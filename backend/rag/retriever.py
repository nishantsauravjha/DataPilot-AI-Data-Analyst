from __future__ import annotations

from dataclasses import dataclass
from typing import Any

from backend.core.config import settings
from backend.rag.embedder import EmbeddingService
from backend.rag.vector_store import QdrantVectorStore


@dataclass(frozen=True)
class RetrievedChunk:
    chunk_id: str
    document_id: str
    page_id: str
    text: str
    score: float
    page_number: int | None
    source_name: str | None
    metadata: dict[str, Any]


class RAGRetriever:
    """
    Production-oriented semantic retrieval layer.

    Query
      ↓
    Embedding
      ↓
    Qdrant
      ↓
    Top-K candidates
      ↓
    Relevance filtering
      ↓
    Duplicate/near-duplicate removal
      ↓
    Final context
    """

    DEFAULT_MIN_SCORE = 0.20

    def __init__(
        self,
        embedder: EmbeddingService | None = None,
        vector_store: QdrantVectorStore | None = None,
        min_score: float | None = None,
    ) -> None:

        self.embedder = (
            embedder
            or EmbeddingService()
        )

        self.vector_store = (
            vector_store
            or QdrantVectorStore()
        )

        configured_score = getattr(
            settings,
            "RAG_MIN_SCORE",
            self.DEFAULT_MIN_SCORE,
        )

        self.min_score = (
            float(min_score)
            if min_score is not None
            else float(configured_score)
        )

        if not 0.0 <= self.min_score <= 1.0:
            raise ValueError(
                "RAG_MIN_SCORE must be between 0 and 1."
            )

    def retrieve(
        self,
        question: str,
        *,
        top_k: int | None = None,
        document_id: str | None = None,
    ) -> list[RetrievedChunk]:

        if not isinstance(question, str):
            raise TypeError(
                "Question must be a string."
            )

        question = question.strip()

        if not question:
            raise ValueError(
                "Question cannot be empty."
            )

        requested_top_k = (
            int(top_k)
            if top_k is not None
            else int(settings.RAG_TOP_K)
        )

        if requested_top_k <= 0:
            raise ValueError(
                "top_k must be greater than zero."
            )

        query_vector = (
            self.embedder.embed_text(question)
        )

        # Retrieve a few extra candidates because
        # filtering/deduplication will reduce the final set.
        candidate_k = max(
            requested_top_k * 2,
            requested_top_k + 3,
        )

        points = self.vector_store.search(
            query_vector,
            top_k=candidate_k,
            document_id=document_id,
        )

        results: list[RetrievedChunk] = []

        for point in points:

            payload = point.payload or {}

            score = float(
                point.score or 0.0
            )

            # Weak semantic matches should not reach
            # the generation model.
            if score < self.min_score:
                continue

            text = str(
                payload.get(
                    "text",
                    "",
                )
            ).strip()

            if not text:
                continue

            results.append(
                RetrievedChunk(
                    chunk_id=str(
                        payload.get(
                            "chunk_id",
                            point.id,
                        )
                    ),
                    document_id=str(
                        payload.get(
                            "document_id",
                            "",
                        )
                    ),
                    page_id=str(
                        payload.get(
                            "page_id",
                            "",
                        )
                    ),
                    text=text,
                    score=score,
                    page_number=(
                        int(payload["page_number"])
                        if payload.get(
                            "page_number"
                        ) is not None
                        else None
                    ),
                    source_name=(
                        str(
                            payload["source_name"]
                        )
                        if payload.get(
                            "source_name"
                        )
                        else None
                    ),
                    metadata=payload,
                )
            )

        # Highest relevance first.
        results.sort(
            key=lambda item: item.score,
            reverse=True,
        )

        return self._deduplicate(
            results,
            limit=requested_top_k,
        )

    @staticmethod
    def _deduplicate(
        chunks: list[RetrievedChunk],
        *,
        limit: int,
    ) -> list[RetrievedChunk]:
        """
        Remove exact duplicate chunks and chunks whose
        text is substantially contained in an already
        selected chunk.

        This prevents the LLM from receiving several
        almost-identical chunks from the same PDF page.
        """

        selected: list[RetrievedChunk] = []

        seen_ids: set[str] = set()
        seen_text: set[str] = set()

        for chunk in chunks:

            if chunk.chunk_id in seen_ids:
                continue

            normalized = (
                " ".join(
                    chunk.text.lower().split()
                )
            )

            if not normalized:
                continue

            if normalized in seen_text:
                continue

            # Containment check for overlapping chunks.
            duplicate = False

            for existing in selected:

                existing_text = (
                    " ".join(
                        existing.text.lower().split()
                    )
                )

                shorter = min(
                    len(normalized),
                    len(existing_text),
                )

                if shorter < 80:
                    continue

                if (
                    normalized in existing_text
                    or existing_text in normalized
                ):
                    duplicate = True
                    break

            if duplicate:
                continue

            seen_ids.add(
                chunk.chunk_id
            )

            seen_text.add(
                normalized
            )

            selected.append(chunk)

            if len(selected) >= limit:
                break

        return selected