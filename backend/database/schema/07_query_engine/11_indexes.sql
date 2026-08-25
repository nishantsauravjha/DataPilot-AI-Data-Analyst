/*
===============================================================================
 OmniBrain Database Project
 Module      : Query Engine
 File        : 11_indexes.sql
 Schema      : query_engine
 Author      : OmniBrain Database Team
 Description : Performance, business-rule, and operational indexes for the
               Query Engine.
===============================================================================

DESCRIPTION
-----------
This file contains manually designed indexes based on expected query
patterns rather than automatically indexing every foreign key.

Primary Keys and UNIQUE constraints already create indexes automatically
and are intentionally excluded here.

OBJECTIVES
----------
• Optimize chat history loading
• Optimize retrieval pipeline
• Optimize response generation
• Optimize analytics
• Minimize redundant indexes
• Reduce write amplification

===============================================================================
*/

SET search_path TO query_engine, public;

-- ============================================================================
-- PERFORMANCE INDEXES
-- ============================================================================

------------------------------------------------------------------------------
-- Chat History
------------------------------------------------------------------------------

CREATE INDEX IF NOT EXISTS idx_conversation_turns_session_created
ON query_engine.conversation_turns
(
    session_id,
    created_at DESC
);

------------------------------------------------------------------------------
-- Query Lookup
------------------------------------------------------------------------------

CREATE INDEX IF NOT EXISTS idx_queries_turn
ON query_engine.queries
(
    turn_id
);

------------------------------------------------------------------------------
-- Retrieval Pipeline
------------------------------------------------------------------------------

CREATE INDEX IF NOT EXISTS idx_retrieved_context_query
ON query_engine.retrieved_context
(
    query_id
);

------------------------------------------------------------------------------
-- Context Retrieval Ordering
------------------------------------------------------------------------------

CREATE INDEX IF NOT EXISTS idx_context_items_retrieval_rank
ON query_engine.context_items
(
    retrieval_id,
    retrieval_rank
);

------------------------------------------------------------------------------
-- Response Lookup
------------------------------------------------------------------------------

CREATE INDEX IF NOT EXISTS idx_responses_query_created
ON query_engine.responses
(
    query_id,
    created_at DESC
);

------------------------------------------------------------------------------
-- Feedback Lookup
------------------------------------------------------------------------------

CREATE INDEX IF NOT EXISTS idx_feedback_response_type
ON query_engine.feedback
(
    response_id,
    feedback_type
);

------------------------------------------------------------------------------
-- Metrics Timeline
------------------------------------------------------------------------------

CREATE INDEX IF NOT EXISTS idx_metrics_scope_created
ON query_engine.metrics
(
    metric_scope,
    created_at DESC
);

-- ============================================================================
-- PARTIAL UNIQUE INDEXES
-- ============================================================================

------------------------------------------------------------------------------
-- One Final Response Per Query
------------------------------------------------------------------------------
-- Ensures only one response is marked as the final response for a query.
------------------------------------------------------------------------------

CREATE UNIQUE INDEX IF NOT EXISTS uq_final_response
ON query_engine.responses
(
    query_id
)
WHERE is_final = TRUE;

------------------------------------------------------------------------------
-- One Primary Citation Per Response
------------------------------------------------------------------------------
-- Ensures only one citation is designated as the primary citation.
------------------------------------------------------------------------------

CREATE UNIQUE INDEX IF NOT EXISTS uq_primary_citation
ON query_engine.citations
(
    response_id
)
WHERE is_primary = TRUE;

------------------------------------------------------------------------------
-- Unique Chunk Reference Per Retrieval
------------------------------------------------------------------------------

CREATE UNIQUE INDEX IF NOT EXISTS uq_context_chunk
ON query_engine.context_items
(
    retrieval_id,
    chunk_id
)
WHERE chunk_id IS NOT NULL;

------------------------------------------------------------------------------
-- Unique Image Reference Per Retrieval
------------------------------------------------------------------------------

CREATE UNIQUE INDEX IF NOT EXISTS uq_context_image
ON query_engine.context_items
(
    retrieval_id,
    image_id
)
WHERE image_id IS NOT NULL;

------------------------------------------------------------------------------
-- Unique Table Reference Per Retrieval
------------------------------------------------------------------------------

CREATE UNIQUE INDEX IF NOT EXISTS uq_context_table
ON query_engine.context_items
(
    retrieval_id,
    table_entity_id
)
WHERE table_entity_id IS NOT NULL;

------------------------------------------------------------------------------
-- Unique Structured Data Reference Per Retrieval
------------------------------------------------------------------------------

CREATE UNIQUE INDEX IF NOT EXISTS uq_context_datasource
ON query_engine.context_items
(
    retrieval_id,
    datasource_id
)
WHERE datasource_id IS NOT NULL;

------------------------------------------------------------------------------
-- Unique Tool Call Per Query
------------------------------------------------------------------------------
-- Prevents duplicate logging of the same tool invocation while allowing
-- NULL tool_call_id values.
------------------------------------------------------------------------------

CREATE UNIQUE INDEX IF NOT EXISTS uq_agent_tool_call
ON query_engine.agent_executions
(
    query_id,
    tool_call_id
)
WHERE tool_call_id IS NOT NULL;



-- ============================================================================
-- OPERATIONAL & ANALYTICS INDEXES
-- ============================================================================

------------------------------------------------------------------------------
-- Query Timeline
------------------------------------------------------------------------------

CREATE INDEX IF NOT EXISTS idx_queries_turn_created
ON query_engine.queries
(
    turn_id,
    created_at DESC
);

------------------------------------------------------------------------------
-- Reverse Citation Lookup
------------------------------------------------------------------------------

CREATE INDEX IF NOT EXISTS idx_citations_context_item
ON query_engine.citations
(
    context_item_id
);

------------------------------------------------------------------------------
-- Feedback By User
------------------------------------------------------------------------------

CREATE INDEX IF NOT EXISTS idx_feedback_user
ON query_engine.feedback
(
    user_id
)
WHERE user_id IS NOT NULL;

------------------------------------------------------------------------------
-- Feedback Analytics
------------------------------------------------------------------------------

CREATE INDEX IF NOT EXISTS idx_feedback_type_rating
ON query_engine.feedback
(
    feedback_type,
    rating
)
WHERE rating IS NOT NULL;

------------------------------------------------------------------------------
-- Metrics By Agent Execution
------------------------------------------------------------------------------

CREATE INDEX IF NOT EXISTS idx_metrics_agent_execution
ON query_engine.metrics
(
    agent_execution_id
)
WHERE agent_execution_id IS NOT NULL;

------------------------------------------------------------------------------
-- Metrics By Response
------------------------------------------------------------------------------

CREATE INDEX IF NOT EXISTS idx_metrics_response
ON query_engine.metrics
(
    response_id
)
WHERE response_id IS NOT NULL;

------------------------------------------------------------------------------
-- Provider / Model Analytics
------------------------------------------------------------------------------

CREATE INDEX IF NOT EXISTS idx_metrics_provider_model
ON query_engine.metrics
(
    provider_name,
    model_name
)
WHERE
provider_name IS NOT NULL
AND
model_name IS NOT NULL;

------------------------------------------------------------------------------
-- Cost Reporting
------------------------------------------------------------------------------

CREATE INDEX IF NOT EXISTS idx_metrics_cost
ON query_engine.metrics
(
    cost_usd
)
WHERE cost_usd IS NOT NULL;

------------------------------------------------------------------------------
-- Time-Series Analytics
------------------------------------------------------------------------------

CREATE INDEX IF NOT EXISTS idx_metrics_created_at
ON query_engine.metrics
(
    created_at DESC
);

------------------------------------------------------------------------------
-- Response Hash Lookup
------------------------------------------------------------------------------

CREATE INDEX IF NOT EXISTS idx_response_hash
ON query_engine.responses
(
    response_hash
)
WHERE response_hash IS NOT NULL;