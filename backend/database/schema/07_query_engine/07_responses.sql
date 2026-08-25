/*
===============================================================================
 OmniBrain Database Project
 Module      : Query Engine
 File        : 07_responses.sql
 Schema      : query_engine
 Author      : OmniBrain Database Team
 Description : Stores every response generated while processing a query.
===============================================================================

DESCRIPTION
-----------
Each row represents ONE response generated during the lifecycle of a query.

A query may have multiple responses, for example:

• Initial draft
• Critic revision
• Regenerated answer
• Final response

Only one response is typically marked as the final response.

This table intentionally does NOT store

• Citations
• Token usage
• Costs
• Latency
• Feedback

Those belong to their respective modules.

DEPENDENCIES
------------
query_engine.queries
query_engine.agent_executions
public.update_updated_at_column()

REFERENCED BY
-------------
query_engine.citations
query_engine.feedback
query_engine.metrics

===============================================================================
*/

SET search_path TO query_engine, public;

-- ============================================================================
-- TABLE : responses
-- ============================================================================

CREATE TABLE IF NOT EXISTS query_engine.responses
(

    ---------------------------------------------------------------------------
    -- Primary Key
    ---------------------------------------------------------------------------

    response_id UUID PRIMARY KEY
        DEFAULT uuid_generate_v4(),

    ---------------------------------------------------------------------------
    -- Relationships
    ---------------------------------------------------------------------------

    query_id UUID NOT NULL,

    agent_execution_id UUID,

    ---------------------------------------------------------------------------
    -- Response Content
    ---------------------------------------------------------------------------

    response_text TEXT NOT NULL,

    response_format VARCHAR(20)
        NOT NULL
        DEFAULT 'MARKDOWN',

    finish_reason VARCHAR(30)
        NOT NULL
        DEFAULT 'STOP',

    ---------------------------------------------------------------------------
    -- Streaming
    ---------------------------------------------------------------------------

    is_streamed BOOLEAN
        NOT NULL
        DEFAULT FALSE,

    stream_completed BOOLEAN
        NOT NULL
        DEFAULT TRUE,

    ---------------------------------------------------------------------------
    -- Response State
    ---------------------------------------------------------------------------

    is_final BOOLEAN
        NOT NULL
        DEFAULT TRUE,

    response_language CHAR(2)
        NOT NULL
        DEFAULT 'en',

    response_hash CHAR(64),

    ---------------------------------------------------------------------------
    -- Flexible Metadata
    ---------------------------------------------------------------------------

    metadata JSONB
        NOT NULL
        DEFAULT '{}'::jsonb,

    ---------------------------------------------------------------------------
    -- Versioning
    ---------------------------------------------------------------------------

    version INTEGER
        NOT NULL
        DEFAULT 1,

    ---------------------------------------------------------------------------
    -- Audit
    ---------------------------------------------------------------------------

    created_at TIMESTAMPTZ
        NOT NULL
        DEFAULT CURRENT_TIMESTAMP,

    updated_at TIMESTAMPTZ
        NOT NULL
        DEFAULT CURRENT_TIMESTAMP,

    ---------------------------------------------------------------------------
    -- Constraints
    ---------------------------------------------------------------------------

    CONSTRAINT chk_response_format
        CHECK
        (
            response_format IN
            (
                'TEXT',
                'MARKDOWN',
                'HTML',
                'JSON',
                'CODE'
            )
        ),

    CONSTRAINT chk_finish_reason
        CHECK
        (
            finish_reason IN
            (
                'STOP',
                'LENGTH',
                'TOOL_CALL',
                'CONTENT_FILTER',
                'ERROR'
            )
        ),

    CONSTRAINT chk_response_language
        CHECK
        (
            response_language ~ '^[a-z]{2}$'
        ),

    CONSTRAINT chk_version
        CHECK (version > 0),

    CONSTRAINT chk_stream_state
        CHECK
        (
            NOT stream_completed
            OR is_streamed
        ),

    ---------------------------------------------------------------------------
    -- Foreign Keys
    ---------------------------------------------------------------------------

    CONSTRAINT fk_response_query
        FOREIGN KEY (query_id)
        REFERENCES query_engine.queries(query_id)
        ON UPDATE CASCADE
        ON DELETE CASCADE,

    CONSTRAINT fk_response_execution
        FOREIGN KEY (agent_execution_id)
        REFERENCES query_engine.agent_executions(agent_execution_id)
        ON UPDATE CASCADE
        ON DELETE SET NULL

)

WITH
(
    fillfactor = 90
);

-- ============================================================================
-- ADDITIONAL CONSTRAINTS
-- ============================================================================

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM pg_constraint
        WHERE conname = 'chk_response_hash'
          AND conrelid = 'query_engine.responses'::regclass
    ) THEN
        ALTER TABLE query_engine.responses
            ADD CONSTRAINT chk_response_hash
            CHECK
            (
                response_hash IS NULL
                OR
                response_hash ~ '^[A-Fa-f0-9]{64}$'
            );
    END IF;
END $$;

-- ============================================================================
-- TABLE COMMENT
-- ============================================================================

COMMENT ON TABLE query_engine.responses IS
'Stores every response generated while processing a logical query. Multiple responses may exist for a single query, including drafts, revisions, and the final answer.';

-- ============================================================================
-- COLUMN COMMENTS
-- ============================================================================

COMMENT ON COLUMN query_engine.responses.response_id IS
'Unique identifier of the generated response.';

COMMENT ON COLUMN query_engine.responses.query_id IS
'Logical query associated with this response.';

COMMENT ON COLUMN query_engine.responses.agent_execution_id IS
'Agent execution responsible for generating this response.';

COMMENT ON COLUMN query_engine.responses.response_text IS
'Complete generated response returned by OmniBrain.';

COMMENT ON COLUMN query_engine.responses.response_format IS
'Output format of the generated response.';

COMMENT ON COLUMN query_engine.responses.finish_reason IS
'Reason why generation stopped.';

COMMENT ON COLUMN query_engine.responses.is_streamed IS
'Indicates whether the response was streamed incrementally.';

COMMENT ON COLUMN query_engine.responses.stream_completed IS
'Indicates whether streaming completed successfully.';

COMMENT ON COLUMN query_engine.responses.is_final IS
'Marks whether this response represents the final answer returned to the user.';

COMMENT ON COLUMN query_engine.responses.response_language IS
'ISO 639-1 language code of the generated response.';

COMMENT ON COLUMN query_engine.responses.response_hash IS
'SHA-256 hash of the response content used for integrity verification and caching.';

COMMENT ON COLUMN query_engine.responses.metadata IS
'Flexible JSON metadata storing provider-specific information, generation parameters, safety information, and future extensions.';

COMMENT ON COLUMN query_engine.responses.version IS
'Schema version of this response record.';

COMMENT ON COLUMN query_engine.responses.created_at IS
'Timestamp when the response record was created.';

COMMENT ON COLUMN query_engine.responses.updated_at IS
'Timestamp automatically updated whenever the record changes.';

-- ============================================================================
-- UPDATED_AT TRIGGER
-- ============================================================================

DROP TRIGGER IF EXISTS trg_responses_updated_at ON query_engine.responses;

CREATE TRIGGER trg_responses_updated_at
BEFORE UPDATE
ON query_engine.responses
FOR EACH ROW
EXECUTE FUNCTION public.update_updated_at_column();