from __future__ import annotations

from typing import Any

from qdrant_client import QdrantClient
from qdrant_client.models import (
    Distance,
    FieldCondition,
    Filter,
    MatchValue,
    PointStruct,
    VectorParams,
)

from backend.core.config import settings


class QdrantVectorStore:
    """
    Qdrant-backed vector store for DataPilot RAG.

    PostgreSQL is the source of truth for document/page/chunk
    metadata.

    Qdrant stores the corresponding embedding vectors.
    """

    def __init__(
        self,
        client: QdrantClient | None = None,
    ) -> None:

        self.client = client or QdrantClient(
            url=settings.QDRANT_URL,
            api_key=settings.QDRANT_API_KEY or None,
        )

        self.collection_name = settings.QDRANT_COLLECTION

    # =========================================================
    # COLLECTION
    # =========================================================

    def ensure_collection(
        self,
        dimension: int,
    ) -> None:

        if dimension <= 0:
            raise ValueError(
                "Embedding dimension must be positive."
            )

        if self.client.collection_exists(
            self.collection_name
        ):

            collection = self.client.get_collection(
                self.collection_name
            )

            existing_size = (
                collection.config.params.vectors.size
            )

            if existing_size != dimension:
                raise RuntimeError(
                    "Qdrant collection dimension mismatch: "
                    f"existing={existing_size}, "
                    f"requested={dimension}"
                )

            return

        self.client.create_collection(
            collection_name=self.collection_name,
            vectors_config=VectorParams(
                size=dimension,
                distance=Distance.COSINE,
            ),
        )

    # =========================================================
    # SINGLE UPSERT
    # =========================================================

    def upsert(
        self,
        *,
        point_id: str,
        vector: list[float],
        payload: dict[str, Any],
    ) -> None:

        if not point_id:
            raise ValueError(
                "point_id cannot be empty."
            )

        if not vector:
            raise ValueError(
                "vector cannot be empty."
            )

        self.ensure_collection(
            dimension=len(vector)
        )

        self.client.upsert(
            collection_name=self.collection_name,
            points=[
                PointStruct(
                    id=point_id,
                    vector=vector,
                    payload=payload,
                )
            ],
        )

    # =========================================================
    # BULK UPSERT
    # =========================================================

    def upsert_many(
        self,
        points: list[PointStruct],
        dimension: int,
    ) -> None:

        if not points:
            return

        if dimension <= 0:
            raise ValueError(
                "Embedding dimension must be positive."
            )

        self.ensure_collection(
            dimension=dimension
        )

        self.client.upsert(
            collection_name=self.collection_name,
            points=points,
        )

    # =========================================================
    # DOCUMENT CLEANUP
    # =========================================================

    def delete_document(
        self,
        document_id: str,
    ) -> None:
        """
        Delete every Qdrant point belonging to a document.

        This operation is intentionally idempotent.

        If:
            - the collection does not exist, or
            - the document has no vectors

        nothing happens.
        """

        if not document_id:
            raise ValueError(
                "document_id cannot be empty."
            )

        if not self.client.collection_exists(
            self.collection_name
        ):
            return

        document_filter = Filter(
            must=[
                FieldCondition(
                    key="document_id",
                    match=MatchValue(
                        value=document_id
                    ),
                )
            ]
        )

        self.client.delete(
            collection_name=self.collection_name,
            points_selector=document_filter,
        )

    # =========================================================
    # SEARCH
    # =========================================================

    def search(
        self,
        vector: list[float],
        *,
        top_k: int = 5,
        document_id: str | None = None,
    ) -> list[Any]:

        if not vector:
            raise ValueError(
                "vector cannot be empty."
            )

        if top_k <= 0:
            raise ValueError(
                "top_k must be positive."
            )

        if not self.client.collection_exists(
            self.collection_name
        ):
            return []

        query_filter = None

        if document_id:

            query_filter = Filter(
                must=[
                    FieldCondition(
                        key="document_id",
                        match=MatchValue(
                            value=document_id
                        ),
                    )
                ]
            )

        result = self.client.query_points(
            collection_name=self.collection_name,
            query=vector,
            query_filter=query_filter,
            limit=top_k,
            with_payload=True,
        )

        return result.points