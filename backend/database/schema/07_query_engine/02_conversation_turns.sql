/*
===============================================================================
OmniBrain Database Project
Module      : Query Engine
File        : 02_conversation_turns.sql
Schema      : query_engine
Author      : OmniBrain Database Team
Description : Stores every message exchanged inside a chat session.
===============================================================================

A Conversation Turn represents ONE message exchanged between the user,
assistant, system, or future agents/tools.

Example

User      : Explain Newton's Laws.
Assistant : ...
User      : Give an example.
Assistant : ...

This table stores ALL of the above.

Dependencies
------------
query_engine.chat_sessions
public.update_updated_at_column()

Referenced By
-------------
query_engine.queries

===============================================================================
*/

SET search_path TO query_engine, public;

-- ============================================================================
-- ENUM TYPES
-- ============================================================================

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM pg_type
        WHERE typname = 'sender_type_enum'
    ) THEN
        CREATE TYPE query_engine.sender_type_enum AS ENUM
        (
            'USER',
            'ASSISTANT',
            'SYSTEM',
            'TOOL',
            'AGENT'
        );
    END IF;
END
$$;

-- ============================================================================
-- TABLE
-- ============================================================================

CREATE TABLE IF NOT EXISTS query_engine.conversation_turns
(

    ---------------------------------------------------------------------------
    -- Primary Key
    ---------------------------------------------------------------------------

    turn_id UUID PRIMARY KEY
        DEFAULT uuid_generate_v4(),

    ---------------------------------------------------------------------------
    -- Relationships
    ---------------------------------------------------------------------------

    session_id UUID NOT NULL,

    parent_turn_id UUID,

    ---------------------------------------------------------------------------
    -- Conversation Information
    ---------------------------------------------------------------------------

    turn_number INTEGER NOT NULL,

    sender_type query_engine.sender_type_enum NOT NULL,

    message TEXT NOT NULL,

    ---------------------------------------------------------------------------
    -- LLM Information
    ---------------------------------------------------------------------------

    model_name VARCHAR(100),

    prompt_tokens INTEGER NOT NULL
        DEFAULT 0,

    completion_tokens INTEGER NOT NULL
        DEFAULT 0,

    total_tokens INTEGER
        GENERATED ALWAYS AS
        (
            prompt_tokens + completion_tokens
        ) STORED,

    latency_ms INTEGER,

    ---------------------------------------------------------------------------
    -- Versioning
    ---------------------------------------------------------------------------

    is_edited BOOLEAN NOT NULL
        DEFAULT FALSE,

    is_regenerated BOOLEAN NOT NULL
        DEFAULT FALSE,

    ---------------------------------------------------------------------------
    -- Extensible Metadata
    ---------------------------------------------------------------------------

    metadata JSONB NOT NULL
        DEFAULT '{}'::jsonb,

    ---------------------------------------------------------------------------
    -- Audit Columns
    ---------------------------------------------------------------------------

    created_at TIMESTAMPTZ NOT NULL
        DEFAULT CURRENT_TIMESTAMP,

    updated_at TIMESTAMPTZ NOT NULL
        DEFAULT CURRENT_TIMESTAMP,

    ---------------------------------------------------------------------------
    -- Constraints
    ---------------------------------------------------------------------------

    CONSTRAINT uq_conversation_turn
        UNIQUE (session_id, turn_number),

    CONSTRAINT chk_turn_number
        CHECK (turn_number > 0),

    CONSTRAINT chk_prompt_tokens
        CHECK (prompt_tokens >= 0),

    CONSTRAINT chk_completion_tokens
        CHECK (completion_tokens >= 0),

    CONSTRAINT chk_latency
        CHECK (
            latency_ms IS NULL
            OR latency_ms >= 0
        ),

    ---------------------------------------------------------------------------
    -- Foreign Keys
    ---------------------------------------------------------------------------

    CONSTRAINT fk_turn_session
        FOREIGN KEY (session_id)
        REFERENCES query_engine.chat_sessions(session_id)
        ON UPDATE CASCADE
        ON DELETE CASCADE,

    CONSTRAINT fk_parent_turn
        FOREIGN KEY (parent_turn_id)
        REFERENCES query_engine.conversation_turns(turn_id)
        ON UPDATE CASCADE
        ON DELETE SET NULL

)

WITH (
    fillfactor = 90
);

-- ============================================================================
-- COMMENTS
-- ============================================================================

COMMENT ON TABLE query_engine.conversation_turns IS
'Stores every message exchanged inside a chat session.';

COMMENT ON COLUMN query_engine.conversation_turns.turn_id IS
'Primary key of the conversation turn.';

COMMENT ON COLUMN query_engine.conversation_turns.session_id IS
'Chat session that owns this conversation turn.';

COMMENT ON COLUMN query_engine.conversation_turns.parent_turn_id IS
'Original turn referenced when a response is regenerated.';

COMMENT ON COLUMN query_engine.conversation_turns.turn_number IS
'Sequential ordering of turns within a session.';

COMMENT ON COLUMN query_engine.conversation_turns.sender_type IS
'Originator of the message (USER, ASSISTANT, SYSTEM, TOOL, AGENT).';

COMMENT ON COLUMN query_engine.conversation_turns.message IS
'Complete message content.';

COMMENT ON COLUMN query_engine.conversation_turns.model_name IS
'LLM used to generate assistant responses.';

COMMENT ON COLUMN query_engine.conversation_turns.prompt_tokens IS
'Prompt tokens consumed.';

COMMENT ON COLUMN query_engine.conversation_turns.completion_tokens IS
'Completion tokens generated.';

COMMENT ON COLUMN query_engine.conversation_turns.total_tokens IS
'Automatically computed total token count.';

COMMENT ON COLUMN query_engine.conversation_turns.latency_ms IS
'LLM response latency in milliseconds.';

COMMENT ON COLUMN query_engine.conversation_turns.is_edited IS
'Whether the message was edited after creation.';

COMMENT ON COLUMN query_engine.conversation_turns.is_regenerated IS
'Whether this turn was generated via regeneration.';

COMMENT ON COLUMN query_engine.conversation_turns.metadata IS
'Extensible JSON metadata (attachments, routing info, tool outputs, UI metadata, etc.).';

COMMENT ON COLUMN query_engine.conversation_turns.created_at IS
'Timestamp when the turn was created.';

COMMENT ON COLUMN query_engine.conversation_turns.updated_at IS
'Timestamp automatically updated whenever the row changes.';

-- ============================================================================
-- UPDATED_AT TRIGGER
-- ============================================================================

DROP TRIGGER IF EXISTS trg_conversation_turns_updated_at ON query_engine.conversation_turns;

CREATE TRIGGER trg_conversation_turns_updated_at
BEFORE UPDATE
ON query_engine.conversation_turns
FOR EACH ROW
EXECUTE FUNCTION public.update_updated_at_column();