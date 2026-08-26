from __future__ import annotations

import hashlib
import re
import uuid
from pathlib import Path
from typing import Any

from qdrant_client.models import PointStruct
from sqlalchemy import text

from backend.core.config import settings
from backend.database.connection import engine
from backend.ingestion.pdf_loader import load_pdf_pages
from backend.rag.chunker import chunk_text
from backend.rag.embedder import EmbeddingService
from backend.rag.vector_store import QdrantVectorStore


DEFAULT_DOMAIN = "General"
DEFAULT_COLLECTION = "DataPilot Documents"
DEFAULT_BUCKET = "datapilot-local"


VALID_DOCUMENT_STATUSES = {
    "UPLOADED",
    "PARSING",
    "OCR_RUNNING",
    "CHUNKING",
    "EMBEDDING",
    "INDEXED",
    "FAILED",
}


class RAGIngestionService:
    """
    End-to-end PDF ingestion pipeline.

    Pipeline:

        PDF
          ↓
        SHA-256 checksum
          ↓
        idempotency check
          ↓
        cleanup previous failed state
          ↓
        PDF extraction
          ↓
        document registration
          ↓
        page registration
          ↓
        text chunking
          ↓
        embedding generation
          ↓
        PostgreSQL chunk metadata
          ↓
        Qdrant vector indexing
          ↓
        document marked INDEXED

    Important design properties:

    1. Idempotent
       Re-ingesting an already indexed file does not duplicate it.

    2. Retry-safe
       Failed/incomplete ingestion is cleaned before retry.

    3. PostgreSQL source of truth
       Documents/pages/chunks live in PostgreSQL.

    4. Qdrant vector lifecycle
       Qdrant vectors are deleted when a document is reset.

    5. Valid database statuses
       Only statuses allowed by the knowledge.documents
       CHECK constraint are used.
    """

    def __init__(
        self,
        embedder: EmbeddingService | None = None,
        vector_store: QdrantVectorStore | None = None,
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

    # ========================================================
    # PUBLIC API
    # ========================================================

    def ingest_pdf(
        self,
        file_path: str | Path,
    ) -> dict[str, Any]:
        """
        Ingest a PDF into PostgreSQL and Qdrant.

        Behavior:

        - New file:
            full ingestion

        - Already INDEXED:
            return existing result

        - Previous FAILED/PARSING/CHUNKING/EMBEDDING:
            remove previous state and retry from scratch
        """

        path = Path(file_path)

        # ----------------------------------------------------
        # Validate file
        # ----------------------------------------------------

        self._validate_pdf(path)

        raw_bytes = path.read_bytes()

        if not raw_bytes:
            raise ValueError(
                "PDF file is empty."
            )

        # ----------------------------------------------------
        # File checksum
        # ----------------------------------------------------

        checksum = hashlib.sha256(
            raw_bytes
        ).hexdigest()

        # ----------------------------------------------------
        # Idempotency / retry handling
        # ----------------------------------------------------

        existing = (
            self._find_document_by_checksum(
                checksum
            )
        )

        if existing:

            existing_status = (
                existing["processing_status"]
            )

            # ----------------------------------------------
            # Already indexed
            # ----------------------------------------------

            if existing_status == "INDEXED":

                return {
                    "document_id": str(
                        existing["document_id"]
                    ),
                    "filename": existing[
                        "original_filename"
                    ],
                    "page_count": existing[
                        "page_count"
                    ],
                    "chunk_count": existing[
                        "chunk_count"
                    ],
                    "embedding_model": (
                        settings.EMBEDDING_MODEL
                    ),
                    "embedding_dimension": (
                        self._get_document_embedding_dimension(
                            existing["document_id"]
                        )
                    ),
                    "status": "ALREADY_INDEXED",
                }

            # ----------------------------------------------
            # Previous attempt incomplete
            # ----------------------------------------------

            self._cleanup_document(
                existing["document_id"]
            )

        # ----------------------------------------------------
        # Parse PDF
        # ----------------------------------------------------

        pages = load_pdf_pages(path)

        pages = [
            page
            for page in pages
            if page.text
            and page.text.strip()
        ]

        if not pages:

            raise ValueError(
                "No extractable text found in PDF."
            )

        # ----------------------------------------------------
        # Create document
        # ----------------------------------------------------

        document_id = self._create_document(
            path=path,
            checksum=checksum,
            page_count=len(pages),
        )

        try:

            # ------------------------------------------------
            # CHUNKING
            # ------------------------------------------------

            self._set_document_status(
                document_id,
                "CHUNKING",
            )

            all_points: list[PointStruct] = []
            all_chunk_ids: list[uuid.UUID] = []

            total_chunks = 0

            # ------------------------------------------------
            # Process pages
            # ------------------------------------------------

            for page in pages:

                page_id = self._create_page(
                    document_id=document_id,
                    page_number=page.page_number,
                    text_value=page.text,
                )

                chunks = chunk_text(
                    page.text,
                    chunk_size=settings.CHUNK_SIZE,
                    chunk_overlap=settings.CHUNK_OVERLAP,
                )

                if not chunks:
                    continue

                # --------------------------------------------
                # Prepare embedding texts
                # --------------------------------------------

                chunk_texts = [
                    chunk.text
                    for chunk in chunks
                ]

                # --------------------------------------------
                # EMBEDDING
                # --------------------------------------------

                self._set_document_status(
                    document_id,
                    "EMBEDDING",
                )

                embeddings = (
                    self.embedder.embed_documents(
                        chunk_texts
                    )
                )

                if len(embeddings) != len(chunks):

                    raise RuntimeError(
                        "Embedding count does not match "
                        "chunk count."
                    )

                # --------------------------------------------
                # Calculate stride
                # --------------------------------------------

                stride = (
                    settings.CHUNK_SIZE
                    - settings.CHUNK_OVERLAP
                )

                if stride <= 0:

                    raise ValueError(
                        "CHUNK_SIZE must be greater than "
                        "CHUNK_OVERLAP."
                    )

                # --------------------------------------------
                # Persist chunks + vectors
                # --------------------------------------------

                for index, (
                    chunk,
                    embedding,
                ) in enumerate(
                    zip(
                        chunks,
                        embeddings,
                        strict=True,
                    ),
                    start=1,
                ):

                    chunk_id = uuid.uuid4()

                    # ----------------------------------------
                    # Character offsets
                    # ----------------------------------------

                    start = (
                        chunk.chunk_index
                        * stride
                    )

                    end = (
                        start
                        + len(chunk.text)
                    )

                    # ----------------------------------------
                    # Deterministic chunk checksum
                    #
                    # The database has a GLOBAL UNIQUE
                    # constraint on content_checksum.
                    #
                    # Therefore the checksum is scoped to:
                    #
                    # document + page + chunk text
                    #
                    # This prevents identical chunks in
                    # different documents from colliding.
                    # ----------------------------------------

                    content_checksum = (
                        self._calculate_chunk_checksum(
                            document_id=document_id,
                            page_number=(
                                page.page_number
                            ),
                            chunk_index=index,
                            text_value=chunk.text,
                        )
                    )

                    # ----------------------------------------
                    # PostgreSQL metadata
                    # ----------------------------------------

                    self._create_chunk(
                        chunk_id=chunk_id,
                        page_id=page_id,
                        chunk_index=index,
                        text_value=chunk.text,
                        character_start=max(
                            0,
                            start,
                        ),
                        character_end=end,
                        token_count=len(
                            re.findall(
                                r"\S+",
                                chunk.text,
                            )
                        ),
                        content_checksum=(
                            content_checksum
                        ),
                    )

                    all_chunk_ids.append(
                        chunk_id
                    )

                    # ----------------------------------------
                    # Qdrant point
                    # ----------------------------------------

                    all_points.append(
                        PointStruct(
                            id=str(chunk_id),
                            vector=embedding,
                            payload={
                                "chunk_id": str(
                                    chunk_id
                                ),
                                "document_id": str(
                                    document_id
                                ),
                                "page_id": str(
                                    page_id
                                ),
                                "page_number": (
                                    page.page_number
                                ),
                                "chunk_index": index,
                                "text": chunk.text,
                                "source_name": (
                                    path.name
                                ),
                            },
                        )
                    )

                    total_chunks += 1

                # --------------------------------------------
                # Page statistics
                # --------------------------------------------

                self._update_page_chunk_count(
                    page_id=page_id,
                    count=len(chunks),
                )

            # ------------------------------------------------
            # Validate chunks
            # ------------------------------------------------

            if not all_points:

                raise ValueError(
                    "No chunks were generated."
                )

            # ------------------------------------------------
            # Embedding dimension
            # ------------------------------------------------

            dimension = len(
                all_points[0].vector
            )

            if dimension <= 0:

                raise ValueError(
                    "Generated embedding dimension "
                    "is invalid."
                )

            # ------------------------------------------------
            # VECTOR INDEXING
            # ------------------------------------------------

            self.vector_store.upsert_many(
                all_points,
                dimension=dimension,
            )

            # ------------------------------------------------
            # Update chunk metadata
            # ------------------------------------------------

            self._mark_chunks_indexed(
                chunk_ids=all_chunk_ids,
                dimension=dimension,
            )

            # ------------------------------------------------
            # Finalize document
            # ------------------------------------------------

            self._finalize_document(
                document_id=document_id,
                page_count=len(pages),
                chunk_count=total_chunks,
            )

            # ------------------------------------------------
            # Return result
            # ------------------------------------------------

            return {
                "document_id": str(
                    document_id
                ),
                "filename": path.name,
                "page_count": len(pages),
                "chunk_count": total_chunks,
                "embedding_model": (
                    settings.EMBEDDING_MODEL
                ),
                "embedding_dimension": dimension,
                "status": "INDEXED",
            }

        except Exception as exc:

            # ----------------------------------------------
            # Mark failed
            # ----------------------------------------------

            try:

                self._set_document_failed(
                    document_id=document_id,
                    error=str(exc),
                )

            except Exception:
                # Never hide the original ingestion error.
                pass

            raise

    # ========================================================
    # VALIDATION
    # ========================================================

    @staticmethod
    def _validate_pdf(
        path: Path,
    ) -> None:

        if not path.exists():

            raise FileNotFoundError(
                f"File not found: {path}"
            )

        if not path.is_file():

            raise ValueError(
                f"Path is not a file: {path}"
            )

        if path.suffix.lower() != ".pdf":

            raise ValueError(
                f"Expected a PDF file, got: "
                f"{path.name}"
            )

    # ========================================================
    # CHECKSUM
    # ========================================================

    @staticmethod
    def _calculate_chunk_checksum(
        *,
        document_id: uuid.UUID,
        page_number: int,
        chunk_index: int,
        text_value: str,
    ) -> str:
        """
        Generate a deterministic SHA-256 checksum.

        The database currently has:

            UNIQUE(content_checksum)

        Therefore identical text in different documents
        cannot share the raw text checksum.

        We scope it using document/page/chunk identity.
        """

        value = (
            f"{document_id}:"
            f"{page_number}:"
            f"{chunk_index}:"
            f"{text_value}"
        )

        return hashlib.sha256(
            value.encode("utf-8")
        ).hexdigest()

    # ========================================================
    # DOCUMENT LOOKUP
    # ========================================================

    def _find_document_by_checksum(
        self,
        checksum: str,
    ) -> dict[str, Any] | None:
        """
        Find a document by its source file checksum.
        """

        with engine.begin() as connection:

            row = connection.execute(
                text(
                    """
                    SELECT
                        document_id,
                        original_filename,
                        processing_status,
                        page_count,
                        chunk_count
                    FROM knowledge.documents
                    WHERE checksum_sha256 = :checksum
                    LIMIT 1
                    """
                ),
                {
                    "checksum": checksum,
                },
            ).mappings().first()

            if row is None:
                return None

            return dict(row)

    # ========================================================
    # DOCUMENT CLEANUP
    # ========================================================

    def _cleanup_document(
        self,
        document_id,
    ) -> None:
        """
        Remove all persisted state belonging to a document.

        Order:

            Qdrant vectors
                ↓
            PostgreSQL document
                ↓ CASCADE
            pages
                ↓ CASCADE
            chunks

        This method is idempotent.
        """

        # ----------------------------------------------------
        # Remove vectors first
        # ----------------------------------------------------

        self.vector_store.delete_document(
            str(document_id)
        )

        # ----------------------------------------------------
        # Delete document metadata
        #
        # knowledge.pages has:
        #
        # ON DELETE CASCADE
        #
        # and knowledge.chunks has:
        #
        # ON DELETE CASCADE
        # ----------------------------------------------------

        with engine.begin() as connection:

            connection.execute(
                text(
                    """
                    DELETE FROM knowledge.documents
                    WHERE document_id = :document_id
                    """
                ),
                {
                    "document_id": document_id,
                },
            )

    # ========================================================
    # DOCUMENT
    # ========================================================

    def _create_document(
        self,
        *,
        path: Path,
        checksum: str,
        page_count: int,
    ) -> uuid.UUID:
        """
        Register the PDF in knowledge.documents.

        Database constraint requires:

            pdf  ✅
            .pdf ❌
        """

        file_extension = (
            path.suffix
            .lstrip(".")
            .lower()
        )

        if not file_extension:

            raise ValueError(
                "Unable to determine file extension "
                f"for: {path.name}"
            )

        if "." in file_extension:

            raise ValueError(
                "file_extension must not contain '.'."
            )

        if file_extension != "pdf":

            raise ValueError(
                "RAGIngestionService only supports PDF. "
                f"Got: {file_extension}"
            )

        with engine.begin() as connection:

            # ----------------------------------------------
            # Race-safe existing check
            # ----------------------------------------------

            existing = connection.execute(
                text(
                    """
                    SELECT document_id
                    FROM knowledge.documents
                    WHERE checksum_sha256 = :checksum
                    LIMIT 1
                    """
                ),
                {
                    "checksum": checksum,
                },
            ).scalar_one_or_none()

            if existing:

                return existing

            # ----------------------------------------------
            # Default domain
            # ----------------------------------------------

            domain_id = connection.execute(
                text(
                    """
                    SELECT domain_id
                    FROM knowledge.domains
                    WHERE slug = 'general'
                    LIMIT 1
                    """
                )
            ).scalar_one_or_none()

            if domain_id is None:

                domain_id = connection.execute(
                    text(
                        """
                        INSERT INTO knowledge.domains
                        (
                            domain_name,
                            description,
                            slug
                        )
                        VALUES
                        (
                            :name,
                            :description,
                            'general'
                        )
                        RETURNING domain_id
                        """
                    ),
                    {
                        "name": DEFAULT_DOMAIN,
                        "description": (
                            "Default DataPilot "
                            "knowledge domain."
                        ),
                    },
                ).scalar_one()

            # ----------------------------------------------
            # Default collection
            # ----------------------------------------------

            collection_id = connection.execute(
                text(
                    """
                    SELECT collection_id
                    FROM knowledge.collections
                    WHERE domain_id = :domain_id
                      AND slug = 'datapilot-documents'
                    LIMIT 1
                    """
                ),
                {
                    "domain_id": domain_id,
                },
            ).scalar_one_or_none()

            if collection_id is None:

                collection_id = connection.execute(
                    text(
                        """
                        INSERT INTO knowledge.collections
                        (
                            domain_id,
                            collection_name,
                            description,
                            slug
                        )
                        VALUES
                        (
                            :domain_id,
                            :name,
                            :description,
                            'datapilot-documents'
                        )
                        RETURNING collection_id
                        """
                    ),
                    {
                        "domain_id": domain_id,
                        "name": DEFAULT_COLLECTION,
                        "description": (
                            "Documents indexed by "
                            "DataPilot RAG."
                        ),
                    },
                ).scalar_one()

            # ----------------------------------------------
            # Create document
            # ----------------------------------------------

            return connection.execute(
                text(
                    """
                    INSERT INTO knowledge.documents
                    (
                        collection_id,
                        document_title,
                        original_filename,
                        mime_type,
                        file_extension,
                        document_type,
                        file_size_bytes,
                        bucket_name,
                        object_path,
                        checksum_sha256,
                        processing_status,
                        page_count
                    )
                    VALUES
                    (
                        :collection_id,
                        :title,
                        :filename,
                        :mime_type,
                        :file_extension,
                        :document_type,
                        :file_size,
                        :bucket_name,
                        :object_path,
                        :checksum,
                        'UPLOADED',
                        :page_count
                    )
                    RETURNING document_id
                    """
                ),
                {
                    "collection_id": collection_id,
                    "title": path.stem,
                    "filename": path.name,
                    "mime_type": "application/pdf",
                    "file_extension": file_extension,
                    "document_type": "PDF",
                    "file_size": path.stat().st_size,
                    "bucket_name": DEFAULT_BUCKET,
                    "object_path": str(path),
                    "checksum": checksum,
                    "page_count": page_count,
                },
            ).scalar_one()

    # ========================================================
    # PAGE
    # ========================================================

    def _create_page(
        self,
        *,
        document_id,
        page_number: int,
        text_value: str,
    ):

        if page_number < 1:

            raise ValueError(
                "page_number must be >= 1."
            )

        with engine.begin() as connection:

            return connection.execute(
                text(
                    """
                    INSERT INTO knowledge.pages
                    (
                        document_id,
                        page_number,
                        page_type,
                        character_count,
                        word_count
                    )
                    VALUES
                    (
                        :document_id,
                        :page_number,
                        'DOCUMENT',
                        :character_count,
                        :word_count
                    )
                    RETURNING page_id
                    """
                ),
                {
                    "document_id": document_id,
                    "page_number": page_number,
                    "character_count": len(
                        text_value
                    ),
                    "word_count": len(
                        re.findall(
                            r"\S+",
                            text_value,
                        )
                    ),
                },
            ).scalar_one()

    # ========================================================
    # CHUNK
    # ========================================================

    def _create_chunk(
        self,
        *,
        chunk_id,
        page_id,
        chunk_index,
        text_value,
        character_start,
        character_end,
        token_count,
        content_checksum,
    ):

        with engine.begin() as connection:

            connection.execute(
                text(
                    """
                    INSERT INTO knowledge.chunks
                    (
                        chunk_id,
                        page_id,
                        chunk_index,
                        chunk_text,
                        chunk_type,
                        character_start,
                        character_end,
                        token_count,
                        content_checksum,
                        chunk_status,
                        is_active
                    )
                    VALUES
                    (
                        :chunk_id,
                        :page_id,
                        :chunk_index,
                        :chunk_text,
                        'TEXT',
                        :character_start,
                        :character_end,
                        :token_count,
                        :checksum,
                        'CREATED',
                        TRUE
                    )
                    """
                ),
                {
                    "chunk_id": chunk_id,
                    "page_id": page_id,
                    "chunk_index": chunk_index,
                    "chunk_text": text_value,
                    "character_start": character_start,
                    "character_end": character_end,
                    "token_count": token_count,
                    "checksum": content_checksum,
                },
            )

    # ========================================================
    # PAGE STATISTICS
    # ========================================================

    def _update_page_chunk_count(
        self,
        *,
        page_id,
        count: int,
    ):

        if count < 0:

            raise ValueError(
                "Chunk count cannot be negative."
            )

        with engine.begin() as connection:

            connection.execute(
                text(
                    """
                    UPDATE knowledge.pages
                    SET
                        chunk_count = :count
                    WHERE page_id = :page_id
                    """
                ),
                {
                    "count": count,
                    "page_id": page_id,
                },
            )

    # ========================================================
    # CHUNK EMBEDDING / INDEX STATUS
    # ========================================================

    def _mark_chunks_indexed(
        self,
        *,
        chunk_ids: list[uuid.UUID],
        dimension: int,
    ):

        if not chunk_ids:
            return

        if dimension <= 0:

            raise ValueError(
                "Embedding dimension must be positive."
            )

        chunk_id_array = (
            "{"
            + ",".join(
                str(chunk_id)
                for chunk_id in chunk_ids
            )
            + "}"
        )

        with engine.begin() as connection:

            connection.execute(
                text(
                    """
                    UPDATE knowledge.chunks
                    SET
                        chunk_status = 'INDEXED',
                        embedding_model = :model,
                        embedding_dimension = :dimension,
                        embedding_generated_at =
                            CURRENT_TIMESTAMP,
                        vector_point_id = chunk_id
                    WHERE chunk_id = ANY(
                        CAST(
                            :chunk_ids AS uuid[]
                        )
                    )
                    """
                ),
                {
                    "model": settings.EMBEDDING_MODEL,
                    "dimension": dimension,
                    "chunk_ids": chunk_id_array,
                },
            )

    # ========================================================
    # DOCUMENT STATUS
    # ========================================================

    def _set_document_status(
        self,
        document_id,
        status: str,
    ):

        if status not in VALID_DOCUMENT_STATUSES:

            raise ValueError(
                f"Invalid document status: {status}"
            )

        with engine.begin() as connection:

            connection.execute(
                text(
                    """
                    UPDATE knowledge.documents
                    SET
                        processing_status = :status,
                        processing_error = NULL,
                        last_processed_at =
                            CURRENT_TIMESTAMP
                    WHERE document_id = :document_id
                    """
                ),
                {
                    "status": status,
                    "document_id": document_id,
                },
            )

    # ========================================================
    # FAILED
    # ========================================================

    def _set_document_failed(
        self,
        *,
        document_id,
        error: str,
    ):

        with engine.begin() as connection:

            connection.execute(
                text(
                    """
                    UPDATE knowledge.documents
                    SET
                        processing_status = 'FAILED',
                        processing_error = :error,
                        last_processed_at =
                            CURRENT_TIMESTAMP
                    WHERE document_id = :document_id
                    """
                ),
                {
                    "document_id": document_id,
                    "error": error[:4000],
                },
            )

    # ========================================================
    # FINALIZE
    # ========================================================

    def _finalize_document(
        self,
        *,
        document_id,
        page_count: int,
        chunk_count: int,
    ):

        if page_count <= 0:

            raise ValueError(
                "page_count must be positive."
            )

        if chunk_count <= 0:

            raise ValueError(
                "chunk_count must be positive."
            )

        with engine.begin() as connection:

            connection.execute(
                text(
                    """
                    UPDATE knowledge.documents
                    SET
                        processing_status = 'INDEXED',
                        page_count = :page_count,
                        chunk_count = :chunk_count,
                        processing_error = NULL,
                        last_processed_at =
                            CURRENT_TIMESTAMP
                    WHERE document_id = :document_id
                    """
                ),
                {
                    "document_id": document_id,
                    "page_count": page_count,
                    "chunk_count": chunk_count,
                },
            )

    # ========================================================
    # EMBEDDING DIMENSION FOR EXISTING DOCUMENT
    # ========================================================

    def _get_document_embedding_dimension(
        self,
        document_id,
    ) -> int | None:
        """
        Retrieve the embedding dimension from the indexed
        chunks of an existing document.
        """

        with engine.begin() as connection:

            value = connection.execute(
                text(
                    """
                    SELECT embedding_dimension
                    FROM knowledge.chunks c
                    JOIN knowledge.pages p
                        ON p.page_id = c.page_id
                    WHERE p.document_id = :document_id
                      AND c.embedding_dimension IS NOT NULL
                    ORDER BY c.chunk_index
                    LIMIT 1
                    """
                ),
                {
                    "document_id": document_id,
                },
            ).scalar_one_or_none()

            if value is None:
                return None

            return int(value)