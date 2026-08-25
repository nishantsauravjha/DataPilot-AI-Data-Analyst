/*
===============================================================================
 OmniBrain Database Project
 Module      : Query Engine
 File        : 04_retrieved_context.sql
 Schema      : query_engine
 Author      : OmniBrain Database Team
 Description : Stores retrieval execution metadata for each logical query.
===============================================================================

DESCRIPTION
-----------
A Retrieved Context represents ONE retrieval operation performed while
processing a logical query.

This table DOES NOT store retrieved chunks, images, tables, or structured
records directly.

Instead, it stores metadata describing the retrieval process.

Individual retrieved evidence is stored in:

    query_engine.context_items

Example
-------

User Query
      │
      ▼
Hybrid Retrieval
      │
      ▼
Retrieved Context
      │
      ├───────────────┐
      ▼               ▼
Context Item      Context Item
Chunk             Image
      ▼               ▼
Context Item      Context Item
Table             SQL Record

DEPENDENCIES
------------
query_engine.queries
public.update_updated_at_column()

REFERENCED BY
-------------
query_engine.context_items

===============================================================================
*/

SET search_path TO query_engine, public;

-- ============================================================================
-- TABLE : retrieved_context
-- ============================================================================

CREATE TABLE IF NOT EXISTS query_engine.retrieved_context
(

    ---------------------------------------------------------------------------
    -- Primary Key
    ---------------------------------------------------------------------------

    retrieval_id UUID PRIMARY KEY
        DEFAULT uuid_generate_v4(),

    ---------------------------------------------------------------------------
    -- Relationships
    ---------------------------------------------------------------------------

    query_id UUID NOT NULL,

    ---------------------------------------------------------------------------
    -- Retrieval Engine Information
    ---------------------------------------------------------------------------

    retriever_name TEXT NOT NULL,

    retriever_version VARCHAR(50),

    reranker_name TEXT,

    reranker_version VARCHAR(50),

    search_namespace VARCHAR(150) NOT NULL,

    ---------------------------------------------------------------------------
    -- Cache Information
    ---------------------------------------------------------------------------

    retrieval_hash VARCHAR(64),

    cache_key VARCHAR(255),

    cache_hit BOOLEAN NOT NULL
        DEFAULT FALSE,

    retrieval_source VARCHAR(20)
        NOT NULL
        DEFAULT 'LIVE',

    ---------------------------------------------------------------------------
    -- Retrieval Statistics
    ---------------------------------------------------------------------------

    candidate_count INTEGER NOT NULL
        DEFAULT 0,

    returned_count INTEGER NOT NULL
        DEFAULT 0,

    filtered_count INTEGER NOT NULL
        DEFAULT 0,

    retrieval_confidence NUMERIC(5,4),

    ---------------------------------------------------------------------------
    -- Flexible Metadata
    ---------------------------------------------------------------------------

    metadata JSONB NOT NULL
        DEFAULT '{}'::jsonb,

    ---------------------------------------------------------------------------
    -- Versioning
    ---------------------------------------------------------------------------

    version INTEGER NOT NULL
        DEFAULT 1,

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

    CONSTRAINT chk_candidate_count
        CHECK (candidate_count >= 0),

    CONSTRAINT chk_returned_count
        CHECK (returned_count >= 0),

    CONSTRAINT chk_filtered_count
        CHECK (filtered_count >= 0),

    CONSTRAINT chk_total_counts
        CHECK (
            candidate_count =
            returned_count + filtered_count
        ),

    CONSTRAINT chk_retrieval_confidence
        CHECK
        (
            retrieval_confidence IS NULL
            OR
            (
                retrieval_confidence >= 0
                AND retrieval_confidence <= 1
            )
        ),

    CONSTRAINT chk_search_namespace
        CHECK (
            length(trim(search_namespace)) > 0
        ),

    CONSTRAINT chk_retrieval_source
        CHECK
        (
            retrieval_source IN
            (
                'LIVE',
                'CACHE',
                'REPLAY'
            )
        ),

    CONSTRAINT chk_version
        CHECK (version > 0),

    ---------------------------------------------------------------------------
    -- Foreign Keys
    ---------------------------------------------------------------------------

    CONSTRAINT fk_retrieval_query
        FOREIGN KEY (query_id)
        REFERENCES query_engine.queries(query_id)
        ON UPDATE CASCADE
        ON DELETE CASCADE

)

WITH
(
    fillfactor = 90
);



-- ============================================================================
-- TABLE COMMENT
-- ============================================================================

COMMENT ON TABLE query_engine.retrieved_context IS
'Stores metadata describing a retrieval operation executed for a logical query. Individual retrieved evidence is stored in query_engine.context_items.';

-- ============================================================================
-- COLUMN COMMENTS
-- ============================================================================

COMMENT ON COLUMN query_engine.retrieved_context.retrieval_id IS
'Unique identifier of the retrieval operation.';

COMMENT ON COLUMN query_engine.retrieved_context.query_id IS
'Logical query that initiated this retrieval operation.';

COMMENT ON COLUMN query_engine.retrieved_context.retriever_name IS
'Retriever implementation used during retrieval (e.g. HybridRetriever, VectorRetriever, SQLRetriever).';

COMMENT ON COLUMN query_engine.retrieved_context.retriever_version IS
'Version of the retriever implementation.';

COMMENT ON COLUMN query_engine.retrieved_context.reranker_name IS
'Reranker model used after retrieval.';

COMMENT ON COLUMN query_engine.retrieved_context.reranker_version IS
'Version of the reranker model.';

COMMENT ON COLUMN query_engine.retrieved_context.search_namespace IS
'Logical namespace, collection, or domain searched during retrieval.';

COMMENT ON COLUMN query_engine.retrieved_context.retrieval_hash IS
'Deterministic hash representing this retrieval configuration for cache validation and duplicate detection.';

COMMENT ON COLUMN query_engine.retrieved_context.cache_key IS
'Cache key used when retrieval results are stored or fetched from cache.';

COMMENT ON COLUMN query_engine.retrieved_context.cache_hit IS
'Indicates whether retrieval results were served from cache instead of executing a new retrieval.';

COMMENT ON COLUMN query_engine.retrieved_context.retrieval_source IS
'Origin of retrieval results (LIVE, CACHE, or REPLAY).';

COMMENT ON COLUMN query_engine.retrieved_context.candidate_count IS
'Total number of candidate records initially retrieved before filtering and reranking.';

COMMENT ON COLUMN query_engine.retrieved_context.returned_count IS
'Final number of context items returned after filtering and reranking.';

COMMENT ON COLUMN query_engine.retrieved_context.filtered_count IS
'Number of candidate items discarded during filtering or reranking.';

COMMENT ON COLUMN query_engine.retrieved_context.retrieval_confidence IS
'Overall confidence score of the retrieval process.';

COMMENT ON COLUMN query_engine.retrieved_context.metadata IS
'Flexible JSON metadata containing retrieval configuration, filters, namespaces, search parameters, and future extensions.';

COMMENT ON COLUMN query_engine.retrieved_context.version IS
'Schema version of the retrieval record for future compatibility.';

COMMENT ON COLUMN query_engine.retrieved_context.created_at IS
'Timestamp when the retrieval record was created.';

COMMENT ON COLUMN query_engine.retrieved_context.updated_at IS
'Timestamp automatically updated whenever the record changes.';

-- ============================================================================
-- UPDATED_AT TRIGGER
-- ============================================================================

DROP TRIGGER IF EXISTS trg_retrieved_context_updated_at ON query_engine.retrieved_context;

CREATE TRIGGER trg_retrieved_context_updated_at
BEFORE UPDATE
ON query_engine.retrieved_context
FOR EACH ROW
EXECUTE FUNCTION public.update_updated_at_column();


