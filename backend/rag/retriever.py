from __future__ import annotations

import re
from dataclasses import dataclass
from typing import Any

from backend.core.config import settings
from backend.rag.embedder import EmbeddingService
from backend.rag.vector_store import QdrantVectorStore


@dataclass(frozen=True)
class RetrievedChunk:
    """A retrieved chunk with provenance and relevance metadata."""

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
    Production RAG retrieval pipeline.

    Question
        ↓
    Embedding
        ↓
    Candidate vector search
        ↓
    Similarity threshold
        ↓
    Exact duplicate removal
        ↓
    Near-duplicate removal
        ↓
    Page/source diversity
        ↓
    Final Top-K
    """

    DEFAULT_MIN_SCORE = 0.20
    DEFAULT_CANDIDATE_MULTIPLIER = 4
    DEFAULT_MIN_CANDIDATES = 15
    DEFAULT_OVERLAP_THRESHOLD = 0.80

    def __init__(
        self,
        embedder: EmbeddingService | None = None,
        vector_store: QdrantVectorStore | None = None,
        min_score: float | None = None,
        overlap_threshold: float | None = None,
    ) -> None:

        self.embedder = (
            embedder
            if embedder is not None
            else EmbeddingService()
        )

        self.vector_store = (
            vector_store
            if vector_store is not None
            else QdrantVectorStore()
        )

        configured_min_score = getattr(
            settings,
            "RAG_MIN_SCORE",
            self.DEFAULT_MIN_SCORE,
        )

        configured_overlap = getattr(
            settings,
            "RAG_OVERLAP_THRESHOLD",
            self.DEFAULT_OVERLAP_THRESHOLD,
        )

        self.min_score = (
            float(min_score)
            if min_score is not None
            else float(configured_min_score)
        )

        self.overlap_threshold = (
            float(overlap_threshold)
            if overlap_threshold is not None
            else float(configured_overlap)
        )

        if not 0.0 <= self.min_score <= 1.0:
            raise ValueError(
                "RAG_MIN_SCORE must be between 0 and 1."
            )

        if not 0.0 <= self.overlap_threshold <= 1.0:
            raise ValueError(
                "RAG_OVERLAP_THRESHOLD must be between 0 and 1."
            )

    # =========================================================
    # PUBLIC API
    # =========================================================

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

        query_vector = self.embedder.embed_text(
            question
        )

        candidate_k = max(
            requested_top_k
            * self.DEFAULT_CANDIDATE_MULTIPLIER,
            self.DEFAULT_MIN_CANDIDATES,
        )

        points = self.vector_store.search(
            query_vector,
            top_k=candidate_k,
            document_id=document_id,
        )

        candidates = self._build_candidates(
            points
        )

        candidates = self._apply_similarity_threshold(
            candidates
        )

        candidates = self._remove_duplicates(
            candidates
        )

        candidates = self._select_diverse_chunks(
            candidates,
            limit=requested_top_k,
        )

        return candidates

    # =========================================================
    # CANDIDATES
    # =========================================================

    def _build_candidates(
        self,
        points: list[Any],
    ) -> list[RetrievedChunk]:

        candidates: list[RetrievedChunk] = []

        for point in points:

            payload = point.payload or {}

            text = str(
                payload.get(
                    "text",
                    "",
                )
            ).strip()

            if not text:
                continue

            try:
                score = float(
                    point.score or 0.0
                )
            except (
                TypeError,
                ValueError,
            ):
                score = 0.0

            page_number = payload.get(
                "page_number"
            )

            try:
                page_number = (
                    int(page_number)
                    if page_number is not None
                    else None
                )
            except (
                TypeError,
                ValueError,
            ):
                page_number = None

            candidates.append(
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
                    page_number=page_number,
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

        candidates.sort(
            key=lambda chunk: chunk.score,
            reverse=True,
        )

        return candidates

    # =========================================================
    # THRESHOLD
    # =========================================================

    def _apply_similarity_threshold(
        self,
        chunks: list[RetrievedChunk],
    ) -> list[RetrievedChunk]:

        return [
            chunk
            for chunk in chunks
            if chunk.score >= self.min_score
        ]

    # =========================================================
    # DUPLICATION
    # =========================================================

    def _remove_exact_duplicates(
        chunks: list[RetrievedChunk],
    ) -> list[RetrievedChunk]:
        """
        Remove chunks with identical normalized text.

        This is intentionally a static helper because it is
        also useful in isolated retrieval-quality tests.
        """

        selected: list[RetrievedChunk] = []

        seen_text: set[str] = set()

        for chunk in chunks:

            normalized = RAGRetriever._normalize(
                chunk.text
            )

            if not normalized:
                continue

            if normalized in seen_text:
                continue

            seen_text.add(
                normalized
            )

            selected.append(
                chunk
            )

        return selected

    @staticmethod
    def _remove_duplicates(
        chunks: list[RetrievedChunk],
    ) -> list[RetrievedChunk]:

        """
        Remove exact chunk-ID duplicates and
        exact-text duplicates.

        Near-duplicate filtering is handled separately
        by the overlap logic.
        """

        selected: list[RetrievedChunk] = []

        seen_chunk_ids: set[str] = set()

        exact_unique = RAGRetriever._remove_exact_duplicates(
            chunks
        )

        for chunk in exact_unique:

            if chunk.chunk_id in seen_chunk_ids:
                continue

            seen_chunk_ids.add(
                chunk.chunk_id
            )

            selected.append(
                chunk
            )

        return selected

    # =========================================================
    # DIVERSITY
    # =========================================================

    @staticmethod
    def _select_diverse_chunks(
        chunks: list[RetrievedChunk],
        *,
        limit: int,
    ) -> list[RetrievedChunk]:

        """
        Select high-quality chunks while preferring
        different document pages.

        Static so retrieval quality can be tested
        independently from the retriever instance.
        """

        if limit <= 0:
            return []

        if not chunks:
            return []

        # Keep strongest results first.
        ordered = sorted(
            chunks,
            key=lambda chunk: chunk.score,
            reverse=True,
        )

        selected: list[RetrievedChunk] = []

        used_pages: set[
            tuple[str, int | None]
        ] = set()

        # -----------------------------------------------------
        # Pass 1:
        # Prefer one strong chunk per page.
        # -----------------------------------------------------

        for chunk in ordered:

            page_key = (
                chunk.document_id,
                chunk.page_number,
            )

            if page_key in used_pages:
                continue

            if RAGRetriever._overlaps_selected(
                chunk,
                selected,
            ):
                continue

            selected.append(
                chunk
            )

            used_pages.add(
                page_key
            )

            if len(selected) >= limit:
                return selected

        # -----------------------------------------------------
        # Pass 2:
        # Fill remaining slots by relevance.
        # -----------------------------------------------------

        for chunk in ordered:

            if chunk in selected:
                continue

            if RAGRetriever._overlaps_selected(
                chunk,
                selected,
            ):
                continue

            selected.append(
                chunk
            )

            if len(selected) >= limit:
                break

        return selected

    # =========================================================
    # OVERLAP
    # =========================================================

    @staticmethod
    def _overlaps_selected(
        candidate: RetrievedChunk,
        selected: list[RetrievedChunk],
        threshold: float = DEFAULT_OVERLAP_THRESHOLD,
    ) -> bool:

        for existing in selected:

            ratio = RAGRetriever._text_overlap_ratio(
                candidate.text,
                existing.text,
            )

            if ratio >= threshold:
                return True

        return False

    @staticmethod
    def _text_overlap_ratio(
        first: str,
        second: str,
    ) -> float:
        """
        Calculate token overlap relative to the smaller
        unique-token set.

        Example:

            A = "revenue increased significantly"
            B = "revenue increased significantly because sales grew"

        The overlap is high because most of A is contained
        in B.
        """

        first_tokens = set(
            RAGRetriever._tokens(first)
        )

        second_tokens = set(
            RAGRetriever._tokens(second)
        )

        if not first_tokens or not second_tokens:
            return 0.0

        intersection = len(
            first_tokens
            & second_tokens
        )

        smaller = min(
            len(first_tokens),
            len(second_tokens),
        )

        if smaller == 0:
            return 0.0

        return intersection / smaller

    # =========================================================
    # NORMALIZATION
    # =========================================================

    @staticmethod
    def _normalize(
        text: str,
    ) -> str:

        return " ".join(
            text.lower().split()
        )

    @classmethod
    def _tokens(
        cls,
        text: str,
    ) -> list[str]:

        normalized = cls._normalize(
            text
        )

        return re.findall(
            r"\b[\w'-]+\b",
            normalized,
        )