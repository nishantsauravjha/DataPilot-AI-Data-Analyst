/*
===============================================================================
 OmniBrain Database Project
 Module      : Query Engine
 File        : 05_context_items.sql
 Schema      : query_engine
 Author      : OmniBrain Database Team
 Description : Stores every evidence item returned during retrieval.
===============================================================================

DESCRIPTION
-----------
Each row represents ONE retrieved evidence item belonging to a retrieval
operation.

A context item may reference exactly ONE of:

• Text Chunk
• Image
• Table Entity
• Structured Data Source

The exclusive-arc constraint guarantees only one reference is populated.

DEPENDENCIES
------------
query_engine.retrieved_context
query_engine.context_item_types
knowledge.chunks
knowledge.images
knowledge.tables
structured.data_sources
public.update_updated_at_column()

===============================================================================
*/

SET search_path TO query_engine, public;

-- ============================================================================
-- TABLE
-- ============================================================================

CREATE TABLE IF NOT EXISTS query_engine.context_items
(

    ---------------------------------------------------------------------------
    -- Primary Key
    ---------------------------------------------------------------------------

    context_item_id UUID PRIMARY KEY
        DEFAULT uuid_generate_v4(),

    ---------------------------------------------------------------------------
    -- Relationships
    ---------------------------------------------------------------------------

    retrieval_id UUID NOT NULL,

    item_type_id SMALLINT NOT NULL,

    ---------------------------------------------------------------------------
    -- Evidence References
    ---------------------------------------------------------------------------

    chunk_id UUID,

    image_id UUID,

    table_entity_id UUID,

    datasource_id UUID,

    ---------------------------------------------------------------------------
    -- Retrieval Metadata
    ---------------------------------------------------------------------------

    retrieval_rank INTEGER NOT NULL,

    relevance_score NUMERIC(6,5) NOT NULL,

    page_number INTEGER,

    citation_label VARCHAR(100),

    highlight_json JSONB,

    metadata JSONB NOT NULL
        DEFAULT '{}'::jsonb,

    ---------------------------------------------------------------------------
    -- Audit
    ---------------------------------------------------------------------------

    created_at TIMESTAMPTZ NOT NULL
        DEFAULT CURRENT_TIMESTAMP,

    updated_at TIMESTAMPTZ NOT NULL
        DEFAULT CURRENT_TIMESTAMP,

    ---------------------------------------------------------------------------
    -- Constraints
    ---------------------------------------------------------------------------

    CONSTRAINT chk_retrieval_rank
        CHECK (retrieval_rank > 0),

    CONSTRAINT chk_relevance_score
        CHECK (
            relevance_score >= 0
            AND relevance_score <= 1
        ),

    CONSTRAINT chk_page_number
        CHECK (
            page_number IS NULL
            OR page_number > 0
        ),

CONSTRAINT uq_context_item_rank
UNIQUE
(
    retrieval_id,
    retrieval_rank
),

CONSTRAINT chk_citation_label
CHECK (
    citation_label IS NULL
    OR length(trim(citation_label)) > 0
),
    ---------------------------------------------------------------------------
    -- Exclusive Arc Constraint
    ---------------------------------------------------------------------------

    CONSTRAINT chk_context_item_reference
    CHECK
    (

        (
            (chunk_id IS NOT NULL)::integer
          + (image_id IS NOT NULL)::integer
          + (table_entity_id IS NOT NULL)::integer
          + (datasource_id IS NOT NULL)::integer

        ) = 1

    ),

    ---------------------------------------------------------------------------
    -- Foreign Keys
    ---------------------------------------------------------------------------

    CONSTRAINT fk_context_retrieval
        FOREIGN KEY (retrieval_id)
        REFERENCES query_engine.retrieved_context(retrieval_id)
        ON UPDATE CASCADE
        ON DELETE CASCADE,

    CONSTRAINT fk_context_item_type
        FOREIGN KEY (item_type_id)
        REFERENCES query_engine.context_item_types(item_type_id)
        ON UPDATE CASCADE
        ON DELETE RESTRICT,

    CONSTRAINT fk_context_chunk
        FOREIGN KEY (chunk_id)
        REFERENCES knowledge.chunks(chunk_id)
        ON UPDATE CASCADE
        ON DELETE CASCADE,

    CONSTRAINT fk_context_image
        FOREIGN KEY (image_id)
        REFERENCES knowledge.images(image_id)
        ON UPDATE CASCADE
        ON DELETE CASCADE,

    CONSTRAINT fk_context_table
        FOREIGN KEY (table_entity_id)
        REFERENCES knowledge.tables(table_id)
        ON UPDATE CASCADE
        ON DELETE CASCADE,

    CONSTRAINT fk_context_datasource
        FOREIGN KEY (datasource_id)
        REFERENCES structured.data_sources(source_id)
        ON UPDATE CASCADE
        ON DELETE CASCADE

)

WITH
(
    fillfactor = 90
);


-- ============================================================================
-- COMMENTS
-- ============================================================================

COMMENT ON TABLE query_engine.context_items IS
'Stores every individual evidence item retrieved for a query.';

COMMENT ON COLUMN query_engine.context_items.retrieval_id IS
'Retrieval operation that produced this evidence item.';

COMMENT ON COLUMN query_engine.context_items.item_type_id IS
'Type of evidence (chunk, image, table, structured data, etc.).';

COMMENT ON COLUMN query_engine.context_items.relevance_score IS
'Normalized relevance score assigned by the retrieval pipeline.';

COMMENT ON COLUMN query_engine.context_items.retrieval_rank IS
'Ranking position of the evidence item after reranking.';

COMMENT ON COLUMN query_engine.context_items.highlight_json IS
'Structured highlighting information such as OCR bounding boxes or text spans.';

COMMENT ON COLUMN query_engine.context_items.metadata IS
'Extensible JSON metadata for future retrieval features.';

-- ============================================================================
-- TRIGGER
-- ============================================================================

DROP TRIGGER IF EXISTS trg_context_items_updated_at ON query_engine.context_items;

CREATE TRIGGER trg_context_items_updated_at
BEFORE UPDATE
ON query_engine.context_items
FOR EACH ROW
EXECUTE FUNCTION public.update_updated_at_column();