/*
===============================================================================
 OmniBrain Database Project
 Module      : Query Engine
 File        : 10_metrics.sql
 Schema      : query_engine
 Author      : OmniBrain Database Team
 Description : Stores immutable execution telemetry and operational metrics.
===============================================================================

DESCRIPTION
-----------
Each row represents ONE immutable telemetry record generated during
query processing.

Metrics are append-only records and must never be updated.

Metrics may represent telemetry for:

• Entire Query
• Retrieval
• Agent Execution
• LLM Generation
• Response

Business data is stored elsewhere.

This table stores only operational measurements.

DEPENDENCIES
------------
query_engine.queries
query_engine.agent_executions
query_engine.responses

===============================================================================
*/

SET search_path TO query_engine, public;

-- ============================================================================
-- TABLE : metrics
-- ============================================================================

CREATE TABLE IF NOT EXISTS query_engine.metrics
(

    ---------------------------------------------------------------------------
    -- Primary Key
    ---------------------------------------------------------------------------

    metric_id UUID PRIMARY KEY
        DEFAULT uuid_generate_v4(),

    ---------------------------------------------------------------------------
    -- Relationships
    ---------------------------------------------------------------------------

    query_id UUID NOT NULL,

    agent_execution_id UUID,

    response_id UUID,

    ---------------------------------------------------------------------------
    -- Metric Scope
    ---------------------------------------------------------------------------

    metric_scope VARCHAR(20)
        NOT NULL,

    ---------------------------------------------------------------------------
    -- Model Information
    ---------------------------------------------------------------------------

    provider_name TEXT,

    model_name TEXT,

    ---------------------------------------------------------------------------
    -- Timing
    ---------------------------------------------------------------------------

    execution_duration_ms BIGINT
        NOT NULL,

    ---------------------------------------------------------------------------
    -- Token Usage
    ---------------------------------------------------------------------------

    input_tokens INTEGER,

    output_tokens INTEGER,

    ---------------------------------------------------------------------------
    -- Cost
    ---------------------------------------------------------------------------

    cost_usd NUMERIC(18,8),

    ---------------------------------------------------------------------------
    -- Cache
    ---------------------------------------------------------------------------

    cache_hit BOOLEAN,

    cache_lookup_ms BIGINT,

    ---------------------------------------------------------------------------
    -- Retrieval Metrics
    ---------------------------------------------------------------------------

    retrieved_documents INTEGER,

    reranked_documents INTEGER,

    ---------------------------------------------------------------------------
    -- Flexible Metadata
    ---------------------------------------------------------------------------

    metadata JSONB
        NOT NULL
        DEFAULT '{}'::jsonb,

    ---------------------------------------------------------------------------
    -- Audit
    ---------------------------------------------------------------------------

    created_at TIMESTAMPTZ
        NOT NULL
        DEFAULT CURRENT_TIMESTAMP,

    ---------------------------------------------------------------------------
    -- Constraints
    ---------------------------------------------------------------------------

    CONSTRAINT chk_metric_scope
        CHECK
        (
            metric_scope IN
            (
                'QUERY',
                'RETRIEVAL',
                'AGENT',
                'LLM',
                'RESPONSE'
            )
        ),

    CONSTRAINT chk_execution_duration
        CHECK
        (
            execution_duration_ms >= 0
        ),

    CONSTRAINT chk_input_tokens
        CHECK
        (
            input_tokens IS NULL
            OR input_tokens >= 0
        ),

    CONSTRAINT chk_output_tokens
        CHECK
        (
            output_tokens IS NULL
            OR output_tokens >= 0
        ),

    CONSTRAINT chk_cost
        CHECK
        (
            cost_usd IS NULL
            OR cost_usd >= 0
        ),

    CONSTRAINT chk_cache_lookup
        CHECK
        (
            cache_lookup_ms IS NULL
            OR cache_lookup_ms >= 0
        ),

    CONSTRAINT chk_retrieved_documents
        CHECK
        (
            retrieved_documents IS NULL
            OR retrieved_documents >= 0
        ),

    CONSTRAINT chk_reranked_documents
        CHECK
        (
            reranked_documents IS NULL
            OR reranked_documents >= 0
        ),

    ---------------------------------------------------------------------------
    -- Foreign Keys
    ---------------------------------------------------------------------------

    CONSTRAINT fk_metrics_query
        FOREIGN KEY (query_id)
        REFERENCES query_engine.queries(query_id)
        ON UPDATE CASCADE
        ON DELETE CASCADE,

    CONSTRAINT fk_metrics_agent_execution
        FOREIGN KEY (agent_execution_id)
        REFERENCES query_engine.agent_executions(agent_execution_id)
        ON UPDATE CASCADE
        ON DELETE SET NULL,

    CONSTRAINT fk_metrics_response
        FOREIGN KEY (response_id)
        REFERENCES query_engine.responses(response_id)
        ON UPDATE CASCADE
        ON DELETE SET NULL

)

WITH
(
    fillfactor = 100
);


-- ============================================================================
-- TABLE COMMENT
-- ============================================================================

COMMENT ON TABLE query_engine.metrics IS
'Stores immutable telemetry and operational metrics generated during query processing. Metrics are append-only records used for monitoring, analytics, performance tuning, and cost analysis.';

-- ============================================================================
-- COLUMN COMMENTS
-- ============================================================================

COMMENT ON COLUMN query_engine.metrics.metric_id IS
'Unique identifier of the telemetry record.';

COMMENT ON COLUMN query_engine.metrics.query_id IS
'Logical query associated with these metrics.';

COMMENT ON COLUMN query_engine.metrics.agent_execution_id IS
'Optional agent execution associated with these metrics.';

COMMENT ON COLUMN query_engine.metrics.response_id IS
'Optional generated response associated with these metrics.';

COMMENT ON COLUMN query_engine.metrics.metric_scope IS
'Pipeline stage represented by this telemetry record.';

COMMENT ON COLUMN query_engine.metrics.provider_name IS
'AI provider, retrieval provider, or execution provider responsible for generating the metric.';

COMMENT ON COLUMN query_engine.metrics.model_name IS
'Model or engine used during execution (LLM, embedding model, reranker, etc.).';

COMMENT ON COLUMN query_engine.metrics.execution_duration_ms IS
'Execution duration measured in milliseconds.';

COMMENT ON COLUMN query_engine.metrics.input_tokens IS
'Number of input tokens processed.';

COMMENT ON COLUMN query_engine.metrics.output_tokens IS
'Number of output tokens generated.';

COMMENT ON COLUMN query_engine.metrics.cost_usd IS
'Estimated execution cost in United States Dollars.';

COMMENT ON COLUMN query_engine.metrics.cache_hit IS
'Indicates whether execution results were served from cache.';

COMMENT ON COLUMN query_engine.metrics.cache_lookup_ms IS
'Time spent checking the cache in milliseconds.';

COMMENT ON COLUMN query_engine.metrics.retrieved_documents IS
'Number of documents initially retrieved before reranking or filtering.';

COMMENT ON COLUMN query_engine.metrics.reranked_documents IS
'Number of documents remaining after reranking.';

COMMENT ON COLUMN query_engine.metrics.metadata IS
'Flexible JSON metadata storing provider-specific telemetry, execution statistics, tracing identifiers, and future observability extensions.';

COMMENT ON COLUMN query_engine.metrics.created_at IS
'Timestamp when the telemetry record was created.';