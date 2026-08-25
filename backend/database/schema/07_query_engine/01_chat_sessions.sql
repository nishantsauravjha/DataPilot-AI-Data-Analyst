/*
===============================================================================
OmniBrain Database Project
Module      : Query Engine
File        : 01_chat_sessions.sql
Schema      : query_engine
Author      : OmniBrain Database Team
Description : Stores chat sessions initiated by users.
===============================================================================

A Chat Session represents one complete conversation between a user and
OmniBrain.

One session contains

• Conversation Turns
• Queries
• Responses
• Citations
• Feedback
• Metrics

Dependencies
------------
auth.users
knowledge.domains
public.update_updated_at_column()

Referenced By
-------------
query_engine.conversation_turns
query_engine.queries

===============================================================================
*/

SET search_path TO query_engine, public;

-- ============================================================================
-- ENUM TYPES
-- ============================================================================

DO $$
BEGIN
    IF NOT EXISTS
    (
        SELECT 1
        FROM pg_type
        WHERE typname='session_status_enum'
    )
    THEN

        CREATE TYPE query_engine.session_status_enum AS ENUM
        (
            'ACTIVE',
            'ARCHIVED',
            'COMPLETED',
            'DELETED'
        );

    END IF;
END
$$;

-- ============================================================================
-- CHAT SESSIONS
-- ============================================================================

CREATE TABLE IF NOT EXISTS query_engine.chat_sessions
(

    ---------------------------------------------------------------------------
    -- Primary Key
    ---------------------------------------------------------------------------

    session_id UUID PRIMARY KEY
        DEFAULT uuid_generate_v4(),

    ---------------------------------------------------------------------------
    -- Ownership
    ---------------------------------------------------------------------------

    user_id UUID NOT NULL,

    domain_id UUID,

    ---------------------------------------------------------------------------
    -- Session Information
    ---------------------------------------------------------------------------

    session_title VARCHAR(255) NOT NULL,

    description TEXT,

    active_model VARCHAR(100),

    system_prompt TEXT,

    status query_engine.session_status_enum
        NOT NULL
        DEFAULT 'ACTIVE',

    ---------------------------------------------------------------------------
    -- Cached Analytics
    ---------------------------------------------------------------------------

    total_turns INTEGER NOT NULL
        DEFAULT 0,

    total_queries INTEGER NOT NULL
        DEFAULT 0,

    ---------------------------------------------------------------------------
    -- Flexible Metadata
    ---------------------------------------------------------------------------

    metadata JSONB NOT NULL
        DEFAULT '{}'::jsonb,

    ---------------------------------------------------------------------------
    -- Audit Columns
    ---------------------------------------------------------------------------

    last_activity_at TIMESTAMPTZ
        DEFAULT CURRENT_TIMESTAMP,

    created_at TIMESTAMPTZ NOT NULL
        DEFAULT CURRENT_TIMESTAMP,

    updated_at TIMESTAMPTZ NOT NULL
        DEFAULT CURRENT_TIMESTAMP,

    archived_at TIMESTAMPTZ,

    deleted_at TIMESTAMPTZ,

    ---------------------------------------------------------------------------
    -- Constraints
    ---------------------------------------------------------------------------

    CONSTRAINT chk_total_turns
        CHECK (total_turns >= 0),

    CONSTRAINT chk_total_queries
        CHECK (total_queries >= 0),

    ---------------------------------------------------------------------------
    -- Foreign Keys
    ---------------------------------------------------------------------------

    CONSTRAINT fk_chat_session_user
        FOREIGN KEY (user_id)
        REFERENCES auth.users(user_id)
        ON UPDATE CASCADE
        ON DELETE CASCADE,

    CONSTRAINT fk_chat_session_domain
        FOREIGN KEY (domain_id)
        REFERENCES knowledge.domains(domain_id)
        ON UPDATE CASCADE
        ON DELETE SET NULL

)

WITH
(
    fillfactor = 90
);

-- ============================================================================
-- COMMENTS
-- ============================================================================

COMMENT ON TABLE query_engine.chat_sessions IS
'Stores every chat session initiated by users. A chat session is the root entity for conversation turns, queries, responses, citations, feedback, and metrics.';

COMMENT ON COLUMN query_engine.chat_sessions.session_id IS
'Unique identifier for the chat session.';

COMMENT ON COLUMN query_engine.chat_sessions.user_id IS
'User who owns this chat session.';

COMMENT ON COLUMN query_engine.chat_sessions.domain_id IS
'Knowledge domain associated with the conversation.';

COMMENT ON COLUMN query_engine.chat_sessions.session_title IS
'Human-readable title generated automatically or edited by the user.';

COMMENT ON COLUMN query_engine.chat_sessions.description IS
'Optional description of the session.';

COMMENT ON COLUMN query_engine.chat_sessions.active_model IS
'LLM currently assigned to the session.';

COMMENT ON COLUMN query_engine.chat_sessions.system_prompt IS
'System prompt applied to this chat session.';

COMMENT ON COLUMN query_engine.chat_sessions.status IS
'Lifecycle status of the session.';

COMMENT ON COLUMN query_engine.chat_sessions.total_turns IS
'Cached number of conversation turns.';

COMMENT ON COLUMN query_engine.chat_sessions.total_queries IS
'Cached number of user queries.';

COMMENT ON COLUMN query_engine.chat_sessions.metadata IS
'Extensible JSON metadata for session configuration, retrieval preferences, UI settings, attached collections, and future features.';

COMMENT ON COLUMN query_engine.chat_sessions.last_activity_at IS
'Timestamp of the latest interaction within the session.';

COMMENT ON COLUMN query_engine.chat_sessions.created_at IS
'Session creation timestamp.';

COMMENT ON COLUMN query_engine.chat_sessions.updated_at IS
'Automatically updated whenever the row changes.';

COMMENT ON COLUMN query_engine.chat_sessions.archived_at IS
'Timestamp when the session was archived.';

COMMENT ON COLUMN query_engine.chat_sessions.deleted_at IS
'Soft deletion timestamp.';

-- ============================================================================
-- UPDATED_AT TRIGGER
-- ============================================================================

DROP TRIGGER IF EXISTS trg_chat_sessions_updated_at ON query_engine.chat_sessions;

CREATE TRIGGER trg_chat_sessions_updated_at
BEFORE UPDATE
ON query_engine.chat_sessions
FOR EACH ROW
EXECUTE FUNCTION public.update_updated_at_column();