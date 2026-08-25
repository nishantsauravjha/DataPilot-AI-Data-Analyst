/*
===============================================================================
 OmniBrain Database Project
 Module      : Query Engine
 File        : 03_queries.sql
 Schema      : query_engine
 Author      : OmniBrain Database Team
 Description : Stores every logical query issued during a conversation.
===============================================================================

DESCRIPTION
-----------
A Query represents ONE logical request generated from a conversation turn.

The query table stores WHAT OmniBrain is trying to answer.

It intentionally does NOT store:

• Retrieved Context
• Agent Executions
• Responses
• Citations
• Feedback
• Metrics

Those belong to their own modules.

DEPENDENCIES
------------
query_engine.conversation_turns
query_engine.query_statuses
query_engine.query_intents
query_engine.retrieval_strategies
query_engine.query_priorities
knowledge.domains
public.update_updated_at_column()

REFERENCED BY
-------------
retrieved_context
agent_executions
responses
feedback
metrics

===============================================================================
*/

SET search_path TO query_engine, public;

-- ============================================================================
-- TABLE
-- ============================================================================

CREATE TABLE IF NOT EXISTS query_engine.queries
(

    ---------------------------------------------------------------------------
    -- Primary Key
    ---------------------------------------------------------------------------

    query_id UUID PRIMARY KEY
        DEFAULT uuid_generate_v4(),

    ---------------------------------------------------------------------------
    -- Relationships
    ---------------------------------------------------------------------------

    turn_id UUID NOT NULL,

    parent_query_id UUID,

    domain_id UUID,

    intent_id SMALLINT NOT NULL,

    status_id SMALLINT NOT NULL,

    strategy_id SMALLINT NOT NULL,

    priority_id SMALLINT NOT NULL,

    ---------------------------------------------------------------------------
    -- Query Text
    ---------------------------------------------------------------------------

    original_query TEXT NOT NULL,

    rewritten_query TEXT,

    normalized_query TEXT,

    language_code CHAR(2)
        DEFAULT 'en',

    ---------------------------------------------------------------------------
    -- Classification Confidence
    ---------------------------------------------------------------------------

    intent_confidence NUMERIC(5,4),

    domain_confidence NUMERIC(5,4),

    ---------------------------------------------------------------------------
    -- Retry Information
    ---------------------------------------------------------------------------

    retry_count SMALLINT NOT NULL
        DEFAULT 0,

    ---------------------------------------------------------------------------
    -- Flexible Metadata
    ---------------------------------------------------------------------------

    metadata JSONB NOT NULL
        DEFAULT '{}'::jsonb,

    ---------------------------------------------------------------------------
    -- Audit
    ---------------------------------------------------------------------------

    created_at TIMESTAMPTZ NOT NULL
        DEFAULT CURRENT_TIMESTAMP,

    updated_at TIMESTAMPTZ NOT NULL
        DEFAULT CURRENT_TIMESTAMP,

    deleted_at TIMESTAMPTZ,

    ---------------------------------------------------------------------------
    -- Constraints
    ---------------------------------------------------------------------------

    CONSTRAINT chk_retry_count
        CHECK (retry_count >= 0),

    CONSTRAINT chk_intent_confidence
        CHECK (
            intent_confidence IS NULL
            OR
            (
                intent_confidence >= 0
                AND intent_confidence <= 1
            )
        ),

    CONSTRAINT chk_domain_confidence
        CHECK (
            domain_confidence IS NULL
            OR
            (
                domain_confidence >= 0
                AND domain_confidence <= 1
            )
        ),

    CONSTRAINT chk_language_code
        CHECK (language_code ~ '^[a-z]{2}$'),

    ---------------------------------------------------------------------------
    -- Foreign Keys
    ---------------------------------------------------------------------------

    CONSTRAINT fk_query_turn
        FOREIGN KEY (turn_id)
        REFERENCES query_engine.conversation_turns(turn_id)
        ON UPDATE CASCADE
        ON DELETE CASCADE,

    CONSTRAINT fk_parent_query
        FOREIGN KEY (parent_query_id)
        REFERENCES query_engine.queries(query_id)
        ON UPDATE CASCADE
        ON DELETE SET NULL,

    CONSTRAINT fk_query_domain
        FOREIGN KEY (domain_id)
        REFERENCES knowledge.domains(domain_id)
        ON UPDATE CASCADE
        ON DELETE SET NULL,

    CONSTRAINT fk_query_intent
        FOREIGN KEY (intent_id)
        REFERENCES query_engine.query_intents(intent_id)
        ON UPDATE CASCADE
        ON DELETE RESTRICT,

    CONSTRAINT fk_query_status
        FOREIGN KEY (status_id)
        REFERENCES query_engine.query_statuses(status_id)
        ON UPDATE CASCADE
        ON DELETE RESTRICT,

    CONSTRAINT fk_query_strategy
        FOREIGN KEY (strategy_id)
        REFERENCES query_engine.retrieval_strategies(strategy_id)
        ON UPDATE CASCADE
        ON DELETE RESTRICT,

    CONSTRAINT fk_query_priority
        FOREIGN KEY (priority_id)
        REFERENCES query_engine.query_priorities(priority_id)
        ON UPDATE CASCADE
        ON DELETE RESTRICT

)

WITH
(
    fillfactor = 90
);

-- ============================================================================
-- COMMENTS
-- ============================================================================

COMMENT ON TABLE query_engine.queries IS
'Stores one logical processing request generated from a conversation turn.';

COMMENT ON COLUMN query_engine.queries.query_id IS
'Primary key of the logical query.';

COMMENT ON COLUMN query_engine.queries.turn_id IS
'Conversation turn that produced this query.';

COMMENT ON COLUMN query_engine.queries.parent_query_id IS
'Rewritten or retried parent query.';

COMMENT ON COLUMN query_engine.queries.domain_id IS
'Detected knowledge domain.';

COMMENT ON COLUMN query_engine.queries.intent_id IS
'Detected query intent.';

COMMENT ON COLUMN query_engine.queries.status_id IS
'Current execution state of the query.';

COMMENT ON COLUMN query_engine.queries.strategy_id IS
'Retrieval strategy selected by the router.';

COMMENT ON COLUMN query_engine.queries.priority_id IS
'Execution priority assigned to this query.';

COMMENT ON COLUMN query_engine.queries.original_query IS
'Original user input.';

COMMENT ON COLUMN query_engine.queries.rewritten_query IS
'Rewritten query generated by the query rewriter.';

COMMENT ON COLUMN query_engine.queries.normalized_query IS
'Canonical normalized representation used for analytics.';

COMMENT ON COLUMN query_engine.queries.language_code IS
'ISO 639-1 language code.';

COMMENT ON COLUMN query_engine.queries.intent_confidence IS
'Confidence score of intent classification.';

COMMENT ON COLUMN query_engine.queries.domain_confidence IS
'Confidence score of domain classification.';

COMMENT ON COLUMN query_engine.queries.retry_count IS
'Number of retries performed for this logical query.';

COMMENT ON COLUMN query_engine.queries.metadata IS
'Extensible JSON metadata for routing, filters, reasoning settings, collections, and future AI features.';

COMMENT ON COLUMN query_engine.queries.deleted_at IS
'Soft deletion timestamp.';

-- ============================================================================
-- TRIGGER
-- ============================================================================

DROP TRIGGER IF EXISTS trg_queries_updated_at ON query_engine.queries;

CREATE TRIGGER trg_queries_updated_at
BEFORE UPDATE
ON query_engine.queries
FOR EACH ROW
EXECUTE FUNCTION public.update_updated_at_column();