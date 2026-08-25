-- ============================================================================
-- FILE: 03_knowledge.sql
-- AUTHOR: OmniBrain Database Team
-- DESCRIPTION:
--     Defines the Knowledge schema core tables responsible for organizing
--     enterprise knowledge into domains and collections.

-- DEPENDENCIES:
--     - 00_extensions.sql
--     - 01_schemas.sql
--     - 04_common_functions.sql
-- ============================================================================

SET search_path TO knowledge, public;

-- ============================================================================
-- TABLE: knowledge.domains
-- ============================================================================

CREATE TABLE if NOT EXISTS knowledge.domains (
    domain_id UUID PRIMARY KEY
        DEFAULT gen_random_uuid(),

    domain_name VARCHAR(100) COLLATE "C" NOT NULL,

    description TEXT,

    slug VARCHAR(100) COLLATE "C" NOT NULL,

    is_active BOOLEAN NOT NULL
        DEFAULT TRUE,

    created_at TIMESTAMPTZ NOT NULL
        DEFAULT CURRENT_TIMESTAMP,

    updated_at TIMESTAMPTZ NOT NULL
        DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT uq_domains_name
        UNIQUE (domain_name),

    CONSTRAINT uq_domains_slug
        UNIQUE (slug),

    CONSTRAINT chk_domains_name_not_blank
        CHECK (length(trim(domain_name)) > 0),

    CONSTRAINT chk_domains_slug_format
        CHECK (
            slug ~ '^[a-z0-9]+(-[a-z0-9]+)*$'
        )
);

-- ============================================================================
-- COMMENTS
-- ============================================================================

COMMENT ON TABLE knowledge.domains IS
'Top-level organizational unit for enterprise knowledge.';

COMMENT ON COLUMN knowledge.domains.domain_id IS
'Primary key for the domain.';

COMMENT ON COLUMN knowledge.domains.domain_name IS
'Unique human-readable domain name.';

COMMENT ON COLUMN knowledge.domains.description IS
'Optional description of the domain.';

COMMENT ON COLUMN knowledge.domains.slug IS
'URL-safe unique identifier.';

COMMENT ON COLUMN knowledge.domains.is_active IS
'Whether the domain is active.';

COMMENT ON COLUMN knowledge.domains.created_at IS
'Creation timestamp.';

COMMENT ON COLUMN knowledge.domains.updated_at IS
'Last modification timestamp.';

-- ============================================================================
-- TRIGGER
-- Automatically maintain updated_at
-- ============================================================================

DROP TRIGGER IF EXISTS trg_domains_bu_set_updated_at ON knowledge.domains;

CREATE TRIGGER trg_domains_bu_set_updated_at
BEFORE UPDATE
ON knowledge.domains
FOR EACH ROW
EXECUTE FUNCTION common.set_updated_at();

-- ============================================================================
-- TABLE: knowledge.collections
-- ============================================================================

CREATE TABLE IF NOT EXISTS knowledge.collections (

    collection_id UUID PRIMARY KEY
        DEFAULT gen_random_uuid(),

    domain_id UUID NOT NULL,

    collection_name VARCHAR(100) COLLATE "C" NOT NULL,

    description TEXT,

    slug VARCHAR(100) COLLATE "C" NOT NULL,

    is_active BOOLEAN NOT NULL
        DEFAULT TRUE,

    created_at TIMESTAMPTZ NOT NULL
        DEFAULT CURRENT_TIMESTAMP,

    updated_at TIMESTAMPTZ NOT NULL
        DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT fk_collections_domain
        FOREIGN KEY (domain_id)
        REFERENCES knowledge.domains(domain_id)
        ON DELETE RESTRICT
        ON UPDATE CASCADE,

    CONSTRAINT uq_collections_domain_name
        UNIQUE (domain_id, collection_name),

    CONSTRAINT uq_collections_domain_slug
        UNIQUE (domain_id, slug),

    CONSTRAINT chk_collections_name_not_blank
        CHECK (
            length(trim(collection_name)) > 0
        ),

    CONSTRAINT chk_collections_slug_format
        CHECK (
            slug ~ '^[a-z0-9]+(-[a-z0-9]+)*$'
        )
);

-- ============================================================================
-- INDEXES
-- ============================================================================

CREATE INDEX IF NOT EXISTS idx_collections_domain
ON knowledge.collections(domain_id);

-- ============================================================================
-- COMMENTS
-- ============================================================================

COMMENT ON TABLE knowledge.collections IS
'Logical grouping of documents within a knowledge domain.';

COMMENT ON COLUMN knowledge.collections.collection_id IS
'Primary key for the collection.';

COMMENT ON COLUMN knowledge.collections.domain_id IS
'Parent domain identifier.';

COMMENT ON COLUMN knowledge.collections.collection_name IS
'Human-readable collection name.';

COMMENT ON COLUMN knowledge.collections.description IS
'Optional description of the collection.';

COMMENT ON COLUMN knowledge.collections.slug IS
'URL-safe identifier unique within a domain.';

COMMENT ON COLUMN knowledge.collections.is_active IS
'Whether the collection is active.';

COMMENT ON COLUMN knowledge.collections.created_at IS
'Creation timestamp.';

COMMENT ON COLUMN knowledge.collections.updated_at IS
'Last modification timestamp.';

-- ============================================================================
-- TRIGGER
-- Automatically maintain updated_at
-- ============================================================================

DROP TRIGGER IF EXISTS trg_collections_bu_set_updated_at ON knowledge.collections;

CREATE TRIGGER trg_collections_bu_set_updated_at
BEFORE UPDATE
ON knowledge.collections
FOR EACH ROW
EXECUTE FUNCTION common.set_updated_at();






-- ============================================================================
-- TABLE: knowledge.documents
-- DESCRIPTION:
--     Stores metadata for every uploaded document in OmniBrain.
--
-- NOTES:
--     - Original files are stored in MinIO.
--     - Embeddings are stored in Qdrant.
--     - PostgreSQL stores metadata only.
-- ============================================================================

CREATE TABLE IF NOT EXISTS knowledge.documents (

    ---------------------------------------------------------------------------
    -- Primary Key
    ---------------------------------------------------------------------------

    document_id UUID
        PRIMARY KEY
        DEFAULT gen_random_uuid(),

    ---------------------------------------------------------------------------
    -- Parent Collection
    ---------------------------------------------------------------------------

    collection_id UUID
        NOT NULL,

    owner_user_id UUID,

    ---------------------------------------------------------------------------
    -- Human Metadata
    ---------------------------------------------------------------------------

    document_title VARCHAR(255)
        NOT NULL,

    document_description TEXT,

    ---------------------------------------------------------------------------
    -- Original File Metadata
    ---------------------------------------------------------------------------

    original_filename VARCHAR(255)
        NOT NULL,

    mime_type VARCHAR(100)
        NOT NULL,

    file_extension VARCHAR(20)
        NOT NULL,

    document_type VARCHAR(20)
        NOT NULL,

    file_size_bytes BIGINT
        NOT NULL,

    ---------------------------------------------------------------------------
    -- Object Storage (MinIO)
    ---------------------------------------------------------------------------

    bucket_name VARCHAR(100)
        NOT NULL,

    object_path TEXT
        NOT NULL,

    ---------------------------------------------------------------------------
    -- Integrity
    ---------------------------------------------------------------------------

    checksum_sha256 CHAR(64)
        NOT NULL,

    ---------------------------------------------------------------------------
    -- Processing Pipeline
    ---------------------------------------------------------------------------

    processing_status VARCHAR(30)
        NOT NULL
        DEFAULT 'UPLOADED',

    processing_error TEXT,

    last_processed_at TIMESTAMPTZ,

    ---------------------------------------------------------------------------
    -- Versioning
    ---------------------------------------------------------------------------

    version_number INTEGER
        NOT NULL
        DEFAULT 1,

    ---------------------------------------------------------------------------
    -- Document Statistics
    ---------------------------------------------------------------------------

    language_code CHAR(2),

    page_count INTEGER
        NOT NULL
        DEFAULT 0,

    chunk_count INTEGER
        NOT NULL
        DEFAULT 0,

    image_count INTEGER
        NOT NULL
        DEFAULT 0,

    table_count INTEGER
        NOT NULL
        DEFAULT 0,

    ---------------------------------------------------------------------------
    -- Lifecycle
    ---------------------------------------------------------------------------

    is_active BOOLEAN
        NOT NULL
        DEFAULT TRUE,

    created_at TIMESTAMPTZ
        NOT NULL
        DEFAULT CURRENT_TIMESTAMP,

    updated_at TIMESTAMPTZ
        NOT NULL
        DEFAULT CURRENT_TIMESTAMP,

    ---------------------------------------------------------------------------
    -- Foreign Keys
    ---------------------------------------------------------------------------

    CONSTRAINT fk_documents_collection
        FOREIGN KEY (collection_id)
        REFERENCES knowledge.collections(collection_id)
        ON DELETE RESTRICT
        ON UPDATE CASCADE,

    CONSTRAINT fk_documents_owner
        FOREIGN KEY (owner_user_id)
        REFERENCES auth.users(user_id)
        ON DELETE RESTRICT
        ON UPDATE CASCADE,

    ---------------------------------------------------------------------------
    -- Unique Constraints
    ---------------------------------------------------------------------------

    CONSTRAINT uq_documents_checksum
        UNIQUE (checksum_sha256),

    CONSTRAINT uq_documents_storage_object
        UNIQUE (bucket_name, object_path),

    ---------------------------------------------------------------------------
    -- Validation Constraints
    ---------------------------------------------------------------------------

    CONSTRAINT chk_documents_title_not_blank
        CHECK (
            length(trim(document_title)) > 0
        ),

    CONSTRAINT chk_documents_filename_not_blank
        CHECK (
            length(trim(original_filename)) > 0
        ),

    CONSTRAINT chk_documents_extension_not_blank
        CHECK (
            length(trim(file_extension)) > 0
        ),

    CONSTRAINT chk_documents_extension_format
        CHECK (
            file_extension = lower(file_extension)
            AND file_extension !~ '\.'
        ),

    CONSTRAINT chk_documents_bucket_not_blank
        CHECK (
            length(trim(bucket_name)) > 0
        ),

    CONSTRAINT chk_documents_object_path_not_blank
        CHECK (
            length(trim(object_path)) > 0
        ),

    CONSTRAINT chk_documents_file_size
        CHECK (
            file_size_bytes >= 0
        ),

    CONSTRAINT chk_documents_version
        CHECK (
            version_number >= 1
        ),

    CONSTRAINT chk_documents_page_count
        CHECK (
            page_count >= 0
        ),

    CONSTRAINT chk_documents_chunk_count
        CHECK (
            chunk_count >= 0
        ),

    CONSTRAINT chk_documents_image_count
        CHECK (
            image_count >= 0
        ),

    CONSTRAINT chk_documents_table_count
        CHECK (
            table_count >= 0
        ),

    CONSTRAINT chk_documents_language
        CHECK (
            language_code IS NULL
            OR language_code ~ '^[a-z]{2}$'
        ),

    CONSTRAINT chk_documents_checksum
        CHECK (
            checksum_sha256 ~ '^[A-Fa-f0-9]{64}$'
        ),

    CONSTRAINT chk_documents_type
        CHECK (
            document_type IN (
                'PDF',
                'DOCX',
                'PPTX',
                'XLSX',
                'IMAGE',
                'TEXT',
                'HTML',
                'MARKDOWN',
                'OTHER'
            )
        ),

    CONSTRAINT chk_documents_processing_status
        CHECK (
            processing_status IN (
                'UPLOADED',
                'PARSING',
                'OCR_RUNNING',
                'CHUNKING',
                'EMBEDDING',
                'INDEXED',
                'FAILED'
            )
        )
);

ALTER TABLE knowledge.documents
    ADD COLUMN IF NOT EXISTS owner_user_id UUID;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM pg_constraint
        WHERE conname = 'fk_documents_owner'
          AND conrelid = 'knowledge.documents'::regclass
    ) THEN
        ALTER TABLE knowledge.documents
            ADD CONSTRAINT fk_documents_owner
            FOREIGN KEY (owner_user_id)
            REFERENCES auth.users(user_id)
            ON DELETE RESTRICT
            ON UPDATE CASCADE;
    END IF;
END;
$$;

CREATE INDEX IF NOT EXISTS idx_documents_owner
ON knowledge.documents(owner_user_id);





-- ============================================================================
-- TABLE: knowledge.pages
-- DESCRIPTION:
--     Represents logical pages extracted from uploaded documents.
--
-- NOTES:
--     - A page may originate from a PDF page, DOCX page,
--       PPTX slide, image, HTML section, or OCR output.
--     - Every chunk belongs to exactly one page.
-- ============================================================================

CREATE TABLE IF NOT EXISTS knowledge.pages (

    ---------------------------------------------------------------------------
    -- Primary Key
    ---------------------------------------------------------------------------

    page_id UUID
        PRIMARY KEY
        DEFAULT gen_random_uuid(),

    ---------------------------------------------------------------------------
    -- Parent Document
    ---------------------------------------------------------------------------

    document_id UUID
        NOT NULL,

    ---------------------------------------------------------------------------
    -- Page Information
    ---------------------------------------------------------------------------

    page_number INTEGER
        NOT NULL,

    page_label VARCHAR(225),

    page_type VARCHAR(20)
        NOT NULL
        DEFAULT 'DOCUMENT',

    ---------------------------------------------------------------------------
    -- OCR Information
    ---------------------------------------------------------------------------

    ocr_applied BOOLEAN
        NOT NULL
        DEFAULT FALSE,

    ---------------------------------------------------------------------------
    -- Page Statistics
    ---------------------------------------------------------------------------

    character_count INTEGER
        NOT NULL
        DEFAULT 0,

    word_count INTEGER
        NOT NULL
        DEFAULT 0,

    chunk_count INTEGER
        NOT NULL
        DEFAULT 0,

    image_count INTEGER
        NOT NULL
        DEFAULT 0,

    table_count INTEGER
        NOT NULL
        DEFAULT 0,

    ---------------------------------------------------------------------------
    -- Lifecycle
    ---------------------------------------------------------------------------

    is_active BOOLEAN
        NOT NULL
        DEFAULT TRUE,

    created_at TIMESTAMPTZ
        NOT NULL
        DEFAULT CURRENT_TIMESTAMP,

    updated_at TIMESTAMPTZ
        NOT NULL
        DEFAULT CURRENT_TIMESTAMP,

    ---------------------------------------------------------------------------
    -- Foreign Keys
    ---------------------------------------------------------------------------

    CONSTRAINT fk_pages_document
        FOREIGN KEY (document_id)
        REFERENCES knowledge.documents(document_id)
        ON DELETE CASCADE
        ON UPDATE CASCADE,

    ---------------------------------------------------------------------------
    -- Unique Constraints
    ---------------------------------------------------------------------------

    CONSTRAINT uq_document_page
        UNIQUE (
            document_id,
            page_number
        ),

    ---------------------------------------------------------------------------
    -- Validation
    ---------------------------------------------------------------------------

    CONSTRAINT chk_page_number
        CHECK (
            page_number >= 1
        ),

    CONSTRAINT chk_page_label
        CHECK (
            page_label IS NULL
            OR length(trim(page_label)) > 0
        ),

    CONSTRAINT chk_page_type
        CHECK (
            page_type IN (
                'DOCUMENT',
                'SLIDE',
                'IMAGE',
                'HTML',
                'MARKDOWN',
                'OCR'
            )
        ),

    CONSTRAINT chk_character_count
        CHECK (
            character_count >= 0
        ),

    CONSTRAINT chk_word_count
        CHECK (
            word_count >= 0
        ),

    CONSTRAINT chk_chunk_count
        CHECK (
            chunk_count >= 0
        ),

    CONSTRAINT chk_image_count
        CHECK (
            image_count >= 0
        ),

    CONSTRAINT chk_table_count
        CHECK (
            table_count >= 0
        )
);

-- Production Indexes
CREATE INDEX IF NOT EXISTS idx_pages_document
ON knowledge.pages(document_id);

CREATE INDEX IF NOT EXISTS idx_pages_document_page
ON knowledge.pages(document_id, page_number);

CREATE INDEX IF NOT EXISTS idx_pages_active
ON knowledge.pages(is_active)
WHERE is_active = TRUE;

-- comments
COMMENT ON TABLE knowledge.pages IS
'Represents logical pages extracted from uploaded documents for downstream processing.';

COMMENT ON COLUMN knowledge.pages.page_id IS
'Primary key of the page.';

COMMENT ON COLUMN knowledge.pages.document_id IS
'Parent document identifier.';

COMMENT ON COLUMN knowledge.pages.page_number IS
'Sequential page number within the document.';

COMMENT ON COLUMN knowledge.pages.page_label IS
'Optional display label, such as Roman numerals or slide titles.';

COMMENT ON COLUMN knowledge.pages.page_type IS
'Logical page type independent of the original file format.';

COMMENT ON COLUMN knowledge.pages.ocr_applied IS
'Indicates whether OCR was executed for this page.';

COMMENT ON COLUMN knowledge.pages.character_count IS
'Total number of extracted characters.';

COMMENT ON COLUMN knowledge.pages.word_count IS
'Total number of extracted words.';

COMMENT ON COLUMN knowledge.pages.chunk_count IS
'Number of chunks generated from this page.';

COMMENT ON COLUMN knowledge.pages.image_count IS
'Number of images detected on the page.';

COMMENT ON COLUMN knowledge.pages.table_count IS
'Number of tables detected on the page.';

COMMENT ON COLUMN knowledge.pages.is_active IS
'Indicates whether the page is active.';

COMMENT ON COLUMN knowledge.pages.created_at IS
'Timestamp when the page metadata was created.';

COMMENT ON COLUMN knowledge.pages.updated_at IS
'Timestamp of the last update.';

--Trigger to automatically update the updated_at timestamp before every UPDATE
DROP TRIGGER IF EXISTS trg_pages_bu_set_updated_at ON knowledge.pages;

CREATE TRIGGER trg_pages_bu_set_updated_at
BEFORE UPDATE
ON knowledge.pages
FOR EACH ROW
EXECUTE FUNCTION common.set_updated_at();





-- ============================================================================
-- TABLE: knowledge.chunks
-- DESCRIPTION:
--     Stores the smallest retrievable semantic units extracted from pages.
--
-- NOTES:
--     - Each chunk belongs to exactly one page.
--     - Embeddings are stored in Qdrant.
--     - PostgreSQL stores metadata only.
-- ============================================================================

CREATE TABLE IF NOT EXISTS knowledge.chunks (

    ---------------------------------------------------------------------------
    -- Primary Key
    ---------------------------------------------------------------------------

    chunk_id UUID
        PRIMARY KEY
        DEFAULT gen_random_uuid(),

    ---------------------------------------------------------------------------
    -- Parent Page
    ---------------------------------------------------------------------------

    page_id UUID
        NOT NULL,

    ---------------------------------------------------------------------------
    -- Chunk Ordering
    ---------------------------------------------------------------------------

    chunk_index INTEGER
        NOT NULL,

    ---------------------------------------------------------------------------
    -- Chunk Content
    ---------------------------------------------------------------------------

    chunk_text TEXT
        NOT NULL,

    chunk_type VARCHAR(30)
        NOT NULL
        DEFAULT 'TEXT',

    ---------------------------------------------------------------------------
    -- Character Offsets
    ---------------------------------------------------------------------------

    character_start INTEGER
        NOT NULL,

    character_end INTEGER
        NOT NULL,

    ---------------------------------------------------------------------------
    -- Statistics
    ---------------------------------------------------------------------------

    token_count INTEGER
        NOT NULL,

    ---------------------------------------------------------------------------
    -- Vector Database Metadata
    ---------------------------------------------------------------------------

    vector_point_id UUID,

    embedding_model TEXT,

    embedding_dimension INTEGER,

    embedding_generated_at TIMESTAMPTZ,

    ---------------------------------------------------------------------------
    -- Integrity
    ---------------------------------------------------------------------------

    content_checksum CHAR(64)
        NOT NULL,

    ---------------------------------------------------------------------------
    -- Processing Status
    ---------------------------------------------------------------------------

    chunk_status VARCHAR(20)
        NOT NULL
        DEFAULT 'CREATED',

    ---------------------------------------------------------------------------
    -- Lifecycle
    ---------------------------------------------------------------------------

    is_active BOOLEAN
        NOT NULL
        DEFAULT TRUE,

    created_at TIMESTAMPTZ
        NOT NULL
        DEFAULT CURRENT_TIMESTAMP,

    updated_at TIMESTAMPTZ
        NOT NULL
        DEFAULT CURRENT_TIMESTAMP,

    ---------------------------------------------------------------------------
    -- FOREIGN KEY
    ---------------------------------------------------------------------------

    CONSTRAINT fk_chunks_page
        FOREIGN KEY (page_id)
        REFERENCES knowledge.pages(page_id)
        ON DELETE CASCADE
        ON UPDATE CASCADE,

    ---------------------------------------------------------------------------
    -- UNIQUE CONSTRAINTS
    ---------------------------------------------------------------------------

    CONSTRAINT uq_chunks_page_index
        UNIQUE (
            page_id,
            chunk_index
        ),

    CONSTRAINT uq_chunks_checksum
        UNIQUE (
            content_checksum
        ),

    ---------------------------------------------------------------------------
    -- VALIDATION
    ---------------------------------------------------------------------------

    CONSTRAINT chk_chunk_text_not_blank
        CHECK (
            length(trim(chunk_text)) > 0
        ),

    CONSTRAINT chk_chunk_index
        CHECK (
            chunk_index >= 1
        ),

    CONSTRAINT chk_character_start
        CHECK (
            character_start >= 0
        ),

    CONSTRAINT chk_character_end
        CHECK (
            character_end >= character_start
        ),

    CONSTRAINT chk_token_count
        CHECK (
            token_count >= 0
        ),

    CONSTRAINT chk_embedding_dimension
        CHECK (
            embedding_dimension IS NULL
            OR embedding_dimension > 0
        ),

    CONSTRAINT chk_checksum_format
        CHECK (
            content_checksum ~ '^[A-Fa-f0-9]{64}$'
        ),

    CONSTRAINT chk_chunk_type
        CHECK (
            chunk_type IN (
                'TEXT',
                'TITLE',
                'HEADER',
                'FOOTER',
                'LIST',
                'TABLE',
                'IMAGE_CAPTION',
                'CODE'
            )
        ),

    CONSTRAINT chk_chunk_status
        CHECK (
            chunk_status IN (
                'CREATED',
                'EMBEDDED',
                'INDEXED',
                'FAILED'
            )
        )
);

-- ============================================================================
-- INDEXES
-- ============================================================================

CREATE INDEX IF NOT EXISTS idx_chunks_page
ON knowledge.chunks(page_id);

CREATE INDEX IF NOT EXISTS idx_chunks_page_chunk
ON knowledge.chunks(page_id, chunk_index);

CREATE INDEX IF NOT EXISTS idx_chunks_status
ON knowledge.chunks(chunk_status);

CREATE INDEX IF NOT EXISTS idx_chunks_active
ON knowledge.chunks(is_active)
WHERE is_active = TRUE;

CREATE INDEX IF NOT EXISTS idx_chunks_vector_uuid
ON knowledge.chunks(vector_point_id);

CREATE INDEX IF NOT EXISTS idx_chunks_embedding_model
ON knowledge.chunks(embedding_model);

-- ============================================================================
-- COMMENTS
-- ============================================================================

COMMENT ON TABLE knowledge.chunks IS
'Stores semantic text chunks extracted from document pages.';

COMMENT ON COLUMN knowledge.chunks.chunk_id IS
'Primary key of the chunk.';

COMMENT ON COLUMN knowledge.chunks.page_id IS
'Parent page identifier.';

COMMENT ON COLUMN knowledge.chunks.chunk_index IS
'Sequential position of the chunk within its page.';

COMMENT ON COLUMN knowledge.chunks.chunk_text IS
'Extracted text content of the chunk.';

COMMENT ON COLUMN knowledge.chunks.chunk_type IS
'Logical classification of the chunk.';

COMMENT ON COLUMN knowledge.chunks.character_start IS
'Starting character offset within the page.';

COMMENT ON COLUMN knowledge.chunks.character_end IS
'Ending character offset within the page.';

COMMENT ON COLUMN knowledge.chunks.token_count IS
'Number of language-model tokens in the chunk.';

COMMENT ON COLUMN knowledge.chunks.vector_point_id IS
'Corresponding point identifier stored in the vector database (Qdrant).';

COMMENT ON COLUMN knowledge.chunks.embedding_model IS
'Embedding model used to generate the vector representation.';

COMMENT ON COLUMN knowledge.chunks.embedding_dimension IS
'Dimension of the generated embedding vector.';

COMMENT ON COLUMN knowledge.chunks.embedding_generated_at IS
'Timestamp when the embedding was generated.';

COMMENT ON COLUMN knowledge.chunks.content_checksum IS
'SHA-256 checksum of the chunk content.';

COMMENT ON COLUMN knowledge.chunks.chunk_status IS
'Processing state of the chunk.';

COMMENT ON COLUMN knowledge.chunks.is_active IS
'Whether the chunk is active.';

COMMENT ON COLUMN knowledge.chunks.created_at IS
'Timestamp when the chunk metadata was created.';

COMMENT ON COLUMN knowledge.chunks.updated_at IS
'Timestamp of the most recent modification.';

-- ============================================================================
-- TRIGGER
-- ============================================================================

DROP TRIGGER IF EXISTS trg_chunks_bu_set_updated_at ON knowledge.chunks;

CREATE TRIGGER trg_chunks_bu_set_updated_at
BEFORE UPDATE
ON knowledge.chunks
FOR EACH ROW
EXECUTE FUNCTION common.set_updated_at();






-- ============================================================================
-- TABLE: knowledge.images
-- DESCRIPTION:
--     Stores metadata for images extracted from documents.
--
-- NOTES:
--     - Image binaries are stored in MinIO.
--     - Image embeddings are stored in Qdrant.
--     - PostgreSQL stores metadata only.
-- ============================================================================

CREATE TABLE IF NOT EXISTS knowledge.images (

    ---------------------------------------------------------------------------
    -- Primary Key
    ---------------------------------------------------------------------------

    image_id UUID
        PRIMARY KEY
        DEFAULT gen_random_uuid(),

    ---------------------------------------------------------------------------
    -- Parent Page
    ---------------------------------------------------------------------------

    page_id UUID
        NOT NULL,

    ---------------------------------------------------------------------------
    -- Image Ordering
    ---------------------------------------------------------------------------

    image_index INTEGER
        NOT NULL,

    ---------------------------------------------------------------------------
    -- Original File Metadata
    ---------------------------------------------------------------------------

    original_filename VARCHAR(255)
        NOT NULL,

    image_format VARCHAR(20)
        NOT NULL,

    mime_type VARCHAR(100)
        NOT NULL,

    file_size_bytes BIGINT
        NOT NULL,

    ---------------------------------------------------------------------------
    -- Object Storage (MinIO)
    ---------------------------------------------------------------------------

    bucket_name VARCHAR(100)
        NOT NULL,

    object_path TEXT
        NOT NULL,

    ---------------------------------------------------------------------------
    -- Image Properties
    ---------------------------------------------------------------------------

    width_px INTEGER
        NOT NULL,

    height_px INTEGER
        NOT NULL,

    ---------------------------------------------------------------------------
    -- Bounding Box (Original Page Coordinates)
    ---------------------------------------------------------------------------

    bbox_x DOUBLE PRECISION
        NOT NULL,

    bbox_y DOUBLE PRECISION
        NOT NULL,

    bbox_width DOUBLE PRECISION
        NOT NULL,

    bbox_height DOUBLE PRECISION
        NOT NULL,

    ---------------------------------------------------------------------------
    -- AI Metadata
    ---------------------------------------------------------------------------

    caption TEXT,

    alt_text TEXT,

    ocr_text TEXT,

    ---------------------------------------------------------------------------
    -- Vector Database Metadata
    ---------------------------------------------------------------------------

    vector_point_id UUID,

    embedding_model TEXT,

    embedding_dimension INTEGER,

    embedding_generated_at TIMESTAMPTZ,

    ---------------------------------------------------------------------------
    -- Integrity
    ---------------------------------------------------------------------------

    content_checksum CHAR(64)
        NOT NULL,

    ---------------------------------------------------------------------------
    -- Processing
    ---------------------------------------------------------------------------

    image_status VARCHAR(30)
        NOT NULL
        DEFAULT 'EXTRACTED',

    ---------------------------------------------------------------------------
    -- Lifecycle
    ---------------------------------------------------------------------------

    is_active BOOLEAN
        NOT NULL
        DEFAULT TRUE,

    created_at TIMESTAMPTZ
        NOT NULL
        DEFAULT CURRENT_TIMESTAMP,

    updated_at TIMESTAMPTZ
        NOT NULL
        DEFAULT CURRENT_TIMESTAMP,

    ---------------------------------------------------------------------------
    -- Foreign Key
    ---------------------------------------------------------------------------

    CONSTRAINT fk_images_page
        FOREIGN KEY (page_id)
        REFERENCES knowledge.pages(page_id)
        ON DELETE CASCADE
        ON UPDATE CASCADE,

    ---------------------------------------------------------------------------
    -- Unique Constraints
    ---------------------------------------------------------------------------

    CONSTRAINT uq_images_page_index
        UNIQUE (
            page_id,
            image_index
        ),

    CONSTRAINT uq_images_storage_object
        UNIQUE (
            bucket_name,
            object_path
        ),

    CONSTRAINT uq_images_checksum
        UNIQUE (
            content_checksum
        ),

    ---------------------------------------------------------------------------
    -- Validation
    ---------------------------------------------------------------------------

    CONSTRAINT chk_images_filename_not_blank
        CHECK (
            length(trim(original_filename)) > 0
        ),

    CONSTRAINT chk_images_bucket_not_blank
        CHECK (
            length(trim(bucket_name)) > 0
        ),

    CONSTRAINT chk_images_object_path_not_blank
        CHECK (
            length(trim(object_path)) > 0
        ),

    CONSTRAINT chk_images_index
        CHECK (
            image_index >= 1
        ),

    CONSTRAINT chk_images_file_size
        CHECK (
            file_size_bytes >= 0
        ),

    CONSTRAINT chk_images_width
        CHECK (
            width_px > 0
        ),

    CONSTRAINT chk_images_height
        CHECK (
            height_px > 0
        ),

    CONSTRAINT chk_images_bbox_x
        CHECK (
            bbox_x >= 0
        ),

    CONSTRAINT chk_images_bbox_y
        CHECK (
            bbox_y >= 0
        ),

    CONSTRAINT chk_images_bbox_width
        CHECK (
            bbox_width > 0
        ),

    CONSTRAINT chk_images_bbox_height
        CHECK (
            bbox_height > 0
        ),

    CONSTRAINT chk_images_embedding_dimension
        CHECK (
            embedding_dimension IS NULL
            OR embedding_dimension > 0
        ),

    CONSTRAINT chk_images_checksum
        CHECK (
            content_checksum ~ '^[A-Fa-f0-9]{64}$'
        ),

    CONSTRAINT chk_images_image_format
        CHECK (
            upper(image_format) IN (
                'PNG',
                'JPEG',
                'JPG',
                'WEBP',
                'GIF',
                'BMP',
                'TIFF',
                'SVG',
                'OTHER'
            )
        ),

    CONSTRAINT chk_images_status
        CHECK (
            image_status IN (
                'EXTRACTED',
                'OCR_COMPLETED',
                'CAPTION_GENERATED',
                'EMBEDDED',
                'FAILED'
            )
        )
);

-- ============================================================================
-- INDEXES
-- ============================================================================

CREATE INDEX IF NOT EXISTS idx_images_page
ON knowledge.images(page_id);

CREATE INDEX IF NOT EXISTS idx_images_page_image
ON knowledge.images(page_id, image_index);

CREATE INDEX IF NOT EXISTS idx_images_status
ON knowledge.images(image_status);

CREATE INDEX IF NOT EXISTS idx_images_vector_point
ON knowledge.images(vector_point_id);

CREATE INDEX IF NOT EXISTS idx_images_embedding_model
ON knowledge.images(embedding_model);

CREATE INDEX IF NOT EXISTS idx_images_checksum
ON knowledge.images(content_checksum);

CREATE INDEX IF NOT EXISTS idx_images_active
ON knowledge.images(is_active)
WHERE is_active = TRUE;

-- ============================================================================
-- COMMENTS
-- ============================================================================

COMMENT ON TABLE knowledge.images IS
'Stores metadata for images extracted from document pages.';

COMMENT ON COLUMN knowledge.images.image_id IS
'Primary key of the extracted image.';

COMMENT ON COLUMN knowledge.images.page_id IS
'Parent page identifier.';

COMMENT ON COLUMN knowledge.images.image_index IS
'Sequential position of the image within the page.';

COMMENT ON COLUMN knowledge.images.original_filename IS
'Original extracted image filename.';

COMMENT ON COLUMN knowledge.images.image_format IS
'Logical image format (PNG, JPEG, WEBP, etc.).';

COMMENT ON COLUMN knowledge.images.mime_type IS
'MIME type of the image.';

COMMENT ON COLUMN knowledge.images.file_size_bytes IS
'Image size in bytes.';

COMMENT ON COLUMN knowledge.images.bucket_name IS
'MinIO bucket storing the image.';

COMMENT ON COLUMN knowledge.images.object_path IS
'Object path inside the storage bucket.';

COMMENT ON COLUMN knowledge.images.width_px IS
'Image width in pixels.';

COMMENT ON COLUMN knowledge.images.height_px IS
'Image height in pixels.';

COMMENT ON COLUMN knowledge.images.bbox_x IS
'Bounding box X-coordinate within the page.';

COMMENT ON COLUMN knowledge.images.bbox_y IS
'Bounding box Y-coordinate within the page.';

COMMENT ON COLUMN knowledge.images.bbox_width IS
'Bounding box width within the page.';

COMMENT ON COLUMN knowledge.images.bbox_height IS
'Bounding box height within the page.';

COMMENT ON COLUMN knowledge.images.caption IS
'AI-generated description of the image.';

COMMENT ON COLUMN knowledge.images.alt_text IS
'Accessibility or manually curated alternative text.';

COMMENT ON COLUMN knowledge.images.ocr_text IS
'Text extracted from the image using OCR.';

COMMENT ON COLUMN knowledge.images.vector_point_id IS
'Identifier of the corresponding vector stored in the vector database.';

COMMENT ON COLUMN knowledge.images.embedding_model IS
'Embedding model used to generate the image embedding.';

COMMENT ON COLUMN knowledge.images.embedding_dimension IS
'Dimension of the generated embedding vector.';

COMMENT ON COLUMN knowledge.images.embedding_generated_at IS
'Timestamp when the embedding was generated.';

COMMENT ON COLUMN knowledge.images.content_checksum IS
'SHA-256 checksum of the extracted image.';

COMMENT ON COLUMN knowledge.images.image_status IS
'Current processing state of the extracted image.';

COMMENT ON COLUMN knowledge.images.is_active IS
'Indicates whether the image is active.';

COMMENT ON COLUMN knowledge.images.created_at IS
'Timestamp when the image metadata was created.';

COMMENT ON COLUMN knowledge.images.updated_at IS
'Timestamp of the most recent modification.';

-- ============================================================================
-- TRIGGER
-- ============================================================================

DROP TRIGGER IF EXISTS trg_images_bu_set_updated_at ON knowledge.images;

CREATE TRIGGER trg_images_bu_set_updated_at
BEFORE UPDATE
ON knowledge.images
FOR EACH ROW
EXECUTE FUNCTION common.set_updated_at();





-- ============================================================================
-- TABLE: knowledge.tables
-- DESCRIPTION:
--     Stores metadata for structured tables extracted from document pages.
--
-- NOTES:
--     - Actual table data (CSV/JSON/Parquet) is stored in MinIO.
--     - Table embeddings are stored in Qdrant.
--     - PostgreSQL stores metadata only.
-- ============================================================================

CREATE TABLE IF NOT EXISTS knowledge.tables (

    ---------------------------------------------------------------------------
    -- Primary Key
    ---------------------------------------------------------------------------

    table_id UUID
        PRIMARY KEY
        DEFAULT gen_random_uuid(),

    ---------------------------------------------------------------------------
    -- Parent Page
    ---------------------------------------------------------------------------

    page_id UUID
        NOT NULL,

    ---------------------------------------------------------------------------
    -- Ordering
    ---------------------------------------------------------------------------

    table_index INTEGER
        NOT NULL,

    ---------------------------------------------------------------------------
    -- Table Metadata
    ---------------------------------------------------------------------------

    table_title VARCHAR(255),

    table_type VARCHAR(30)
        NOT NULL
        DEFAULT 'DATA_TABLE',

    has_header BOOLEAN
        NOT NULL
        DEFAULT TRUE,

    ---------------------------------------------------------------------------
    -- Storage
    ---------------------------------------------------------------------------

    bucket_name VARCHAR(100)
        NOT NULL,

    object_path TEXT
        NOT NULL,

    storage_format VARCHAR(225)
        NOT NULL,

    ---------------------------------------------------------------------------
    -- Table Statistics
    ---------------------------------------------------------------------------

    row_count INTEGER
        NOT NULL,

    column_count INTEGER
        NOT NULL,

    column_headers JSONB,

    table_summary TEXT,

    ---------------------------------------------------------------------------
    -- Bounding Box
    ---------------------------------------------------------------------------

    bbox_x DOUBLE PRECISION
        NOT NULL,

    bbox_y DOUBLE PRECISION
        NOT NULL,

    bbox_width DOUBLE PRECISION
        NOT NULL,

    bbox_height DOUBLE PRECISION
        NOT NULL,

    ---------------------------------------------------------------------------
    -- Extraction Metadata
    ---------------------------------------------------------------------------

    extraction_engine VARCHAR(100),

    extraction_confidence NUMERIC(5,4),

    ---------------------------------------------------------------------------
    -- Vector Metadata
    ---------------------------------------------------------------------------

    vector_point_id UUID,

    embedding_model TEXT,

    embedding_dimension INTEGER,

    embedding_generated_at TIMESTAMPTZ,

    ---------------------------------------------------------------------------
    -- Integrity
    ---------------------------------------------------------------------------

    content_checksum CHAR(64)
        NOT NULL,

    ---------------------------------------------------------------------------
    -- Processing
    ---------------------------------------------------------------------------

    table_status VARCHAR(30)
        NOT NULL
        DEFAULT 'EXTRACTED',

    ---------------------------------------------------------------------------
    -- Lifecycle
    ---------------------------------------------------------------------------

    is_active BOOLEAN
        NOT NULL
        DEFAULT TRUE,

    created_at TIMESTAMPTZ
        NOT NULL
        DEFAULT CURRENT_TIMESTAMP,

    updated_at TIMESTAMPTZ
        NOT NULL
        DEFAULT CURRENT_TIMESTAMP,

    ---------------------------------------------------------------------------
    -- Foreign Key
    ---------------------------------------------------------------------------

    CONSTRAINT fk_tables_page
        FOREIGN KEY (page_id)
        REFERENCES knowledge.pages(page_id)
        ON DELETE CASCADE
        ON UPDATE CASCADE,

    ---------------------------------------------------------------------------
    -- Unique Constraints
    ---------------------------------------------------------------------------

    CONSTRAINT uq_tables_page_index
        UNIQUE (page_id, table_index),

    CONSTRAINT uq_tables_storage
        UNIQUE (bucket_name, object_path),

    CONSTRAINT uq_tables_checksum
        UNIQUE (content_checksum),

    ---------------------------------------------------------------------------
    -- Validation
    ---------------------------------------------------------------------------

    CONSTRAINT chk_tables_bucket_not_blank
        CHECK (length(trim(bucket_name)) > 0),

    CONSTRAINT chk_tables_object_path_not_blank
        CHECK (length(trim(object_path)) > 0),

    CONSTRAINT chk_tables_index
        CHECK (table_index >= 1),

    CONSTRAINT chk_tables_rows
        CHECK (row_count >= 0),

    CONSTRAINT chk_tables_columns
        CHECK (column_count >= 0),

    CONSTRAINT chk_tables_bbox_x
        CHECK (bbox_x >= 0),

    CONSTRAINT chk_tables_bbox_y
        CHECK (bbox_y >= 0),

    CONSTRAINT chk_tables_bbox_width
        CHECK (bbox_width > 0),

    CONSTRAINT chk_tables_bbox_height
        CHECK (bbox_height > 0),

    CONSTRAINT chk_tables_embedding_dimension
        CHECK (
            embedding_dimension IS NULL
            OR embedding_dimension > 0
        ),

    CONSTRAINT chk_tables_extraction_confidence
        CHECK (
            extraction_confidence IS NULL
            OR (
                extraction_confidence >= 0
                AND extraction_confidence <= 1
            )
        ),

    CONSTRAINT chk_tables_checksum
        CHECK (
            content_checksum ~ '^[A-Fa-f0-9]{64}$'
        ),

    CONSTRAINT chk_tables_storage_format
        CHECK (
            storage_format IN (
                'CSV',
                'JSON',
                'PARQUET'
            )
        ),

    CONSTRAINT chk_tables_type
        CHECK (
            table_type IN (
                'DATA_TABLE',
                'KEY_VALUE',
                'MATRIX',
                'FINANCIAL',
                'UNKNOWN'
            )
        ),

    CONSTRAINT chk_tables_status
        CHECK (
            table_status IN (
                'EXTRACTED',
                'SUMMARIZED',
                'EMBEDDED',
                'FAILED'
            )
        )
);

-- ============================================================================
-- INDEXES
-- ============================================================================

CREATE INDEX IF NOT EXISTS idx_tables_page
ON knowledge.tables(page_id);

CREATE INDEX IF NOT EXISTS idx_tables_page_table
ON knowledge.tables(page_id, table_index);

CREATE INDEX IF NOT EXISTS idx_tables_status
ON knowledge.tables(table_status);

CREATE INDEX IF NOT EXISTS idx_tables_storage_format
ON knowledge.tables(storage_format);

CREATE INDEX IF NOT EXISTS idx_tables_vector_point
ON knowledge.tables(vector_point_id);

CREATE INDEX IF NOT EXISTS idx_tables_embedding_model
ON knowledge.tables(embedding_model);

CREATE INDEX IF NOT EXISTS idx_tables_checksum
ON knowledge.tables(content_checksum);

CREATE INDEX IF NOT EXISTS idx_tables_active
ON knowledge.tables(is_active)
WHERE is_active = TRUE;

CREATE INDEX IF NOT EXISTS idx_tables_column_headers
ON knowledge.tables
USING GIN(column_headers);

-- ============================================================================
-- COMMENTS
-- ============================================================================

COMMENT ON TABLE knowledge.tables IS
'Stores metadata for structured tables extracted from document pages.';

COMMENT ON COLUMN knowledge.tables.table_id IS
'Primary key of the extracted table.';

COMMENT ON COLUMN knowledge.tables.page_id IS
'Parent page identifier.';

COMMENT ON COLUMN knowledge.tables.table_index IS
'Sequential position of the table within the page.';

COMMENT ON COLUMN knowledge.tables.table_title IS
'Title or caption associated with the extracted table.';

COMMENT ON COLUMN knowledge.tables.table_type IS
'Logical classification of the extracted table.';

COMMENT ON COLUMN knowledge.tables.has_header IS
'Indicates whether the extracted table contains a header row.';

COMMENT ON COLUMN knowledge.tables.bucket_name IS
'MinIO bucket storing the extracted table data.';

COMMENT ON COLUMN knowledge.tables.object_path IS
'Object path of the extracted table inside MinIO.';

COMMENT ON COLUMN knowledge.tables.storage_format IS
'Serialization format of the stored table data.';

COMMENT ON COLUMN knowledge.tables.row_count IS
'Number of extracted rows.';

COMMENT ON COLUMN knowledge.tables.column_count IS
'Number of extracted columns.';

COMMENT ON COLUMN knowledge.tables.column_headers IS
'JSON array containing extracted column names.';

COMMENT ON COLUMN knowledge.tables.table_summary IS
'AI-generated summary of the extracted table.';

COMMENT ON COLUMN knowledge.tables.bbox_x IS
'Bounding box X coordinate on the original page.';

COMMENT ON COLUMN knowledge.tables.bbox_y IS
'Bounding box Y coordinate on the original page.';

COMMENT ON COLUMN knowledge.tables.bbox_width IS
'Bounding box width on the original page.';

COMMENT ON COLUMN knowledge.tables.bbox_height IS
'Bounding box height on the original page.';

COMMENT ON COLUMN knowledge.tables.extraction_engine IS
'Tool or model used to extract the table.';

COMMENT ON COLUMN knowledge.tables.extraction_confidence IS
'Confidence score produced by the extraction engine.';

COMMENT ON COLUMN knowledge.tables.vector_point_id IS
'Identifier of the corresponding vector stored in the vector database.';

COMMENT ON COLUMN knowledge.tables.embedding_model IS
'Embedding model used for semantic indexing.';

COMMENT ON COLUMN knowledge.tables.embedding_dimension IS
'Dimension of the generated embedding vector.';

COMMENT ON COLUMN knowledge.tables.embedding_generated_at IS
'Timestamp when the embedding was generated.';

COMMENT ON COLUMN knowledge.tables.content_checksum IS
'SHA-256 checksum of the extracted table content.';

COMMENT ON COLUMN knowledge.tables.table_status IS
'Current processing state of the extracted table.';

COMMENT ON COLUMN knowledge.tables.is_active IS
'Indicates whether the table is active.';

COMMENT ON COLUMN knowledge.tables.created_at IS
'Timestamp when the table metadata was created.';

COMMENT ON COLUMN knowledge.tables.updated_at IS
'Timestamp of the most recent modification.';

-- ============================================================================
-- TRIGGER
-- ============================================================================

DROP TRIGGER IF EXISTS trg_tables_bu_set_updated_at ON knowledge.tables;

CREATE TRIGGER trg_tables_bu_set_updated_at
BEFORE UPDATE
ON knowledge.tables
FOR EACH ROW
EXECUTE FUNCTION common.set_updated_at();





-- ============================================================================
-- TABLE: knowledge.tags
-- DESCRIPTION:
--     Master table storing reusable tags for document classification.
--
-- NOTES:
--     - Tags are shared across documents.
--     - Relationships are maintained via knowledge.document_tag_mapping.
-- ============================================================================

CREATE TABLE IF NOT EXISTS knowledge.tags (

    ---------------------------------------------------------------------------
    -- Primary Key
    ---------------------------------------------------------------------------

    tag_id UUID
        PRIMARY KEY
        DEFAULT gen_random_uuid(),

    ---------------------------------------------------------------------------
    -- Core Information
    ---------------------------------------------------------------------------

    tag_name CITEXT
        NOT NULL,

    slug VARCHAR(120)
        NOT NULL,

    description TEXT,

    usage_notes TEXT,

    ---------------------------------------------------------------------------
    -- Classification
    ---------------------------------------------------------------------------

    tag_type VARCHAR(30)
        NOT NULL
        DEFAULT 'CUSTOM',

    ---------------------------------------------------------------------------
    -- Presentation
    ---------------------------------------------------------------------------

    color_hex CHAR(7),

    display_order INTEGER
        NOT NULL
        DEFAULT 0,

    ---------------------------------------------------------------------------
    -- System Metadata
    ---------------------------------------------------------------------------

    is_system_tag BOOLEAN
        NOT NULL
        DEFAULT FALSE,

    ---------------------------------------------------------------------------
    -- Lifecycle
    ---------------------------------------------------------------------------

    is_active BOOLEAN
        NOT NULL
        DEFAULT TRUE,

    created_at TIMESTAMPTZ
        NOT NULL
        DEFAULT CURRENT_TIMESTAMP,

    updated_at TIMESTAMPTZ
        NOT NULL
        DEFAULT CURRENT_TIMESTAMP,

    ---------------------------------------------------------------------------
    -- Constraints
    ---------------------------------------------------------------------------

    CONSTRAINT uq_tags_tag_name
        UNIQUE (tag_name),

    CONSTRAINT chk_tags_name_not_blank
        CHECK (
            length(trim(tag_name::TEXT)) > 0
        ),

    CONSTRAINT chk_tags_slug_not_blank
        CHECK (
            length(trim(slug)) > 0
        ),

    CONSTRAINT chk_tags_slug_lowercase
        CHECK (
            slug = lower(slug)
        ),

    CONSTRAINT chk_tags_slug_format
        CHECK (
            slug ~ '^[a-z0-9]+(?:-[a-z0-9]+)*$'
        ),

    CONSTRAINT chk_tags_color
        CHECK (
            color_hex IS NULL
            OR color_hex ~ '^#[A-Fa-f0-9]{6}$'
        ),

    CONSTRAINT chk_tags_display_order
        CHECK (
            display_order >= 0
        ),

    CONSTRAINT chk_tags_type
        CHECK (
            tag_type IN (
                'DOMAIN',
                'TOPIC',
                'TECHNOLOGY',
                'DOCUMENT_TYPE',
                'LANGUAGE',
                'SECURITY',
                'CUSTOM'
            )
        )
);

-- ============================================================================
-- UNIQUE INDEXES
-- ============================================================================

CREATE UNIQUE INDEX IF NOT EXISTS uq_tags_slug_ci
ON knowledge.tags (LOWER(slug));

-- ============================================================================
-- INDEXES
-- ============================================================================

CREATE INDEX IF NOT EXISTS idx_tags_type
ON knowledge.tags(tag_type);

CREATE INDEX IF NOT EXISTS idx_tags_display_order
ON knowledge.tags(display_order);

CREATE INDEX IF NOT EXISTS idx_tags_system
ON knowledge.tags(is_system_tag);

CREATE INDEX IF NOT EXISTS idx_tags_active
ON knowledge.tags(is_active)
WHERE is_active = TRUE;

-- ============================================================================
-- COMMENTS
-- ============================================================================

COMMENT ON TABLE knowledge.tags IS
'Master table storing reusable tags used to classify and organize knowledge documents.';

COMMENT ON COLUMN knowledge.tags.tag_id IS
'Primary key of the tag.';

COMMENT ON COLUMN knowledge.tags.tag_name IS
'Human-readable tag name. Uses CITEXT for case-insensitive uniqueness.';

COMMENT ON COLUMN knowledge.tags.slug IS
'Lowercase URL-friendly unique identifier for the tag.';

COMMENT ON COLUMN knowledge.tags.description IS
'Detailed description of the tag.';

COMMENT ON COLUMN knowledge.tags.usage_notes IS
'Internal notes describing intended usage of the tag.';

COMMENT ON COLUMN knowledge.tags.tag_type IS
'Logical classification of the tag.';

COMMENT ON COLUMN knowledge.tags.color_hex IS
'Optional hexadecimal color used by the user interface.';

COMMENT ON COLUMN knowledge.tags.display_order IS
'Display ordering for UI components.';

COMMENT ON COLUMN knowledge.tags.is_system_tag IS
'Indicates whether this tag is managed internally by the system.';

COMMENT ON COLUMN knowledge.tags.is_active IS
'Indicates whether the tag is active.';

COMMENT ON COLUMN knowledge.tags.created_at IS
'Timestamp when the tag was created.';

COMMENT ON COLUMN knowledge.tags.updated_at IS
'Timestamp of the most recent modification.';

-- ============================================================================
-- TRIGGER
-- ============================================================================

DROP TRIGGER IF EXISTS trg_tags_bu_set_updated_at ON knowledge.tags;

CREATE TRIGGER trg_tags_bu_set_updated_at
BEFORE UPDATE
ON knowledge.tags
FOR EACH ROW
EXECUTE FUNCTION common.set_updated_at();





-- ============================================================================
-- TABLE: knowledge.document_tag_mapping
-- DESCRIPTION:
--     Junction table implementing the many-to-many relationship between
--     documents and tags.
--
-- NOTES:
--     - One document may have multiple tags.
--     - One tag may be assigned to multiple documents.
--     - Mapping rows are immutable.
--     - Delete and recreate mappings instead of updating them.
-- ============================================================================

CREATE TABLE IF NOT EXISTS knowledge.document_tag_mapping (

    ---------------------------------------------------------------------------
    -- Primary Key
    ---------------------------------------------------------------------------

    mapping_id UUID
        PRIMARY KEY
        DEFAULT gen_random_uuid(),

    ---------------------------------------------------------------------------
    -- Relationships
    ---------------------------------------------------------------------------

    document_id UUID
        NOT NULL,

    tag_id UUID
        NOT NULL,

    ---------------------------------------------------------------------------
    -- Assignment Metadata
    ---------------------------------------------------------------------------

    tag_source VARCHAR(20)
        NOT NULL
        DEFAULT 'MANUAL',

    confidence_score NUMERIC(5,4),

    is_primary BOOLEAN
        NOT NULL
        DEFAULT FALSE,

    ---------------------------------------------------------------------------
    -- Audit
    ---------------------------------------------------------------------------

    created_at TIMESTAMPTZ
        NOT NULL
        DEFAULT CURRENT_TIMESTAMP,

    ---------------------------------------------------------------------------
    -- Foreign Keys
    ---------------------------------------------------------------------------

    CONSTRAINT fk_document_tag_mapping_document
        FOREIGN KEY (document_id)
        REFERENCES knowledge.documents(document_id)
        ON DELETE CASCADE
        ON UPDATE CASCADE,

    CONSTRAINT fk_document_tag_mapping_tag
        FOREIGN KEY (tag_id)
        REFERENCES knowledge.tags(tag_id)
        ON DELETE RESTRICT
        ON UPDATE CASCADE,

    ---------------------------------------------------------------------------
    -- Uniqueness
    ---------------------------------------------------------------------------

    CONSTRAINT uq_document_tag_mapping_document_tag
        UNIQUE (
            document_id,
            tag_id
        ),

    ---------------------------------------------------------------------------
    -- Validation
    ---------------------------------------------------------------------------

    CONSTRAINT chk_document_tag_mapping_tag_source
        CHECK (
            tag_source IN (
                'MANUAL',
                'AUTO',
                'LLM',
                'IMPORT'
            )
        ),

    CONSTRAINT chk_document_tag_mapping_confidence
        CHECK (
            confidence_score IS NULL
            OR (
                confidence_score >= 0
                AND confidence_score <= 1
            )
        )
);

-- ============================================================================
-- INDEXES
-- ============================================================================

CREATE INDEX IF NOT EXISTS idx_document_tag_mapping_document
ON knowledge.document_tag_mapping(document_id);

CREATE INDEX IF NOT EXISTS idx_document_tag_mapping_tag
ON knowledge.document_tag_mapping(tag_id);

CREATE INDEX IF NOT EXISTS idx_document_tag_mapping_tag_source
ON knowledge.document_tag_mapping(tag_source);

CREATE INDEX IF NOT EXISTS idx_document_tag_mapping_created_at
ON knowledge.document_tag_mapping(created_at);

-- ============================================================================
-- BUSINESS RULE
-- Only one primary tag per document
-- ============================================================================

CREATE UNIQUE INDEX IF NOT EXISTS uq_document_primary_tag
ON knowledge.document_tag_mapping(document_id)
WHERE is_primary = TRUE;

-- ============================================================================
-- COMMENTS
-- ============================================================================

COMMENT ON TABLE knowledge.document_tag_mapping IS
'Associates documents with reusable tags using a normalized many-to-many relationship.';

COMMENT ON COLUMN knowledge.document_tag_mapping.mapping_id IS
'Primary key of the document-tag relationship.';

COMMENT ON COLUMN knowledge.document_tag_mapping.document_id IS
'Referenced document identifier.';

COMMENT ON COLUMN knowledge.document_tag_mapping.tag_id IS
'Referenced tag identifier.';

COMMENT ON COLUMN knowledge.document_tag_mapping.tag_source IS
'Origin of the tag assignment (MANUAL, AUTO, LLM, IMPORT).';

COMMENT ON COLUMN knowledge.document_tag_mapping.confidence_score IS
'Confidence score for automatically assigned tags. NULL for manual assignments.';

COMMENT ON COLUMN knowledge.document_tag_mapping.is_primary IS
'Indicates whether this is the primary tag assigned to the document.';

COMMENT ON COLUMN knowledge.document_tag_mapping.created_at IS
'Timestamp when the document-tag relationship was created.';