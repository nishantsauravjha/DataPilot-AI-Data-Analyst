/*
===============================================================================
Project      : OmniBrain - Enterprise Agentic Multi-Modal RAG Platform
Schema       : auth
File         : 03_auth_sessions.sql
Version      : 1.0
Author       : OmniBrain Database Team

Description:
Adds token session and auth rate limit event tables for authentication lifecycle management.

Dependencies:
    - 00_extensions.sql
    - 01_schemas.sql
    - 02_auth.sql
===============================================================================
*/

BEGIN;

SET search_path TO auth;

-- ==========================================================================
-- TABLE: token_sessions
-- Purpose:
-- Stores JWT session metadata to support token revocation and logout.
-- ==========================================================================

CREATE TABLE IF NOT EXISTS token_sessions
(
    token_id UUID PRIMARY KEY
        DEFAULT gen_random_uuid(),

    user_id UUID NOT NULL
        REFERENCES users(user_id)
        ON DELETE RESTRICT,

    issued_at TIMESTAMPTZ NOT NULL,

    expires_at TIMESTAMPTZ NOT NULL,

    revoked_at TIMESTAMPTZ NULL,

    revocation_reason TEXT NULL,

    created_at TIMESTAMPTZ NOT NULL
        DEFAULT CURRENT_TIMESTAMP
);

COMMENT ON TABLE token_sessions IS
'Stores JWT session records for authentication token revocation and logout.';

COMMENT ON COLUMN token_sessions.token_id IS
'Unique token session identifier used as the JWT jti.';

COMMENT ON COLUMN token_sessions.user_id IS
'Authenticated user associated with the token session.';

COMMENT ON COLUMN token_sessions.issued_at IS
'Timestamp when the token was issued.';

COMMENT ON COLUMN token_sessions.expires_at IS
'Timestamp when the token expires.';

COMMENT ON COLUMN token_sessions.revoked_at IS
'Timestamp when the token session was revoked.';

COMMENT ON COLUMN token_sessions.revocation_reason IS
'Optional reason for revocation, e.g. logout.';

COMMENT ON COLUMN token_sessions.created_at IS
'Timestamp when the session row was created.';

CREATE INDEX IF NOT EXISTS idx_token_sessions_user_expires
    ON token_sessions(user_id, expires_at);

COMMENT ON INDEX idx_token_sessions_user_expires IS
'Optimizes authentication lookups by user and expiry date.';

-- ==========================================================================
-- TABLE: auth_rate_limit_events
-- Purpose:
-- Stores authentication rate limit events for login/register protection.
-- ==========================================================================

CREATE TABLE IF NOT EXISTS auth_rate_limit_events
(
    event_id UUID PRIMARY KEY
        DEFAULT gen_random_uuid(),

    endpoint TEXT NOT NULL,

    request_key TEXT NOT NULL,

    created_at TIMESTAMPTZ NOT NULL
        DEFAULT CURRENT_TIMESTAMP
);

COMMENT ON TABLE auth_rate_limit_events IS
'Stores auth rate limit events for login and register throttling.';

COMMENT ON COLUMN auth_rate_limit_events.endpoint IS
'Authentication endpoint associated with the rate limit event.';

COMMENT ON COLUMN auth_rate_limit_events.request_key IS
'Hashed request key used to identify rate limit buckets.';

COMMENT ON COLUMN auth_rate_limit_events.created_at IS
'Timestamp when the rate limit event was recorded.';

CREATE INDEX IF NOT EXISTS idx_auth_rate_limit_events_key
    ON auth_rate_limit_events(endpoint, request_key, created_at);

COMMENT ON INDEX idx_auth_rate_limit_events_key IS
'Optimizes rate limit lookups by endpoint, key, and timestamp.';

COMMIT;
