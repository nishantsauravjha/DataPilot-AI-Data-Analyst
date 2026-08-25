/*
===============================================================================
Project      : OmniBrain - Enterprise Agentic Multi-Modal RAG Platform
Schema       : auth
File         : 02_auth.sql
Version      : 1.0
Author       : Database Engineering Team

Description:
Creates the authentication and authorization schema for OmniBrain.

Dependencies:
    - 00_extensions.sql
    - 01_schemas.sql

Tables:
    - roles
    - users

===============================================================================
*/

BEGIN;

SET search_path TO auth;

-- ============================================================================
-- TABLE: roles
-- Purpose:
-- Stores all application roles used for Role-Based Access Control (RBAC).
-- ============================================================================

CREATE TABLE IF NOT EXISTS roles
(
    role_id UUID PRIMARY KEY
        DEFAULT gen_random_uuid(),

    role_name VARCHAR(50) NOT NULL,

    description TEXT,

    created_at TIMESTAMPTZ NOT NULL
        DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT uq_roles_role_name
        UNIQUE (role_name),

    CONSTRAINT chk_roles_role_name
        CHECK (length(trim(role_name)) > 0)
);

COMMENT ON TABLE roles IS
'Stores all application roles for Role-Based Access Control (RBAC).';

COMMENT ON COLUMN roles.role_id IS
'Primary key generated using UUID.';

COMMENT ON COLUMN roles.role_name IS
'Unique role name.';

COMMENT ON COLUMN roles.description IS
'Optional description of the role.';

COMMENT ON COLUMN roles.created_at IS
'Timestamp when the role was created.';


-- ============================================================================
-- TABLE: users
-- Purpose:
-- Stores authenticated OmniBrain users.
-- ============================================================================

CREATE TABLE IF NOT EXISTS users
(
    user_id UUID PRIMARY KEY
        DEFAULT gen_random_uuid(),

    role_id UUID NOT NULL,

    email VARCHAR(255) NOT NULL,

    full_name VARCHAR(150) NOT NULL,

    password_hash VARCHAR(255),

    is_active BOOLEAN NOT NULL
        DEFAULT TRUE,

    created_at TIMESTAMPTZ NOT NULL
        DEFAULT CURRENT_TIMESTAMP,

    updated_at TIMESTAMPTZ NOT NULL
        DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT uq_users_email
        UNIQUE (email),

    CONSTRAINT chk_users_email
        CHECK (
            email ~* '^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$'
        ),

    CONSTRAINT chk_users_full_name
        CHECK (
            length(trim(full_name)) > 0
        ),

    CONSTRAINT fk_users_role
        FOREIGN KEY (role_id)
        REFERENCES roles(role_id)
        ON UPDATE CASCADE
        ON DELETE RESTRICT
);

COMMENT ON TABLE users IS
'Stores authenticated OmniBrain users.';

COMMENT ON COLUMN users.user_id IS
'Primary key generated using UUID.';

COMMENT ON COLUMN users.role_id IS
'Foreign key referencing auth.roles.';

COMMENT ON COLUMN users.email IS
'Unique email address used for authentication.';

COMMENT ON COLUMN users.full_name IS
'Full name of the user.';

COMMENT ON COLUMN users.is_active IS
'Logical activation flag for the user account.';

COMMENT ON COLUMN users.created_at IS
'Timestamp when the user account was created.';

COMMENT ON COLUMN users.updated_at IS
'Timestamp when the user account was last updated.';


-- ============================================================================
-- INDEXES
-- ============================================================================

CREATE INDEX IF NOT EXISTS idx_users_role
    ON users(role_id);

CREATE INDEX IF NOT EXISTS idx_users_active
    ON users(is_active);

COMMENT ON INDEX idx_users_role IS
'Optimizes joins between users and roles.';

COMMENT ON INDEX idx_users_active IS
'Optimizes filtering of active users.';


-- ============================================================================
-- TRIGGER: set_updated_at
-- Purpose:
-- Automatically update `updated_at` on row updates for `users`.
-- ============================================================================

CREATE OR REPLACE FUNCTION auth.set_updated_at()
RETURNS TRIGGER AS
$$
BEGIN
    NEW.updated_at = clock_timestamp();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_users_set_updated_at ON users;

CREATE TRIGGER trg_users_set_updated_at
BEFORE UPDATE ON users
FOR EACH ROW
EXECUTE FUNCTION auth.set_updated_at();


-- ============================================================================
-- SEED DATA
-- ============================================================================

INSERT INTO roles
(
    role_name,
    description
)
VALUES
(
    'Admin',
    'Full system administrator with unrestricted access.'
),
(
    'Editor',
    'Can manage and curate knowledge assets.'
),
(
    'Viewer',
    'Read-only access to the knowledge base.'
)
ON CONFLICT (role_name)
DO NOTHING;

COMMIT;
