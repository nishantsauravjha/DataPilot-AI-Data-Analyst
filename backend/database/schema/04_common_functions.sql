-- ============================================================================
-- FILE: 04_common_functions.sql
-- AUTHOR: OmniBrain Database Team
-- DESCRIPTION:
--     Shared reusable PostgreSQL functions and triggers.
-- ============================================================================

SET search_path TO common, public;

-- ============================================================================
-- FUNCTION: common.set_updated_at()
--
-- Automatically updates the updated_at timestamp before every UPDATE.
-- ============================================================================

CREATE OR REPLACE FUNCTION common.set_updated_at()
RETURNS TRIGGER
LANGUAGE plpgsql
AS
$$
BEGIN
    NEW.updated_at := CURRENT_TIMESTAMP;
    RETURN NEW;
END;
$$;

COMMENT ON FUNCTION common.set_updated_at() IS
'Automatically updates updated_at before row modification.';






/*
===============================================================================
FUNCTION: common.validate_resource_tag()
SCHEMA: common

PURPOSE:
    Validates that the resource referenced by structured.resource_tags exists
    before allowing a tag assignment.

DESCRIPTION:
    Since resource_tags uses a polymorphic relationship
    (resource_type + resource_id), PostgreSQL cannot enforce referential
    integrity using standard foreign keys.

    This trigger validates that:

        DATASET      -> structured.datasets
        TABLE        -> structured.dataset_tables
        COLUMN       -> structured.dataset_columns
        RELATIONSHIP -> structured.dataset_relationships

RETURNS:
    TRIGGER

POSTGRESQL:
    Compatible with PostgreSQL 17+

===============================================================================
*/

CREATE OR REPLACE FUNCTION common.validate_resource_tag()
RETURNS TRIGGER
LANGUAGE plpgsql
AS
$$
BEGIN

    CASE NEW.resource_type

        ------------------------------------------------------------------------
        -- DATASET
        ------------------------------------------------------------------------
        WHEN 'DATASET' THEN

            IF NOT EXISTS
            (
                SELECT 1
                FROM structured.datasets
                WHERE dataset_id = NEW.resource_id
            )
            THEN
                RAISE EXCEPTION
                    'Dataset (%) does not exist.',
                    NEW.resource_id
                    USING ERRCODE = '23503';
            END IF;

        ------------------------------------------------------------------------
        -- TABLE
        ------------------------------------------------------------------------
        WHEN 'TABLE' THEN

            IF NOT EXISTS
            (
                SELECT 1
                FROM structured.dataset_tables
                WHERE table_id = NEW.resource_id
            )
            THEN
                RAISE EXCEPTION
                    'Table (%) does not exist.',
                    NEW.resource_id
                    USING ERRCODE = '23503';
            END IF;

        ------------------------------------------------------------------------
        -- COLUMN
        ------------------------------------------------------------------------
        WHEN 'COLUMN' THEN

            IF NOT EXISTS
            (
                SELECT 1
                FROM structured.dataset_columns
                WHERE column_id = NEW.resource_id
            )
            THEN
                RAISE EXCEPTION
                    'Column (%) does not exist.',
                    NEW.resource_id
                    USING ERRCODE = '23503';
            END IF;

        ------------------------------------------------------------------------
        -- RELATIONSHIP
        ------------------------------------------------------------------------
        WHEN 'RELATIONSHIP' THEN

            IF NOT EXISTS
            (
                SELECT 1
                FROM structured.dataset_relationships
                WHERE relationship_id = NEW.resource_id
            )
            THEN
                RAISE EXCEPTION
                    'Relationship (%) does not exist.',
                    NEW.resource_id
                    USING ERRCODE = '23503';
            END IF;

        ------------------------------------------------------------------------
        -- UNKNOWN RESOURCE TYPE
        ------------------------------------------------------------------------
        ELSE

            RAISE EXCEPTION
                'Unsupported resource_type: %',
                NEW.resource_type
                USING ERRCODE = '22023';

    END CASE;

    RETURN NEW;

END;
$$;


-- ============================================================================
-- AUTH SCHEMA TRIGGERS
-- Automatically update updated_at timestamp
-- ============================================================================

DROP TRIGGER IF EXISTS trg_users_bu_set_updated_at
ON auth.users;

DROP TRIGGER IF EXISTS trg_users_bu_set_updated_at ON auth.users;

CREATE TRIGGER trg_users_bu_set_updated_at
BEFORE UPDATE
ON auth.users
FOR EACH ROW
EXECUTE FUNCTION common.set_updated_at();


SET search_path TO public;

-- ============================================================================
-- FUNCTION : update_updated_at_column()
-- Description:
-- Automatically updates the updated_at timestamp before every UPDATE.
-- ============================================================================

CREATE OR REPLACE FUNCTION public.update_updated_at_column()
RETURNS TRIGGER
LANGUAGE plpgsql
AS
$$
BEGIN
    NEW.updated_at := CURRENT_TIMESTAMP;
    RETURN NEW;
END;
$$;

COMMENT ON FUNCTION public.update_updated_at_column() IS
'Automatically updates the updated_at column before UPDATE operations.';