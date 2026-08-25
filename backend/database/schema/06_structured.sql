-- ============================================================================
-- TABLE: structured.data_sources
-- DESCRIPTION:
--     Stores metadata describing registered structured data sources used by
--     OmniBrain. A data source represents the origin of structured data such
--     as relational databases, CSV files, Excel workbooks, JSON files,
--     Parquet files, cloud storage objects, or REST APIs.
--
-- NOTES:
--     - Metadata only.
--     - No credentials or secrets are stored.
--     - One data source may contain multiple logical datasets.
-- ============================================================================

CREATE TABLE IF NOT EXISTS structured.data_sources (

    ---------------------------------------------------------------------------
    -- Primary Key
    ---------------------------------------------------------------------------

    source_id UUID
        PRIMARY KEY
        DEFAULT gen_random_uuid(),

    ---------------------------------------------------------------------------
    -- Source Information
    ---------------------------------------------------------------------------

    source_name VARCHAR(150)
        NOT NULL,

    source_type VARCHAR(30)
        NOT NULL,

    connection_mode VARCHAR(20)
        NOT NULL,

    connection_identifier TEXT
        NOT NULL,

    description TEXT,

    owner_name VARCHAR(150),

    ---------------------------------------------------------------------------
    -- Operational Metadata
    ---------------------------------------------------------------------------

    supports_incremental_refresh BOOLEAN
        NOT NULL
        DEFAULT FALSE,

    last_connection_check TIMESTAMPTZ,

    source_status VARCHAR(20)
        NOT NULL
        DEFAULT 'ACTIVE',

    is_active BOOLEAN
        NOT NULL
        DEFAULT TRUE,

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

    CONSTRAINT uq_data_sources_source_name
        UNIQUE (source_name),

    CONSTRAINT chk_data_sources_source_name
        CHECK (length(trim(source_name)) > 0),

    CONSTRAINT chk_data_sources_connection_identifier
        CHECK (length(trim(connection_identifier)) > 0),

    CONSTRAINT chk_data_sources_source_type
        CHECK (
            source_type IN (
                'POSTGRESQL',
                'MYSQL',
                'SQLSERVER',
                'SQLITE',
                'ORACLE',
                'MONGODB',
                'DUCKDB',
                'CSV',
                'EXCEL',
                'JSON',
                'PARQUET',
                'REST_API',
                'GOOGLE_SHEETS',
                'SNOWFLAKE',
                'BIGQUERY',
                'OTHER'
            )
        ),

    CONSTRAINT chk_data_sources_connection_mode
        CHECK (
            connection_mode IN (
                'LOCAL',
                'REMOTE',
                'CLOUD'
            )
        ),

    CONSTRAINT chk_data_sources_status
        CHECK (
            source_status IN (
                'ACTIVE',
                'INACTIVE',
                'ERROR',
                'ARCHIVED'
            )
        )

);

-- ============================================================================
-- INDEXES
-- ============================================================================

CREATE INDEX IF NOT EXISTS idx_data_sources_source_type
ON structured.data_sources(source_type);

CREATE INDEX IF NOT EXISTS idx_data_sources_status
ON structured.data_sources(source_status);

CREATE INDEX IF NOT EXISTS idx_data_sources_connection_mode
ON structured.data_sources(connection_mode);

CREATE INDEX IF NOT EXISTS idx_data_sources_last_connection_check
ON structured.data_sources(last_connection_check);

CREATE INDEX IF NOT EXISTS idx_data_sources_active
ON structured.data_sources(is_active)
WHERE is_active = TRUE;

-- ============================================================================
-- TRIGGER
-- ============================================================================

DROP TRIGGER IF EXISTS trg_data_sources_bu_set_updated_at ON structured.data_sources;

CREATE TRIGGER trg_data_sources_bu_set_updated_at
BEFORE UPDATE
ON structured.data_sources
FOR EACH ROW
EXECUTE FUNCTION common.set_updated_at();

-- ============================================================================
-- COMMENTS
-- ============================================================================

COMMENT ON TABLE structured.data_sources IS
'Registered structured data sources used by OmniBrain. Stores metadata only and never stores credentials or the actual data.';

COMMENT ON COLUMN structured.data_sources.source_id IS
'Primary key identifying the structured data source.';

COMMENT ON COLUMN structured.data_sources.source_name IS
'Unique human-readable name of the data source.';

COMMENT ON COLUMN structured.data_sources.source_type IS
'Technology or format of the structured data source.';

COMMENT ON COLUMN structured.data_sources.connection_mode IS
'Indicates whether the source is local, remote, or cloud-hosted.';

COMMENT ON COLUMN structured.data_sources.connection_identifier IS
'Non-sensitive identifier such as file path, hostname, URL, bucket path, or database name.';

COMMENT ON COLUMN structured.data_sources.description IS
'Optional description of the data source.';

COMMENT ON COLUMN structured.data_sources.owner_name IS
'Logical owner or responsible team for the data source.';

COMMENT ON COLUMN structured.data_sources.supports_incremental_refresh IS
'Indicates whether incremental synchronization is supported.';

COMMENT ON COLUMN structured.data_sources.last_connection_check IS
'Timestamp of the most recent successful or attempted connectivity check.';

COMMENT ON COLUMN structured.data_sources.source_status IS
'Current operational state of the data source.';

COMMENT ON COLUMN structured.data_sources.is_active IS
'Indicates whether the data source is enabled for ingestion.';

COMMENT ON COLUMN structured.data_sources.created_at IS
'Timestamp when the data source metadata was created.';

COMMENT ON COLUMN structured.data_sources.updated_at IS
'Timestamp when the data source metadata was last modified.';





/*
===============================================================================
TABLE: structured.datasets
PURPOSE:
    Stores metadata for every structured dataset registered in OmniBrain.

DESCRIPTION:
    A dataset represents a logical collection of structured tables originating
    from a single data source (PostgreSQL, MySQL, Snowflake, CSV, Excel, etc.).

    This table stores ONLY dataset-level metadata.

    Individual tables, columns, constraints, statistics, relationships,
    profiling information, and synchronization history are maintained in
    dedicated tables.

===============================================================================
*/

CREATE TABLE IF NOT EXISTS structured.datasets
(
    ---------------------------------------------------------------------------
    -- Primary Key
    ---------------------------------------------------------------------------
    dataset_id UUID
        PRIMARY KEY
        DEFAULT gen_random_uuid(),

    ---------------------------------------------------------------------------
    -- Parent Data Source
    ---------------------------------------------------------------------------
    source_id UUID
        NOT NULL,

    ---------------------------------------------------------------------------
    -- Dataset Identity
    ---------------------------------------------------------------------------
    dataset_name VARCHAR(255)
        NOT NULL,

    display_name VARCHAR(255),

    description TEXT,

    ---------------------------------------------------------------------------
    -- Database Information
    ---------------------------------------------------------------------------
    database_name VARCHAR(255)
        NOT NULL,

    database_schema VARCHAR(255)
        NOT NULL,

    ---------------------------------------------------------------------------
    -- Dataset Classification
    ---------------------------------------------------------------------------
    dataset_type VARCHAR(50)
        NOT NULL,

    database_engine VARCHAR(50)
        NOT NULL,

    dataset_status VARCHAR(30)
        NOT NULL
        DEFAULT 'active',

    ---------------------------------------------------------------------------
    -- Versioning
    ---------------------------------------------------------------------------
    dataset_version VARCHAR(50)
        DEFAULT '1.0',

    ---------------------------------------------------------------------------
    -- Synchronization Metadata
    ---------------------------------------------------------------------------
    last_synced_at TIMESTAMPTZ,

    ---------------------------------------------------------------------------
    -- Optional Notes
    ---------------------------------------------------------------------------
    remarks TEXT,

    ---------------------------------------------------------------------------
    -- Audit Columns
    ---------------------------------------------------------------------------
    created_at TIMESTAMPTZ
        NOT NULL
        DEFAULT CURRENT_TIMESTAMP,

    updated_at TIMESTAMPTZ
        NOT NULL
        DEFAULT CURRENT_TIMESTAMP,

    ---------------------------------------------------------------------------
    -- Foreign Key
    ---------------------------------------------------------------------------
    CONSTRAINT fk_datasets_datasource
    FOREIGN KEY (source_id)
    REFERENCES structured.data_sources(source_id)
    ON DELETE CASCADE
    ON UPDATE CASCADE,

    ---------------------------------------------------------------------------
    -- Unique Dataset inside a Data Source
    ---------------------------------------------------------------------------
    CONSTRAINT uq_datasets_unique_name
        UNIQUE
        (
            source_id,
            database_schema,
            dataset_name
        ),

    ---------------------------------------------------------------------------
    -- Dataset Type Validation
    ---------------------------------------------------------------------------
    CONSTRAINT chk_datasets_dataset_type
        CHECK
        (
            dataset_type IN
            (
                'transactional',
                'warehouse',
                'lakehouse',
                'analytics',
                'reporting'
            )
        ),

    ---------------------------------------------------------------------------
    -- Database Engine Validation
    ---------------------------------------------------------------------------
    CONSTRAINT chk_datasets_database_engine
        CHECK
        (
            database_engine IN
            (
                'postgresql',
                'mysql',
                'oracle',
                'sqlserver',
                'sqlite',
                'snowflake',
                'bigquery',
                'duckdb',
                'csv',
                'excel'
            )
        ),

    ---------------------------------------------------------------------------
    -- Dataset Status Validation
    ---------------------------------------------------------------------------
    CONSTRAINT chk_datasets_status
        CHECK
        (
            dataset_status IN
            (
                'active',
                'inactive',
                'archived',
                'failed'
            )
        )
);

-- ============================================================================
-- INDEXES
-- ============================================================================

CREATE INDEX IF NOT EXISTS idx_datasets_datasource
ON structured.datasets(source_id);

CREATE INDEX IF NOT EXISTS idx_datasets_name
ON structured.datasets(dataset_name);

CREATE INDEX IF NOT EXISTS idx_datasets_status
ON structured.datasets(dataset_status);

CREATE INDEX IF NOT EXISTS idx_datasets_engine
ON structured.datasets(database_engine);

CREATE INDEX IF NOT EXISTS idx_datasets_last_synced
ON structured.datasets(last_synced_at);

-- ============================================================================
-- UPDATED_AT TRIGGER
-- ============================================================================

DROP TRIGGER IF EXISTS trg_datasets_set_updated_at ON structured.datasets;

CREATE TRIGGER trg_datasets_set_updated_at
BEFORE UPDATE ON structured.datasets
FOR EACH ROW
EXECUTE FUNCTION common.set_updated_at();

-- ============================================================================
-- TABLE COMMENT
-- ============================================================================

COMMENT ON TABLE structured.datasets IS
'Stores metadata describing structured datasets registered within OmniBrain.';

COMMENT ON COLUMN structured.datasets.dataset_id IS
'Unique identifier for the dataset.';

COMMENT ON COLUMN structured.datasets.source_id IS
'Reference to the parent structured data source.';

COMMENT ON COLUMN structured.datasets.dataset_name IS
'Internal dataset name from the source system.';

COMMENT ON COLUMN structured.datasets.display_name IS
'Human-readable dataset name displayed in the UI.';

COMMENT ON COLUMN structured.datasets.description IS
'Business description of the dataset.';

COMMENT ON COLUMN structured.datasets.database_name IS
'Physical database containing the dataset.';

COMMENT ON COLUMN structured.datasets.database_schema IS
'Database schema containing the dataset.';

COMMENT ON COLUMN structured.datasets.dataset_type IS
'Logical dataset classification such as warehouse, analytics, or transactional.';

COMMENT ON COLUMN structured.datasets.database_engine IS
'Underlying database engine or structured source technology.';

COMMENT ON COLUMN structured.datasets.dataset_status IS
'Current operational status of the dataset.';

COMMENT ON COLUMN structured.datasets.dataset_version IS
'Logical version identifier for the dataset metadata.';

COMMENT ON COLUMN structured.datasets.last_synced_at IS
'Timestamp of the most recent successful synchronization.';

COMMENT ON COLUMN structured.datasets.remarks IS
'Optional administrator notes.';

COMMENT ON COLUMN structured.datasets.created_at IS
'Timestamp when the dataset metadata was created.';

COMMENT ON COLUMN structured.datasets.updated_at IS
'Timestamp when the dataset metadata was last updated.';






/*
===============================================================================
TABLE: structured.dataset_tables

DESCRIPTION
-----------
Stores metadata describing every physical table or view belonging to a
structured dataset.

This table stores ONLY table-level metadata.

Actual table rows remain in the source database.
Column definitions are stored separately in
structured.dataset_columns.
===============================================================================
*/

CREATE TABLE IF NOT EXISTS structured.dataset_tables
(
    ---------------------------------------------------------------------------
    -- Primary Key
    ---------------------------------------------------------------------------
    table_id UUID
        PRIMARY KEY
        DEFAULT gen_random_uuid(),

    ---------------------------------------------------------------------------
    -- Parent Dataset
    ---------------------------------------------------------------------------
    dataset_id UUID
        NOT NULL,

    ---------------------------------------------------------------------------
    -- Table Identity
    ---------------------------------------------------------------------------
    table_name VARCHAR(255)
        NOT NULL,

    display_name VARCHAR(255),

    table_schema VARCHAR(255)
        NOT NULL,

    description TEXT,

    ---------------------------------------------------------------------------
    -- Table Classification
    ---------------------------------------------------------------------------
    table_type VARCHAR(30)
        NOT NULL
        DEFAULT 'BASE_TABLE',

    storage_engine VARCHAR(100),

    ---------------------------------------------------------------------------
    -- Operational Metadata
    ---------------------------------------------------------------------------
    table_status VARCHAR(20)
        NOT NULL
        DEFAULT 'ACTIVE',

    last_synced_at TIMESTAMPTZ,

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
    -- Foreign Key
    ---------------------------------------------------------------------------
    CONSTRAINT fk_dataset_tables_dataset
        FOREIGN KEY (dataset_id)
        REFERENCES structured.datasets(dataset_id)
        ON DELETE CASCADE,

    ---------------------------------------------------------------------------
    -- Unique Constraint
    ---------------------------------------------------------------------------
    CONSTRAINT uq_dataset_tables_name
        UNIQUE
        (
            dataset_id,
            table_schema,
            table_name
        ),

    ---------------------------------------------------------------------------
    -- Table Name Validation
    ---------------------------------------------------------------------------
    CONSTRAINT chk_dataset_tables_name
        CHECK (length(trim(table_name)) > 0),

    ---------------------------------------------------------------------------
    -- Schema Name Validation
    ---------------------------------------------------------------------------
    CONSTRAINT chk_dataset_tables_schema
        CHECK (length(trim(table_schema)) > 0),

    ---------------------------------------------------------------------------
    -- Table Type Validation
    ---------------------------------------------------------------------------
    CONSTRAINT chk_dataset_tables_type
        CHECK
        (
            table_type IN
            (
                'BASE_TABLE',
                'VIEW',
                'MATERIALIZED_VIEW',
                'EXTERNAL_TABLE',
                'TEMPORARY_TABLE'
            )
        ),

    ---------------------------------------------------------------------------
    -- Status Validation
    ---------------------------------------------------------------------------
    CONSTRAINT chk_dataset_tables_status
        CHECK
        (
            table_status IN
            (
                'ACTIVE',
                'ARCHIVED',
                'FAILED'
            )
        )
);

-- ============================================================================
-- INDEXES
-- ============================================================================

CREATE INDEX IF NOT EXISTS idx_dataset_tables_dataset
ON structured.dataset_tables(dataset_id);

CREATE INDEX IF NOT EXISTS idx_dataset_tables_name
ON structured.dataset_tables(table_name);

CREATE INDEX IF NOT EXISTS idx_dataset_tables_schema
ON structured.dataset_tables(table_schema);

CREATE INDEX IF NOT EXISTS idx_dataset_tables_type
ON structured.dataset_tables(table_type);

CREATE INDEX IF NOT EXISTS idx_dataset_tables_status
ON structured.dataset_tables(table_status);

CREATE INDEX IF NOT EXISTS idx_dataset_tables_last_synced
ON structured.dataset_tables(last_synced_at);

-- ============================================================================
-- TRIGGER
-- ============================================================================

DROP TRIGGER IF EXISTS trg_dataset_tables_set_updated_at ON structured.dataset_tables;

CREATE TRIGGER trg_dataset_tables_set_updated_at
BEFORE UPDATE
ON structured.dataset_tables
FOR EACH ROW
EXECUTE FUNCTION common.set_updated_at();

-- ============================================================================
-- COMMENTS
-- ============================================================================

COMMENT ON TABLE structured.dataset_tables IS
'Stores metadata for physical tables and views within structured datasets.';

COMMENT ON COLUMN structured.dataset_tables.table_id IS
'Unique identifier for the structured table metadata record.';

COMMENT ON COLUMN structured.dataset_tables.dataset_id IS
'Reference to the parent dataset.';

COMMENT ON COLUMN structured.dataset_tables.table_name IS
'Physical table or view name in the source system.';

COMMENT ON COLUMN structured.dataset_tables.display_name IS
'Human-friendly display name used in the UI.';

COMMENT ON COLUMN structured.dataset_tables.table_schema IS
'Schema or namespace containing the table.';

COMMENT ON COLUMN structured.dataset_tables.description IS
'Business description of the table.';

COMMENT ON COLUMN structured.dataset_tables.table_type IS
'Type of object represented by this metadata record.';

COMMENT ON COLUMN structured.dataset_tables.storage_engine IS
'Storage engine used by the source database where applicable.';

COMMENT ON COLUMN structured.dataset_tables.table_status IS
'Operational status of the table metadata.';

COMMENT ON COLUMN structured.dataset_tables.last_synced_at IS
'Timestamp of the last successful metadata synchronization.';

COMMENT ON COLUMN structured.dataset_tables.created_at IS
'Timestamp when the metadata record was created.';

COMMENT ON COLUMN structured.dataset_tables.updated_at IS
'Timestamp when the metadata record was last modified.';






/*
===============================================================================
TABLE: structured.dataset_columns

DESCRIPTION
-----------
Stores metadata describing every column belonging to a structured table.

One row represents exactly one column.

This table is optimized for:

• Metadata Catalog
• Text-to-SQL
• Schema Discovery
• Semantic Search
• Agentic Query Planning

Business data is NEVER stored here.
===============================================================================
*/

CREATE TABLE IF NOT EXISTS structured.dataset_columns
(
    ---------------------------------------------------------------------------
    -- Primary Key
    ---------------------------------------------------------------------------
    column_id UUID
        PRIMARY KEY
        DEFAULT gen_random_uuid(),

    ---------------------------------------------------------------------------
    -- Parent Table
    ---------------------------------------------------------------------------
    table_id UUID
        NOT NULL,

    ---------------------------------------------------------------------------
    -- Column Identity
    ---------------------------------------------------------------------------
    column_name VARCHAR(255)
        NOT NULL,

    column_display_name VARCHAR(255),

    description TEXT,

    ordinal_position INTEGER
        NOT NULL,

    ---------------------------------------------------------------------------
    -- Data Types
    ---------------------------------------------------------------------------
    logical_data_type VARCHAR(50)
        NOT NULL,

    physical_data_type VARCHAR(128)
        NOT NULL,

    character_maximum_length INTEGER,

    numeric_precision INTEGER,

    numeric_scale INTEGER,

    datetime_precision INTEGER,

    ---------------------------------------------------------------------------
    -- Constraints
    ---------------------------------------------------------------------------
    is_nullable BOOLEAN
        NOT NULL DEFAULT TRUE,

    is_primary_key BOOLEAN
        NOT NULL DEFAULT FALSE,

    is_foreign_key BOOLEAN
        NOT NULL DEFAULT FALSE,

    is_unique BOOLEAN
        NOT NULL DEFAULT FALSE,

    is_indexed BOOLEAN
        NOT NULL DEFAULT FALSE,

    column_default TEXT,

    ---------------------------------------------------------------------------
    -- Semantic Metadata
    ---------------------------------------------------------------------------
    semantic_role VARCHAR(50),

    sample_value TEXT,

    is_searchable BOOLEAN
        NOT NULL DEFAULT TRUE,

    is_filterable BOOLEAN
        NOT NULL DEFAULT TRUE,

    is_sortable BOOLEAN
        NOT NULL DEFAULT TRUE,

    ---------------------------------------------------------------------------
    -- Operational Metadata
    ---------------------------------------------------------------------------
    column_status VARCHAR(20)
        NOT NULL DEFAULT 'ACTIVE',

    last_synced_at TIMESTAMPTZ,

    ---------------------------------------------------------------------------
    -- Audit
    ---------------------------------------------------------------------------
    created_at TIMESTAMPTZ
        NOT NULL DEFAULT CURRENT_TIMESTAMP,

    updated_at TIMESTAMPTZ
        NOT NULL DEFAULT CURRENT_TIMESTAMP,

    ---------------------------------------------------------------------------
    -- Foreign Key
    ---------------------------------------------------------------------------
    CONSTRAINT fk_dataset_columns_table
        FOREIGN KEY (table_id)
        REFERENCES structured.dataset_tables(table_id)
        ON DELETE CASCADE,

    ---------------------------------------------------------------------------
    -- Unique Constraint
    ---------------------------------------------------------------------------
    CONSTRAINT uq_dataset_columns_table_name
        UNIQUE
        (
            table_id,
            column_name
        ),

    ---------------------------------------------------------------------------
    -- Validation
    ---------------------------------------------------------------------------
    CONSTRAINT chk_dataset_columns_name
        CHECK (length(trim(column_name)) > 0),

    CONSTRAINT chk_dataset_columns_position
        CHECK (ordinal_position > 0),

    CONSTRAINT chk_dataset_columns_character_length
        CHECK (
            character_maximum_length IS NULL
            OR character_maximum_length > 0
        ),

    CONSTRAINT chk_dataset_columns_numeric_precision
        CHECK (
            numeric_precision IS NULL
            OR numeric_precision >= 0
        ),

    CONSTRAINT chk_dataset_columns_numeric_scale
        CHECK (
            numeric_scale IS NULL
            OR numeric_scale >= 0
        ),

    CONSTRAINT chk_dataset_columns_datetime_precision
        CHECK (
            datetime_precision IS NULL
            OR datetime_precision >= 0
        ),

    CONSTRAINT chk_dataset_columns_status
        CHECK (
            column_status IN
            (
                'ACTIVE',
                'ARCHIVED',
                'FAILED'
            )
        ),

    CONSTRAINT chk_dataset_columns_logical_type
        CHECK (
            logical_data_type IN
            (
                'STRING',
                'INTEGER',
                'DECIMAL',
                'BOOLEAN',
                'DATE',
                'TIME',
                'DATETIME',
                'JSON',
                'ARRAY',
                'BINARY',
                'UUID',
                'OTHER'
            )
        ),

    CONSTRAINT chk_dataset_columns_semantic_role
        CHECK (
            semantic_role IS NULL
            OR semantic_role IN
            (
                'IDENTIFIER',
                'DIMENSION',
                'MEASURE',
                'DATE',
                'TIME',
                'DATETIME',
                'EMAIL',
                'PHONE',
                'LOCATION',
                'NAME',
                'URL',
                'JSON',
                'TEXT',
                'BOOLEAN_FLAG',
                'OTHER'
            )
        )
);

-- ============================================================================
-- INDEXES
-- ============================================================================

CREATE INDEX IF NOT EXISTS idx_dataset_columns_table
ON structured.dataset_columns(table_id);

CREATE INDEX IF NOT EXISTS idx_dataset_columns_name
ON structured.dataset_columns(column_name);

CREATE INDEX IF NOT EXISTS idx_dataset_columns_logical_type
ON structured.dataset_columns(logical_data_type);

CREATE INDEX IF NOT EXISTS idx_dataset_columns_semantic_role
ON structured.dataset_columns(semantic_role);

CREATE INDEX IF NOT EXISTS idx_dataset_columns_primary_key
ON structured.dataset_columns(is_primary_key)
WHERE is_primary_key = TRUE;

CREATE INDEX IF NOT EXISTS idx_dataset_columns_foreign_key
ON structured.dataset_columns(is_foreign_key)
WHERE is_foreign_key = TRUE;

CREATE INDEX IF NOT EXISTS idx_dataset_columns_indexed
ON structured.dataset_columns(is_indexed)
WHERE is_indexed = TRUE;

CREATE INDEX IF NOT EXISTS idx_dataset_columns_last_synced
ON structured.dataset_columns(last_synced_at);

-- ============================================================================
-- TRIGGER
-- ============================================================================

DROP TRIGGER IF EXISTS trg_dataset_columns_set_updated_at ON structured.dataset_columns;

CREATE TRIGGER trg_dataset_columns_set_updated_at
BEFORE UPDATE
ON structured.dataset_columns
FOR EACH ROW
EXECUTE FUNCTION common.set_updated_at();





/*
===============================================================================
TABLE: structured.dataset_relationships

PURPOSE:
    Stores metadata describing logical relationships between structured tables.

DESCRIPTION:
    One row represents one relationship between two structured tables.
    This table stores relationship-level metadata only.

    Column mappings for simple or composite relationships are stored in:
        structured.dataset_relationship_columns

    Used by:
      - Text-to-SQL Agent
      - Query Planner
      - Schema Discovery
      - Metadata Catalog
      - Data Lineage
      - Semantic Query Engine

===============================================================================
*/

CREATE TABLE IF NOT EXISTS structured.dataset_relationships
(
    ---------------------------------------------------------------------------
    -- Primary Key
    ---------------------------------------------------------------------------
    relationship_id UUID
        PRIMARY KEY
        DEFAULT gen_random_uuid(),

    ---------------------------------------------------------------------------
    -- Source / Target Tables
    ---------------------------------------------------------------------------
    source_table_id UUID
        NOT NULL,

    target_table_id UUID
        NOT NULL,

    ---------------------------------------------------------------------------
    -- Relationship Identity
    ---------------------------------------------------------------------------
    relationship_name VARCHAR(255)
        NOT NULL,

    constraint_name VARCHAR(255),

    description TEXT,

    ---------------------------------------------------------------------------
    -- Relationship Classification
    ---------------------------------------------------------------------------
    relationship_type VARCHAR(30)
        NOT NULL
        DEFAULT 'FOREIGN_KEY',

    cardinality VARCHAR(20)
        NOT NULL,

    ---------------------------------------------------------------------------
    -- Referential Actions
    ---------------------------------------------------------------------------
    on_update_action VARCHAR(20)
        NOT NULL
        DEFAULT 'NO_ACTION',

    on_delete_action VARCHAR(20)
        NOT NULL
        DEFAULT 'NO_ACTION',

    ---------------------------------------------------------------------------
    -- Discovery Metadata
    ---------------------------------------------------------------------------
    discovery_method VARCHAR(20)
        NOT NULL
        DEFAULT 'CATALOG',

    confidence_score NUMERIC(5,4)
        NOT NULL
        DEFAULT 1.0000,

    is_verified BOOLEAN
        NOT NULL
        DEFAULT FALSE,

    last_verified_at TIMESTAMPTZ,

    ---------------------------------------------------------------------------
    -- Operational Metadata
    ---------------------------------------------------------------------------
    relationship_status VARCHAR(20)
        NOT NULL
        DEFAULT 'ACTIVE',

    ---------------------------------------------------------------------------
    -- Audit Columns
    ---------------------------------------------------------------------------
    created_at TIMESTAMPTZ
        NOT NULL
        DEFAULT CURRENT_TIMESTAMP,

    updated_at TIMESTAMPTZ
        NOT NULL
        DEFAULT CURRENT_TIMESTAMP,

    ---------------------------------------------------------------------------
    -- Foreign Keys
    ---------------------------------------------------------------------------
    CONSTRAINT fk_dataset_relationships_source_table
        FOREIGN KEY (source_table_id)
        REFERENCES structured.dataset_tables(table_id)
        ON DELETE CASCADE
        ON UPDATE CASCADE,

    CONSTRAINT fk_dataset_relationships_target_table
        FOREIGN KEY (target_table_id)
        REFERENCES structured.dataset_tables(table_id)
        ON DELETE CASCADE
        ON UPDATE CASCADE,

    ---------------------------------------------------------------------------
    -- Unique Constraint
    ---------------------------------------------------------------------------
    CONSTRAINT uq_dataset_relationships_name
        UNIQUE
        (
            source_table_id,
            target_table_id,
            relationship_name
        ),

    ---------------------------------------------------------------------------
    -- Validation Constraints
    ---------------------------------------------------------------------------
    CONSTRAINT chk_dataset_relationships_not_self
        CHECK (source_table_id <> target_table_id),

    CONSTRAINT chk_dataset_relationships_name
        CHECK (length(trim(relationship_name)) > 0),

    CONSTRAINT chk_dataset_relationships_type
        CHECK
        (
            relationship_type IN
            (
                'FOREIGN_KEY',
                'LOGICAL',
                'SEMANTIC',
                'INFERRED',
                'MANUAL'
            )
        ),

    CONSTRAINT chk_dataset_relationships_cardinality
        CHECK
        (
            cardinality IN
            (
                'ONE_TO_ONE',
                'ONE_TO_MANY',
                'MANY_TO_ONE',
                'MANY_TO_MANY'
            )
        ),

    CONSTRAINT chk_dataset_relationships_update_action
        CHECK
        (
            on_update_action IN
            (
                'CASCADE',
                'RESTRICT',
                'SET_NULL',
                'SET_DEFAULT',
                'NO_ACTION'
            )
        ),

    CONSTRAINT chk_dataset_relationships_delete_action
        CHECK
        (
            on_delete_action IN
            (
                'CASCADE',
                'RESTRICT',
                'SET_NULL',
                'SET_DEFAULT',
                'NO_ACTION'
            )
        ),

    CONSTRAINT chk_dataset_relationships_discovery
        CHECK
        (
            discovery_method IN
            (
                'SYSTEM',
                'CATALOG',
                'MANUAL',
                'LLM',
                'INFERRED'
            )
        ),

    CONSTRAINT chk_dataset_relationships_confidence
        CHECK
        (
            confidence_score >= 0.0000
            AND confidence_score <= 1.0000
        ),

    CONSTRAINT chk_dataset_relationships_status
        CHECK
        (
            relationship_status IN
            (
                'ACTIVE',
                'ARCHIVED',
                'FAILED'
            )
        )
);

-- ============================================================================
-- INDEXES
-- ============================================================================

CREATE INDEX IF NOT EXISTS idx_dataset_relationships_source_table
ON structured.dataset_relationships(source_table_id);

CREATE INDEX IF NOT EXISTS idx_dataset_relationships_target_table
ON structured.dataset_relationships(target_table_id);

CREATE INDEX IF NOT EXISTS idx_dataset_relationships_type
ON structured.dataset_relationships(relationship_type);

CREATE INDEX IF NOT EXISTS idx_dataset_relationships_cardinality
ON structured.dataset_relationships(cardinality);

CREATE INDEX IF NOT EXISTS idx_dataset_relationships_discovery
ON structured.dataset_relationships(discovery_method);

CREATE INDEX IF NOT EXISTS idx_dataset_relationships_status
ON structured.dataset_relationships(relationship_status);

CREATE INDEX IF NOT EXISTS idx_dataset_relationships_verified
ON structured.dataset_relationships(is_verified)
WHERE is_verified = TRUE;

CREATE INDEX IF NOT EXISTS idx_dataset_relationships_last_verified
ON structured.dataset_relationships(last_verified_at);

CREATE INDEX IF NOT EXISTS idx_dataset_relationships_confidence
ON structured.dataset_relationships(confidence_score);

-- ============================================================================
-- UPDATED_AT TRIGGER
-- ============================================================================

DROP TRIGGER IF EXISTS trg_dataset_relationships_set_updated_at ON structured.dataset_relationships;

CREATE TRIGGER trg_dataset_relationships_set_updated_at
BEFORE UPDATE
ON structured.dataset_relationships
FOR EACH ROW
EXECUTE FUNCTION common.set_updated_at();

-- ============================================================================
-- TABLE COMMENT
-- ============================================================================

COMMENT ON TABLE structured.dataset_relationships IS
'Stores metadata describing logical relationships between structured tables. Column mappings are maintained separately in structured.dataset_relationship_columns.';

-- ============================================================================
-- COLUMN COMMENTS
-- ============================================================================

COMMENT ON COLUMN structured.dataset_relationships.relationship_id IS
'Unique identifier for the relationship metadata record.';

COMMENT ON COLUMN structured.dataset_relationships.source_table_id IS
'Identifier of the source (referencing) table.';

COMMENT ON COLUMN structured.dataset_relationships.target_table_id IS
'Identifier of the target (referenced) table.';

COMMENT ON COLUMN structured.dataset_relationships.relationship_name IS
'Human-readable name of the relationship.';

COMMENT ON COLUMN structured.dataset_relationships.constraint_name IS
'Original constraint name in the source database if available.';

COMMENT ON COLUMN structured.dataset_relationships.description IS
'Business description of the relationship.';

COMMENT ON COLUMN structured.dataset_relationships.relationship_type IS
'Classification of the relationship.';

COMMENT ON COLUMN structured.dataset_relationships.cardinality IS
'Logical cardinality between the source and target tables.';

COMMENT ON COLUMN structured.dataset_relationships.on_update_action IS
'Referential action executed when the referenced key is updated.';

COMMENT ON COLUMN structured.dataset_relationships.on_delete_action IS
'Referential action executed when the referenced key is deleted.';

COMMENT ON COLUMN structured.dataset_relationships.discovery_method IS
'Method by which the relationship was discovered or created.';

COMMENT ON COLUMN structured.dataset_relationships.confidence_score IS
'Confidence score for inferred or AI-generated relationships.';

COMMENT ON COLUMN structured.dataset_relationships.is_verified IS
'Indicates whether the relationship has been validated against the source system.';

COMMENT ON COLUMN structured.dataset_relationships.last_verified_at IS
'Timestamp of the most recent relationship verification.';

COMMENT ON COLUMN structured.dataset_relationships.relationship_status IS
'Operational status of the relationship metadata.';

COMMENT ON COLUMN structured.dataset_relationships.created_at IS
'Timestamp when the relationship metadata was created.';

COMMENT ON COLUMN structured.dataset_relationships.updated_at IS
'Timestamp when the relationship metadata was last updated.';





/*
===============================================================================
FUNCTION: common.validate_relationship_column_mapping()

PURPOSE:
    Validates relationship column mappings before INSERT or UPDATE.

DESCRIPTION:
    Ensures:

    1. Source column belongs to the relationship's source table.
    2. Target column belongs to the relationship's target table.
    3. Source and target columns are not identical.
    4. Prevents invalid relationship metadata from entering the catalog.

RETURNS:
    TRIGGER

===============================================================================
*/

CREATE OR REPLACE FUNCTION common.validate_relationship_column_mapping()
RETURNS TRIGGER
LANGUAGE plpgsql
AS
$$
DECLARE
    v_source_table UUID;
    v_target_table UUID;

    v_source_column_table UUID;
    v_target_column_table UUID;
BEGIN

    ---------------------------------------------------------------------------
    -- Source / Target tables defined by the relationship
    ---------------------------------------------------------------------------
    SELECT
        source_table_id,
        target_table_id
    INTO
        v_source_table,
        v_target_table
    FROM structured.dataset_relationships
    WHERE relationship_id = NEW.relationship_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION
            'Relationship % does not exist.',
            NEW.relationship_id;
    END IF;

    ---------------------------------------------------------------------------
    -- Source column must exist
    ---------------------------------------------------------------------------
    SELECT table_id
    INTO v_source_column_table
    FROM structured.dataset_columns
    WHERE column_id = NEW.source_column_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION
            'Source column % does not exist.',
            NEW.source_column_id;
    END IF;

    ---------------------------------------------------------------------------
    -- Target column must exist
    ---------------------------------------------------------------------------
    SELECT table_id
    INTO v_target_column_table
    FROM structured.dataset_columns
    WHERE column_id = NEW.target_column_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION
            'Target column % does not exist.',
            NEW.target_column_id;
    END IF;

    ---------------------------------------------------------------------------
    -- Validate source column ownership
    ---------------------------------------------------------------------------
    IF v_source_column_table <> v_source_table THEN

        RAISE EXCEPTION
        'Source column % does not belong to source table %.',
        NEW.source_column_id,
        v_source_table;

    END IF;

    ---------------------------------------------------------------------------
    -- Validate target column ownership
    ---------------------------------------------------------------------------
    IF v_target_column_table <> v_target_table THEN

        RAISE EXCEPTION
        'Target column % does not belong to target table %.',
        NEW.target_column_id,
        v_target_table;

    END IF;

    ---------------------------------------------------------------------------
    -- Prevent self mapping
    ---------------------------------------------------------------------------
    IF NEW.source_column_id = NEW.target_column_id THEN

        RAISE EXCEPTION
        'Source and target columns cannot be identical.';

    END IF;

    RETURN NEW;

END;
$$;

COMMENT ON FUNCTION common.validate_relationship_column_mapping() IS
'Validates that relationship column mappings reference columns belonging to the correct source and target tables before insert or update.';





/*
===============================================================================
TABLE: structured.dataset_relationship_columns

PURPOSE:
    Stores column-level mappings for relationships between structured tables.

DESCRIPTION:
    One row represents one source-to-target column mapping belonging to a
    relationship.

    Supports:
        • Single-column foreign keys
        • Composite foreign keys
        • Ordered column mappings
        • Text-to-SQL join generation
        • Schema discovery
        • Metadata catalog

    Relationship-level metadata is stored in:

        structured.dataset_relationships

===============================================================================
*/

CREATE TABLE IF NOT EXISTS structured.dataset_relationship_columns
(
    ---------------------------------------------------------------------------
    -- Primary Key
    ---------------------------------------------------------------------------
    relationship_column_id UUID
        PRIMARY KEY
        DEFAULT gen_random_uuid(),

    ---------------------------------------------------------------------------
    -- Parent Relationship
    ---------------------------------------------------------------------------
    relationship_id UUID
        NOT NULL,

    ---------------------------------------------------------------------------
    -- Source Column
    ---------------------------------------------------------------------------
    source_column_id UUID
        NOT NULL,

    ---------------------------------------------------------------------------
    -- Target Column
    ---------------------------------------------------------------------------
    target_column_id UUID
        NOT NULL,

    ---------------------------------------------------------------------------
    -- Composite Foreign Key Ordering
    ---------------------------------------------------------------------------
    column_sequence SMALLINT
        NOT NULL,

    ---------------------------------------------------------------------------
    -- Audit Columns
    ---------------------------------------------------------------------------
    created_at TIMESTAMPTZ
        NOT NULL
        DEFAULT CURRENT_TIMESTAMP,

    updated_at TIMESTAMPTZ
        NOT NULL
        DEFAULT CURRENT_TIMESTAMP,

    ---------------------------------------------------------------------------
    -- Foreign Keys
    ---------------------------------------------------------------------------
    CONSTRAINT fk_relationship_columns_relationship
        FOREIGN KEY (relationship_id)
        REFERENCES structured.dataset_relationships(relationship_id)
        ON DELETE CASCADE
        ON UPDATE CASCADE,

    CONSTRAINT fk_relationship_columns_source_column
        FOREIGN KEY (source_column_id)
        REFERENCES structured.dataset_columns(column_id)
        ON DELETE RESTRICT
        ON UPDATE CASCADE,

    CONSTRAINT fk_relationship_columns_target_column
        FOREIGN KEY (target_column_id)
        REFERENCES structured.dataset_columns(column_id)
        ON DELETE RESTRICT
        ON UPDATE CASCADE,

    ---------------------------------------------------------------------------
    -- Unique Constraints
    ---------------------------------------------------------------------------
    CONSTRAINT uq_relationship_columns_sequence
        UNIQUE
        (
            relationship_id,
            column_sequence
        ),

    CONSTRAINT uq_relationship_columns_mapping
        UNIQUE
        (
            relationship_id,
            source_column_id,
            target_column_id
        ),

    ---------------------------------------------------------------------------
    -- Validation Constraints
    ---------------------------------------------------------------------------
    CONSTRAINT chk_relationship_columns_sequence
        CHECK (column_sequence > 0),

    CONSTRAINT chk_relationship_columns_not_self
        CHECK (source_column_id <> target_column_id)
);

-- ============================================================================
-- INDEXES
-- ============================================================================

CREATE INDEX IF NOT EXISTS idx_relationship_columns_relationship
ON structured.dataset_relationship_columns
(
    relationship_id
);

CREATE INDEX IF NOT EXISTS idx_relationship_columns_source_column
ON structured.dataset_relationship_columns
(
    source_column_id
);

CREATE INDEX IF NOT EXISTS idx_relationship_columns_target_column
ON structured.dataset_relationship_columns
(
    target_column_id
);

CREATE INDEX IF NOT EXISTS idx_relationship_columns_sequence
ON structured.dataset_relationship_columns
(
    relationship_id,
    column_sequence
);

-- ============================================================================
-- VALIDATION TRIGGER
-- ============================================================================

DROP TRIGGER IF EXISTS trg_relationship_columns_validate ON structured.dataset_relationship_columns;

CREATE TRIGGER trg_relationship_columns_validate
BEFORE INSERT OR UPDATE
ON structured.dataset_relationship_columns
FOR EACH ROW
EXECUTE FUNCTION common.validate_relationship_column_mapping();

-- ============================================================================
-- UPDATED_AT TRIGGER
-- ============================================================================

DROP TRIGGER IF EXISTS trg_relationship_columns_set_updated_at ON structured.dataset_relationship_columns;

CREATE TRIGGER trg_relationship_columns_set_updated_at
BEFORE UPDATE
ON structured.dataset_relationship_columns
FOR EACH ROW
EXECUTE FUNCTION common.set_updated_at();

-- ============================================================================
-- TABLE COMMENT
-- ============================================================================

COMMENT ON TABLE structured.dataset_relationship_columns IS
'Stores source-to-target column mappings for relationships between structured tables. Supports both single-column and composite foreign keys.';

-- ============================================================================
-- COLUMN COMMENTS
-- ============================================================================

COMMENT ON COLUMN structured.dataset_relationship_columns.relationship_column_id IS
'Unique identifier for the relationship column mapping.';

COMMENT ON COLUMN structured.dataset_relationship_columns.relationship_id IS
'Reference to the parent relationship metadata record.';

COMMENT ON COLUMN structured.dataset_relationship_columns.source_column_id IS
'Source (referencing) column participating in the relationship.';

COMMENT ON COLUMN structured.dataset_relationship_columns.target_column_id IS
'Target (referenced) column participating in the relationship.';

COMMENT ON COLUMN structured.dataset_relationship_columns.column_sequence IS
'Defines the ordinal position of the column mapping within a composite relationship.';

COMMENT ON COLUMN structured.dataset_relationship_columns.created_at IS
'Timestamp when the relationship column mapping was created.';

COMMENT ON COLUMN structured.dataset_relationship_columns.updated_at IS
'Timestamp when the relationship column mapping was last updated.';





/*
===============================================================================
TABLE: structured.dataset_statistics
SCHEMA: structured

PURPOSE:
    Stores dataset-level profiling statistics for datasets registered in
    OmniBrain.

DESCRIPTION:
    This table contains aggregated profiling statistics computed at the
    dataset level. These statistics support metadata discovery, governance,
    monitoring, analytics, and AI-assisted query planning.

    This table stores ONLY dataset-level statistics.

    Table-level statistics are maintained in:
        structured.table_statistics

    Column-level profiling statistics are maintained in:
        structured.column_statistics

NOTES:
    • One statistics record per dataset.
    • Statistics are periodically regenerated by profiling jobs.
    • Historical executions are tracked separately in
      structured.dataset_refresh_history.
    • Compatible with PostgreSQL 17+.

===============================================================================
*/

CREATE TABLE IF NOT EXISTS structured.dataset_statistics
(
    ---------------------------------------------------------------------------
    -- Primary Key
    ---------------------------------------------------------------------------
    statistics_id UUID
        PRIMARY KEY
        DEFAULT gen_random_uuid(),

    ---------------------------------------------------------------------------
    -- Dataset Reference
    ---------------------------------------------------------------------------
    dataset_id UUID
        NOT NULL,

    ---------------------------------------------------------------------------
    -- Dataset Profiling Statistics
    ---------------------------------------------------------------------------
    row_count BIGINT
        NOT NULL
        DEFAULT 0,

    table_count INTEGER
        NOT NULL
        DEFAULT 0,

    view_count INTEGER
        NOT NULL
        DEFAULT 0,

    materialized_view_count INTEGER
        NOT NULL
        DEFAULT 0,

    total_storage_bytes BIGINT
        NOT NULL
        DEFAULT 0,

    largest_table_size_bytes BIGINT
        NOT NULL
        DEFAULT 0,

    statistics_generated_at TIMESTAMPTZ
        NOT NULL
        DEFAULT CURRENT_TIMESTAMP,

    ---------------------------------------------------------------------------
    -- Audit Columns
    ---------------------------------------------------------------------------
    created_at TIMESTAMPTZ
        NOT NULL
        DEFAULT CURRENT_TIMESTAMP,

    updated_at TIMESTAMPTZ
        NOT NULL
        DEFAULT CURRENT_TIMESTAMP,

    ---------------------------------------------------------------------------
    -- Foreign Key
    ---------------------------------------------------------------------------
    CONSTRAINT fk_dataset_statistics_dataset
        FOREIGN KEY (dataset_id)
        REFERENCES structured.datasets(dataset_id)
        ON UPDATE CASCADE
        ON DELETE CASCADE,

    ---------------------------------------------------------------------------
    -- One Statistics Record Per Dataset
    ---------------------------------------------------------------------------
    CONSTRAINT uq_dataset_statistics_dataset
        UNIQUE (dataset_id),

    ---------------------------------------------------------------------------
    -- Validation Constraints
    ---------------------------------------------------------------------------
    CONSTRAINT chk_dataset_statistics_row_count
        CHECK (row_count >= 0),

    CONSTRAINT chk_dataset_statistics_table_count
        CHECK (table_count >= 0),

    CONSTRAINT chk_dataset_statistics_view_count
        CHECK (view_count >= 0),

    CONSTRAINT chk_dataset_statistics_materialized_view_count
        CHECK (materialized_view_count >= 0),

    CONSTRAINT chk_dataset_statistics_total_storage
        CHECK (total_storage_bytes >= 0),

    CONSTRAINT chk_dataset_statistics_largest_table
        CHECK (largest_table_size_bytes >= 0)
);

-- ============================================================================
-- INDEXES
-- ============================================================================

CREATE INDEX IF NOT EXISTS idx_dataset_statistics_dataset
ON structured.dataset_statistics
(
    dataset_id
);

CREATE INDEX IF NOT EXISTS idx_dataset_statistics_generated_at
ON structured.dataset_statistics
(
    statistics_generated_at DESC
);

CREATE INDEX IF NOT EXISTS idx_dataset_statistics_row_count
ON structured.dataset_statistics
(
    row_count DESC
);

CREATE INDEX IF NOT EXISTS idx_dataset_statistics_storage
ON structured.dataset_statistics
(
    total_storage_bytes DESC
);

-- ============================================================================
-- TRIGGER
-- ============================================================================

DROP TRIGGER IF EXISTS trg_dataset_statistics_set_updated_at ON structured.dataset_statistics;

CREATE TRIGGER trg_dataset_statistics_set_updated_at
BEFORE UPDATE
ON structured.dataset_statistics
FOR EACH ROW
EXECUTE FUNCTION common.set_updated_at();

-- ============================================================================
-- TABLE COMMENT
-- ============================================================================

COMMENT ON TABLE structured.dataset_statistics IS
'Stores aggregated dataset-level profiling statistics for datasets managed by OmniBrain.';

-- ============================================================================
-- COLUMN COMMENTS
-- ============================================================================

COMMENT ON COLUMN structured.dataset_statistics.statistics_id IS
'Unique identifier for the dataset statistics record.';

COMMENT ON COLUMN structured.dataset_statistics.dataset_id IS
'Reference to the dataset whose profiling statistics are stored.';

COMMENT ON COLUMN structured.dataset_statistics.row_count IS
'Total number of rows across all tables belonging to the dataset.';

COMMENT ON COLUMN structured.dataset_statistics.table_count IS
'Total number of user tables within the dataset.';

COMMENT ON COLUMN structured.dataset_statistics.view_count IS
'Total number of logical views within the dataset.';

COMMENT ON COLUMN structured.dataset_statistics.materialized_view_count IS
'Total number of materialized views within the dataset.';

COMMENT ON COLUMN structured.dataset_statistics.total_storage_bytes IS
'Total storage consumed by all objects in the dataset, expressed in bytes.';

COMMENT ON COLUMN structured.dataset_statistics.largest_table_size_bytes IS
'Storage size in bytes of the largest table within the dataset.';

COMMENT ON COLUMN structured.dataset_statistics.statistics_generated_at IS
'Timestamp when the dataset profiling statistics were last generated.';

COMMENT ON COLUMN structured.dataset_statistics.created_at IS
'Timestamp when this statistics record was created.';

COMMENT ON COLUMN structured.dataset_statistics.updated_at IS
'Timestamp when this statistics record was last updated.';






/*
===============================================================================
TABLE: structured.table_statistics
SCHEMA: structured

PURPOSE:
    Stores table-level profiling and storage statistics for structured tables
    registered in OmniBrain.

DESCRIPTION:
    This table contains aggregated statistics for individual tables within
    a dataset. The statistics support metadata discovery, governance,
    storage monitoring, query optimization, and AI-assisted schema analysis.

    This table stores ONLY table-level statistics.

    Dataset-level statistics are maintained in:
        structured.dataset_statistics

    Column-level profiling statistics are maintained in:
        structured.column_statistics

NOTES:
    • One statistics record per table.
    • Statistics are periodically regenerated.
    • Historical refresh executions are tracked separately.
    • Compatible with PostgreSQL 17+.

===============================================================================
*/

CREATE TABLE IF NOT EXISTS structured.table_statistics
(
    ---------------------------------------------------------------------------
    -- Primary Key
    ---------------------------------------------------------------------------
    table_statistics_id UUID
        PRIMARY KEY
        DEFAULT gen_random_uuid(),

    ---------------------------------------------------------------------------
    -- Table Reference
    ---------------------------------------------------------------------------
    table_id UUID
        NOT NULL,

    ---------------------------------------------------------------------------
    -- Row Statistics
    ---------------------------------------------------------------------------
    row_count BIGINT
        NOT NULL
        DEFAULT 0,

    live_row_count BIGINT
        NOT NULL
        DEFAULT 0,

    dead_row_count BIGINT
        NOT NULL
        DEFAULT 0,

    ---------------------------------------------------------------------------
    -- Structural Statistics
    ---------------------------------------------------------------------------
    column_count INTEGER
        NOT NULL
        DEFAULT 0,

    primary_key_count INTEGER
        NOT NULL
        DEFAULT 0,

    foreign_key_count INTEGER
        NOT NULL
        DEFAULT 0,

    unique_constraint_count INTEGER
        NOT NULL
        DEFAULT 0,

    check_constraint_count INTEGER
        NOT NULL
        DEFAULT 0,

    index_count INTEGER
        NOT NULL
        DEFAULT 0,

    ---------------------------------------------------------------------------
    -- Storage Statistics
    ---------------------------------------------------------------------------
    table_size_bytes BIGINT
        NOT NULL
        DEFAULT 0,

    index_size_bytes BIGINT
        NOT NULL
        DEFAULT 0,

    toast_size_bytes BIGINT
        NOT NULL
        DEFAULT 0,

    total_size_bytes BIGINT
        NOT NULL
        DEFAULT 0,

    ---------------------------------------------------------------------------
    -- Profiling Metadata
    ---------------------------------------------------------------------------
    statistics_generated_at TIMESTAMPTZ
        NOT NULL
        DEFAULT CURRENT_TIMESTAMP,

    ---------------------------------------------------------------------------
    -- Audit Columns
    ---------------------------------------------------------------------------
    created_at TIMESTAMPTZ
        NOT NULL
        DEFAULT CURRENT_TIMESTAMP,

    updated_at TIMESTAMPTZ
        NOT NULL
        DEFAULT CURRENT_TIMESTAMP,

    ---------------------------------------------------------------------------
    -- Foreign Key
    ---------------------------------------------------------------------------
    CONSTRAINT fk_table_statistics_table
        FOREIGN KEY (table_id)
        REFERENCES structured.dataset_tables(table_id)
        ON UPDATE CASCADE
        ON DELETE CASCADE,

    ---------------------------------------------------------------------------
    -- One Statistics Record Per Table
    ---------------------------------------------------------------------------
    CONSTRAINT uq_table_statistics_table
        UNIQUE (table_id),

    ---------------------------------------------------------------------------
    -- Validation Constraints
    ---------------------------------------------------------------------------
    CONSTRAINT chk_table_statistics_row_count
        CHECK (row_count >= 0),

    CONSTRAINT chk_table_statistics_live_row_count
        CHECK (live_row_count >= 0),

    CONSTRAINT chk_table_statistics_dead_row_count
        CHECK (dead_row_count >= 0),

    CONSTRAINT chk_table_statistics_column_count
        CHECK (column_count >= 0),

    CONSTRAINT chk_table_statistics_primary_key_count
        CHECK (primary_key_count >= 0),

    CONSTRAINT chk_table_statistics_foreign_key_count
        CHECK (foreign_key_count >= 0),

    CONSTRAINT chk_table_statistics_unique_constraint_count
        CHECK (unique_constraint_count >= 0),

    CONSTRAINT chk_table_statistics_check_constraint_count
        CHECK (check_constraint_count >= 0),

    CONSTRAINT chk_table_statistics_index_count
        CHECK (index_count >= 0),

    CONSTRAINT chk_table_statistics_table_size
        CHECK (table_size_bytes >= 0),

    CONSTRAINT chk_table_statistics_index_size
        CHECK (index_size_bytes >= 0),

    CONSTRAINT chk_table_statistics_toast_size
        CHECK (toast_size_bytes >= 0),

    CONSTRAINT chk_table_statistics_total_size
        CHECK (total_size_bytes >= 0),

    CONSTRAINT chk_table_statistics_live_dead_rows
        CHECK
        (
            row_count >= live_row_count
        ),

    CONSTRAINT chk_table_statistics_total_storage
        CHECK
        (
            total_size_bytes >= table_size_bytes
        ),

    CONSTRAINT chk_table_statistics_total_index_storage
        CHECK
        (
            total_size_bytes >= index_size_bytes
        ),

    CONSTRAINT chk_table_statistics_total_toast_storage
        CHECK
        (
            total_size_bytes >= toast_size_bytes
        )
);

-- ============================================================================
-- INDEXES
-- ============================================================================

CREATE INDEX IF NOT EXISTS idx_table_statistics_table
ON structured.table_statistics
(
    table_id
);

CREATE INDEX IF NOT EXISTS idx_table_statistics_generated_at
ON structured.table_statistics
(
    statistics_generated_at DESC
);

CREATE INDEX IF NOT EXISTS idx_table_statistics_row_count
ON structured.table_statistics
(
    row_count DESC
);

CREATE INDEX IF NOT EXISTS idx_table_statistics_total_size
ON structured.table_statistics
(
    total_size_bytes DESC
);

CREATE INDEX IF NOT EXISTS idx_table_statistics_table_size
ON structured.table_statistics
(
    table_size_bytes DESC
);

CREATE INDEX IF NOT EXISTS idx_table_statistics_index_size
ON structured.table_statistics
(
    index_size_bytes DESC
);

-- ============================================================================
-- UPDATED_AT TRIGGER
-- ============================================================================

DROP TRIGGER IF EXISTS trg_table_statistics_set_updated_at ON structured.table_statistics;

CREATE TRIGGER trg_table_statistics_set_updated_at
BEFORE UPDATE
ON structured.table_statistics
FOR EACH ROW
EXECUTE FUNCTION common.set_updated_at();

-- ============================================================================
-- TABLE COMMENT
-- ============================================================================

COMMENT ON TABLE structured.table_statistics IS
'Stores profiling, structural, and storage statistics for individual tables registered in OmniBrain.';

-- ============================================================================
-- COLUMN COMMENTS
-- ============================================================================

COMMENT ON COLUMN structured.table_statistics.table_statistics_id IS
'Unique identifier for the table statistics record.';

COMMENT ON COLUMN structured.table_statistics.table_id IS
'Reference to the table whose statistics are maintained.';

COMMENT ON COLUMN structured.table_statistics.row_count IS
'Estimated total number of rows in the table.';

COMMENT ON COLUMN structured.table_statistics.live_row_count IS
'Estimated number of live rows currently present in the table.';

COMMENT ON COLUMN structured.table_statistics.dead_row_count IS
'Estimated number of dead rows awaiting cleanup by VACUUM.';

COMMENT ON COLUMN structured.table_statistics.column_count IS
'Total number of columns defined for the table.';

COMMENT ON COLUMN structured.table_statistics.primary_key_count IS
'Number of primary key constraints defined on the table.';

COMMENT ON COLUMN structured.table_statistics.foreign_key_count IS
'Number of foreign key constraints defined on the table.';

COMMENT ON COLUMN structured.table_statistics.unique_constraint_count IS
'Number of unique constraints defined on the table.';

COMMENT ON COLUMN structured.table_statistics.check_constraint_count IS
'Number of CHECK constraints defined on the table.';

COMMENT ON COLUMN structured.table_statistics.index_count IS
'Total number of indexes associated with the table.';

COMMENT ON COLUMN structured.table_statistics.table_size_bytes IS
'Heap storage size of the table in bytes.';

COMMENT ON COLUMN structured.table_statistics.index_size_bytes IS
'Combined storage size of all indexes associated with the table in bytes.';

COMMENT ON COLUMN structured.table_statistics.toast_size_bytes IS
'Storage size of TOAST data associated with the table in bytes.';

COMMENT ON COLUMN structured.table_statistics.total_size_bytes IS
'Total storage consumed by the table, including heap, indexes, and TOAST data.';

COMMENT ON COLUMN structured.table_statistics.statistics_generated_at IS
'Timestamp when the profiling statistics were last generated.';

COMMENT ON COLUMN structured.table_statistics.created_at IS
'Timestamp when the statistics record was created.';

COMMENT ON COLUMN structured.table_statistics.updated_at IS
'Timestamp when the statistics record was last updated.';






/*
===============================================================================
TABLE: structured.column_statistics
SCHEMA: structured

PURPOSE:
    Stores profiling statistics for individual columns belonging to structured
    tables registered in OmniBrain.

DESCRIPTION:
    This table contains column-level profiling information generated during
    metadata analysis. The statistics support:

        • AI-assisted schema understanding
        • Text-to-SQL generation
        • Data profiling
        • Metadata exploration
        • Governance
        • Data quality analysis

    One statistics record is maintained per column.

RELATED TABLES:
    • structured.dataset_statistics
    • structured.table_statistics
    • structured.dataset_columns

NOTES:
    • Statistics are periodically regenerated.
    • Numeric metrics remain NULL for non-numeric columns.
    • Sample values are stored in JSONB.
    • Compatible with PostgreSQL 17+.

===============================================================================
*/

CREATE TABLE IF NOT EXISTS structured.column_statistics
(
    ---------------------------------------------------------------------------
    -- Primary Key
    ---------------------------------------------------------------------------
    statistics_id UUID
        PRIMARY KEY
        DEFAULT gen_random_uuid(),

    ---------------------------------------------------------------------------
    -- Column Reference
    ---------------------------------------------------------------------------
    column_id UUID
        NOT NULL,

    ---------------------------------------------------------------------------
    -- Cardinality Statistics
    ---------------------------------------------------------------------------
    distinct_value_count BIGINT
        NOT NULL
        DEFAULT 0,

    duplicate_value_count BIGINT
        NOT NULL
        DEFAULT 0,

    unique_value_percentage NUMERIC(5,2),

    ---------------------------------------------------------------------------
    -- NULL Statistics
    ---------------------------------------------------------------------------
    null_value_count BIGINT
        NOT NULL
        DEFAULT 0,

    null_percentage NUMERIC(5,2),

    ---------------------------------------------------------------------------
    -- Numeric Statistics
    ---------------------------------------------------------------------------
    minimum_value NUMERIC,

    maximum_value NUMERIC,

    average_value NUMERIC,

    median_value NUMERIC,

    standard_deviation NUMERIC,

    ---------------------------------------------------------------------------
    -- Text Statistics
    ---------------------------------------------------------------------------
    minimum_length INTEGER,

    maximum_length INTEGER,

    average_length NUMERIC,

    ---------------------------------------------------------------------------
    -- Sampling
    ---------------------------------------------------------------------------
    sample_values JSONB,

    ---------------------------------------------------------------------------
    -- Profiling Metadata
    ---------------------------------------------------------------------------
    statistics_generated_at TIMESTAMPTZ
        NOT NULL
        DEFAULT CURRENT_TIMESTAMP,

    ---------------------------------------------------------------------------
    -- Audit Columns
    ---------------------------------------------------------------------------
    created_at TIMESTAMPTZ
        NOT NULL
        DEFAULT CURRENT_TIMESTAMP,

    updated_at TIMESTAMPTZ
        NOT NULL
        DEFAULT CURRENT_TIMESTAMP,

    ---------------------------------------------------------------------------
    -- Foreign Key
    ---------------------------------------------------------------------------
    CONSTRAINT fk_column_statistics_column
        FOREIGN KEY (column_id)
        REFERENCES structured.dataset_columns(column_id)
        ON UPDATE CASCADE
        ON DELETE CASCADE,

    ---------------------------------------------------------------------------
    -- One Statistics Record Per Column
    ---------------------------------------------------------------------------
    CONSTRAINT uq_column_statistics_column
        UNIQUE (column_id),

    ---------------------------------------------------------------------------
    -- Validation Constraints
    ---------------------------------------------------------------------------
    CONSTRAINT chk_column_statistics_distinct_values
        CHECK (distinct_value_count >= 0),

    CONSTRAINT chk_column_statistics_duplicate_values
        CHECK (duplicate_value_count >= 0),

    CONSTRAINT chk_column_statistics_null_values
        CHECK (null_value_count >= 0),

    CONSTRAINT chk_column_statistics_unique_percentage
        CHECK
        (
            unique_value_percentage IS NULL
            OR
            (
                unique_value_percentage >= 0
                AND unique_value_percentage <= 100
            )
        ),

    CONSTRAINT chk_column_statistics_null_percentage
        CHECK
        (
            null_percentage IS NULL
            OR
            (
                null_percentage >= 0
                AND null_percentage <= 100
            )
        ),

    CONSTRAINT chk_column_statistics_minimum_length
        CHECK
        (
            minimum_length IS NULL
            OR minimum_length >= 0
        ),

    CONSTRAINT chk_column_statistics_maximum_length
        CHECK
        (
            maximum_length IS NULL
            OR maximum_length >= 0
        ),

    CONSTRAINT chk_column_statistics_average_length
        CHECK
        (
            average_length IS NULL
            OR average_length >= 0
        ),

    CONSTRAINT chk_column_statistics_length_order
        CHECK
        (
            minimum_length IS NULL
            OR maximum_length IS NULL
            OR minimum_length <= maximum_length
        ),

    CONSTRAINT chk_column_statistics_numeric_order
        CHECK
        (
            minimum_value IS NULL
            OR maximum_value IS NULL
            OR minimum_value <= maximum_value
        ),

    CONSTRAINT chk_column_statistics_standard_deviation
        CHECK
        (
            standard_deviation IS NULL
            OR standard_deviation >= 0
        )
);
-- ============================================================================
-- INDEXES
-- ============================================================================

CREATE INDEX IF NOT EXISTS idx_column_statistics_column
ON structured.column_statistics
(
    column_id
);

CREATE INDEX IF NOT EXISTS idx_column_statistics_generated_at
ON structured.column_statistics
(
    statistics_generated_at DESC
);

CREATE INDEX IF NOT EXISTS idx_column_statistics_distinct_values
ON structured.column_statistics
(
    distinct_value_count DESC
);

CREATE INDEX IF NOT EXISTS idx_column_statistics_null_percentage
ON structured.column_statistics
(
    null_percentage DESC
);

CREATE INDEX IF NOT EXISTS idx_column_statistics_unique_percentage
ON structured.column_statistics
(
    unique_value_percentage DESC
);

-- ============================================================================
-- UPDATED_AT TRIGGER
-- ============================================================================

DROP TRIGGER IF EXISTS trg_column_statistics_set_updated_at ON structured.column_statistics;

CREATE TRIGGER trg_column_statistics_set_updated_at
BEFORE UPDATE
ON structured.column_statistics
FOR EACH ROW
EXECUTE FUNCTION common.set_updated_at();

-- ============================================================================
-- TABLE COMMENT
-- ============================================================================

COMMENT ON TABLE structured.column_statistics IS
'Stores profiling statistics for individual columns, including cardinality, NULL distribution, numeric summaries, text characteristics, and representative sample data.';

-- ============================================================================
-- COLUMN COMMENTS
-- ============================================================================

COMMENT ON COLUMN structured.column_statistics.statistics_id IS
'Unique identifier for the column statistics record.';

COMMENT ON COLUMN structured.column_statistics.column_id IS
'Reference to the column whose profiling statistics are maintained.';

COMMENT ON COLUMN structured.column_statistics.distinct_value_count IS
'Number of distinct values present in the column.';

COMMENT ON COLUMN structured.column_statistics.duplicate_value_count IS
'Number of non-distinct (repeated) values present in the column.';

COMMENT ON COLUMN structured.column_statistics.unique_value_percentage IS
'Percentage of values in the column that are unique.';

COMMENT ON COLUMN structured.column_statistics.null_value_count IS
'Number of NULL values present in the column.';

COMMENT ON COLUMN structured.column_statistics.null_percentage IS
'Percentage of NULL values present in the column.';

COMMENT ON COLUMN structured.column_statistics.minimum_value IS
'Minimum numeric value observed in the column.';

COMMENT ON COLUMN structured.column_statistics.maximum_value IS
'Maximum numeric value observed in the column.';

COMMENT ON COLUMN structured.column_statistics.average_value IS
'Arithmetic mean of numeric values in the column.';

COMMENT ON COLUMN structured.column_statistics.median_value IS
'Median of numeric values in the column.';

COMMENT ON COLUMN structured.column_statistics.standard_deviation IS
'Standard deviation of numeric values in the column.';

COMMENT ON COLUMN structured.column_statistics.minimum_length IS
'Minimum length of text values in the column.';

COMMENT ON COLUMN structured.column_statistics.maximum_length IS
'Maximum length of text values in the column.';

COMMENT ON COLUMN structured.column_statistics.average_length IS
'Average length of text values in the column.';

COMMENT ON COLUMN structured.column_statistics.sample_values IS
'Representative sample data collected during profiling and stored in JSONB format.';

COMMENT ON COLUMN structured.column_statistics.statistics_generated_at IS
'Timestamp when the profiling statistics were most recently generated.';

COMMENT ON COLUMN structured.column_statistics.created_at IS
'Timestamp when this statistics record was created.';

COMMENT ON COLUMN structured.column_statistics.updated_at IS
'Timestamp when this statistics record was last updated.';






/*
===============================================================================
TABLE: structured.tags
SCHEMA: structured

PURPOSE:
    Stores reusable metadata tags that can be assigned to datasets, tables,
    columns, relationships, and future metadata resources.

DESCRIPTION:
    This table represents the master catalog of tags used throughout the
    OmniBrain metadata platform. Tags enable:

        • Metadata classification
        • Governance
        • Security labeling
        • Business categorization
        • Search and discovery
        • AI-assisted retrieval
        • Lifecycle management

    Tags are reusable definitions. Resource assignments are maintained in
    structured.resource_tags.

RELATED TABLES:
    • structured.resource_tags

NOTES:
    • One record represents one reusable tag.
    • Tag names are unique (case-insensitive).
    • Tags can be deactivated without deletion.
    • Compatible with PostgreSQL 17+.

===============================================================================
*/

CREATE TABLE IF NOT EXISTS structured.tags
(
    ----------------------------------------------------------------------------
    -- Primary Key
    ----------------------------------------------------------------------------
    tag_id UUID
        PRIMARY KEY
        DEFAULT gen_random_uuid(),

    ----------------------------------------------------------------------------
    -- Tag Information
    ----------------------------------------------------------------------------
    tag_name VARCHAR(100)
        NOT NULL,

    tag_name_normalized VARCHAR(100)
        GENERATED ALWAYS AS (LOWER(BTRIM(tag_name))) STORED,

    tag_category VARCHAR(50)
        NOT NULL,

    description TEXT,

    ----------------------------------------------------------------------------
    -- Display Information
    ----------------------------------------------------------------------------
    color_code CHAR(7)
        DEFAULT '#808080',

    ----------------------------------------------------------------------------
    -- Tag Properties
    ----------------------------------------------------------------------------
    is_system_tag BOOLEAN
        NOT NULL
        DEFAULT FALSE,

    is_active BOOLEAN
        NOT NULL
        DEFAULT TRUE,

    ----------------------------------------------------------------------------
    -- Audit Information
    ----------------------------------------------------------------------------
    created_by VARCHAR(100),

    created_at TIMESTAMPTZ
        NOT NULL
        DEFAULT CURRENT_TIMESTAMP,

    updated_at TIMESTAMPTZ
        NOT NULL
        DEFAULT CURRENT_TIMESTAMP,

    ----------------------------------------------------------------------------
    -- Constraints
    ----------------------------------------------------------------------------
    CONSTRAINT uq_tags_name
        UNIQUE (tag_name_normalized),

    CONSTRAINT chk_tags_name_not_blank
        CHECK (LENGTH(BTRIM(tag_name)) > 0),

    CONSTRAINT chk_tags_category
        CHECK
        (
            tag_category IN
            (
                'BUSINESS',
                'SECURITY',
                'GOVERNANCE',
                'QUALITY',
                'LIFECYCLE',
                'CUSTOM'
            )
        ),

    CONSTRAINT chk_tags_color_code
        CHECK
        (
            color_code ~ '^#[A-Fa-f0-9]{6}$'
        )
);

-- ============================================================================
-- INDEXES
-- ============================================================================

CREATE INDEX IF NOT EXISTS idx_tags_category
ON structured.tags
(
    tag_category
);

CREATE INDEX IF NOT EXISTS idx_tags_active
ON structured.tags
(
    is_active
);

CREATE INDEX IF NOT EXISTS idx_tags_system
ON structured.tags
(
    is_system_tag
);

CREATE INDEX IF NOT EXISTS idx_tags_created_at
ON structured.tags
(
    created_at DESC
);

-- ============================================================================
-- UPDATED_AT TRIGGER
-- ============================================================================

DROP TRIGGER IF EXISTS trg_tags_set_updated_at ON structured.tags;

CREATE TRIGGER trg_tags_set_updated_at
BEFORE UPDATE
ON structured.tags
FOR EACH ROW
EXECUTE FUNCTION common.set_updated_at();

-- ============================================================================
-- TABLE COMMENT
-- ============================================================================

COMMENT ON TABLE structured.tags IS
'Stores reusable metadata tag definitions for classifying and organizing resources across the OmniBrain metadata catalog.';

-- ============================================================================
-- COLUMN COMMENTS
-- ============================================================================

COMMENT ON COLUMN structured.tags.tag_id IS
'Unique identifier for the tag.';

COMMENT ON COLUMN structured.tags.tag_name IS
'Human-readable name of the metadata tag.';

COMMENT ON COLUMN structured.tags.tag_name_normalized IS
'Automatically generated lowercase representation of the tag name used for case-insensitive uniqueness.';

COMMENT ON COLUMN structured.tags.tag_category IS
'Functional category to which the tag belongs.';

COMMENT ON COLUMN structured.tags.description IS
'Detailed description explaining the purpose and usage of the tag.';

COMMENT ON COLUMN structured.tags.color_code IS
'Hexadecimal color code used for displaying the tag in user interfaces.';

COMMENT ON COLUMN structured.tags.is_system_tag IS
'Indicates whether the tag is managed internally by the system.';

COMMENT ON COLUMN structured.tags.is_active IS
'Indicates whether the tag is currently active and available for assignment.';

COMMENT ON COLUMN structured.tags.created_by IS
'User or service that created the tag definition.';

COMMENT ON COLUMN structured.tags.created_at IS
'Timestamp when the tag definition was created.';

COMMENT ON COLUMN structured.tags.updated_at IS
'Timestamp when the tag definition was last updated.';






/*
===============================================================================
TABLE: structured.resource_tags
SCHEMA: structured

PURPOSE:
    Maps reusable metadata tags to metadata resources within OmniBrain.

DESCRIPTION:
    This table implements the many-to-many relationship between reusable tags
    and metadata resources such as datasets, tables, columns, and
    relationships.

    Resource existence is validated through the trigger function
    common.validate_resource_tag().

RELATED TABLES:
    • structured.tags
    • structured.datasets
    • structured.dataset_tables
    • structured.dataset_columns
    • structured.dataset_relationships

NOTES:
    • Supports polymorphic resource references.
    • Prevents duplicate tag assignments.
    • Compatible with PostgreSQL 17+.

===============================================================================
*/

CREATE TABLE IF NOT EXISTS structured.resource_tags
(
    ----------------------------------------------------------------------------
    -- Primary Key
    ----------------------------------------------------------------------------
    resource_tag_id UUID
        PRIMARY KEY
        DEFAULT gen_random_uuid(),

    ----------------------------------------------------------------------------
    -- Tag Reference
    ----------------------------------------------------------------------------
    tag_id UUID
        NOT NULL,

    ----------------------------------------------------------------------------
    -- Resource Reference
    ----------------------------------------------------------------------------
    resource_type VARCHAR(30)
        NOT NULL,

    resource_id UUID
        NOT NULL,

    ----------------------------------------------------------------------------
    -- Assignment Metadata
    ----------------------------------------------------------------------------
    assigned_by VARCHAR(100),

    assigned_at TIMESTAMPTZ
        NOT NULL
        DEFAULT CURRENT_TIMESTAMP,

    ----------------------------------------------------------------------------
    -- Status
    ----------------------------------------------------------------------------
    is_active BOOLEAN
        NOT NULL
        DEFAULT TRUE,

    ----------------------------------------------------------------------------
    -- Audit Columns
    ----------------------------------------------------------------------------
    created_at TIMESTAMPTZ
        NOT NULL
        DEFAULT CURRENT_TIMESTAMP,

    updated_at TIMESTAMPTZ
        NOT NULL
        DEFAULT CURRENT_TIMESTAMP,

    ----------------------------------------------------------------------------
    -- Foreign Keys
    ----------------------------------------------------------------------------
    CONSTRAINT fk_resource_tags_tag
        FOREIGN KEY (tag_id)
        REFERENCES structured.tags(tag_id)
        ON UPDATE CASCADE
        ON DELETE RESTRICT,

    ----------------------------------------------------------------------------
    -- Constraints
    ----------------------------------------------------------------------------
    CONSTRAINT uq_resource_tags_assignment
        UNIQUE
        (
            resource_type,
            resource_id,
            tag_id
        ),

    CONSTRAINT chk_resource_tags_resource_type
        CHECK
        (
            resource_type IN
            (
                'DATASET',
                'TABLE',
                'COLUMN',
                'RELATIONSHIP'
            )
        )
);

-- ============================================================================
-- INDEXES
-- ============================================================================

CREATE INDEX IF NOT EXISTS idx_resource_tags_tag
ON structured.resource_tags
(
    tag_id
);

CREATE INDEX IF NOT EXISTS idx_resource_tags_resource
ON structured.resource_tags
(
    resource_type,
    resource_id
);

CREATE INDEX IF NOT EXISTS idx_resource_tags_active
ON structured.resource_tags
(
    is_active
);

CREATE INDEX IF NOT EXISTS idx_resource_tags_assigned_at
ON structured.resource_tags
(
    assigned_at DESC
);

-- ============================================================================
-- TRIGGERS
-- ============================================================================

DROP TRIGGER IF EXISTS trg_resource_tags_validate_resource ON structured.resource_tags;

CREATE TRIGGER trg_resource_tags_validate_resource
BEFORE INSERT OR UPDATE
ON structured.resource_tags
FOR EACH ROW
EXECUTE FUNCTION common.validate_resource_tag();

DROP TRIGGER IF EXISTS trg_resource_tags_set_updated_at ON structured.resource_tags;

CREATE TRIGGER trg_resource_tags_set_updated_at
BEFORE UPDATE
ON structured.resource_tags
FOR EACH ROW
EXECUTE FUNCTION common.set_updated_at();

-- ============================================================================
-- TABLE COMMENT
-- ============================================================================

COMMENT ON TABLE structured.resource_tags IS
'Maps reusable metadata tags to datasets, tables, columns, relationships, and future metadata resources.';

-- ============================================================================
-- COLUMN COMMENTS
-- ============================================================================

COMMENT ON COLUMN structured.resource_tags.resource_tag_id IS
'Unique identifier for the resource-tag assignment.';

COMMENT ON COLUMN structured.resource_tags.tag_id IS
'Reference to the reusable metadata tag.';

COMMENT ON COLUMN structured.resource_tags.resource_type IS
'Type of metadata resource receiving the tag.';

COMMENT ON COLUMN structured.resource_tags.resource_id IS
'Identifier of the tagged metadata resource.';

COMMENT ON COLUMN structured.resource_tags.assigned_by IS
'User or service that assigned the tag.';

COMMENT ON COLUMN structured.resource_tags.assigned_at IS
'Timestamp when the tag was assigned to the resource.';

COMMENT ON COLUMN structured.resource_tags.is_active IS
'Indicates whether the tag assignment is currently active.';

COMMENT ON COLUMN structured.resource_tags.created_at IS
'Timestamp when the assignment record was created.';

COMMENT ON COLUMN structured.resource_tags.updated_at IS
'Timestamp when the assignment record was last updated.';







/*
===============================================================================
TABLE: structured.dataset_refresh_history
SCHEMA: structured

PURPOSE:
    Stores the execution history of dataset refresh operations performed within
    OmniBrain.

DESCRIPTION:
    Each record represents a single refresh execution for a dataset. The table
    supports operational monitoring, auditing, troubleshooting, retry analysis,
    scheduling analytics, and performance reporting.

    Historical records are immutable and should never be deleted as part of
    normal system operations.

RELATED TABLES:
    • structured.datasets

NOTES:
    • One row represents one refresh execution.
    • Stores operational metrics and execution status.
    • Compatible with PostgreSQL 17+.

===============================================================================
*/

CREATE TABLE IF NOT EXISTS structured.dataset_refresh_history
(
    ----------------------------------------------------------------------------
    -- Primary Key
    ----------------------------------------------------------------------------
    refresh_id UUID
        PRIMARY KEY
        DEFAULT gen_random_uuid(),

    ----------------------------------------------------------------------------
    -- Dataset
    ----------------------------------------------------------------------------
    dataset_id UUID
        NOT NULL,

    ----------------------------------------------------------------------------
    -- Execution Information
    ----------------------------------------------------------------------------
    execution_id UUID
        NOT NULL
        DEFAULT gen_random_uuid(),

    refresh_type VARCHAR(20)
        NOT NULL,

    refresh_mode VARCHAR(20)
        NOT NULL,

    refresh_status VARCHAR(20)
        NOT NULL,

    retry_number INTEGER
        NOT NULL
        DEFAULT 0,

    ----------------------------------------------------------------------------
    -- Timing
    ----------------------------------------------------------------------------
    started_at TIMESTAMPTZ
        NOT NULL
        DEFAULT CURRENT_TIMESTAMP,

    completed_at TIMESTAMPTZ,

    duration_ms BIGINT,

    ----------------------------------------------------------------------------
    -- Row Metrics
    ----------------------------------------------------------------------------
    rows_read BIGINT
        DEFAULT 0,

    rows_processed BIGINT
        DEFAULT 0,

    rows_inserted BIGINT
        DEFAULT 0,

    rows_updated BIGINT
        DEFAULT 0,

    rows_deleted BIGINT
        DEFAULT 0,

    rows_failed BIGINT
        DEFAULT 0,

    ----------------------------------------------------------------------------
    -- Error Information
    ----------------------------------------------------------------------------
    error_code VARCHAR(100),

    error_message TEXT,

    ----------------------------------------------------------------------------
    -- User Information
    ----------------------------------------------------------------------------
    triggered_by VARCHAR(100),

    ----------------------------------------------------------------------------
    -- Audit Columns
    ----------------------------------------------------------------------------
    created_at TIMESTAMPTZ
        NOT NULL
        DEFAULT CURRENT_TIMESTAMP,

    updated_at TIMESTAMPTZ
        NOT NULL
        DEFAULT CURRENT_TIMESTAMP,

    ----------------------------------------------------------------------------
    -- Foreign Keys
    ----------------------------------------------------------------------------
    CONSTRAINT fk_dataset_refresh_history_dataset
        FOREIGN KEY (dataset_id)
        REFERENCES structured.datasets(dataset_id)
        ON UPDATE CASCADE
        ON DELETE CASCADE,

    ----------------------------------------------------------------------------
    -- Constraints
    ----------------------------------------------------------------------------
    CONSTRAINT uq_dataset_refresh_execution
        UNIQUE (execution_id),

    CONSTRAINT chk_dataset_refresh_type
        CHECK
        (
            refresh_type IN
            (
                'MANUAL',
                'SCHEDULED',
                'SYSTEM',
                'API'
            )
        ),

    CONSTRAINT chk_dataset_refresh_mode
        CHECK
        (
            refresh_mode IN
            (
                'FULL',
                'INCREMENTAL',
                'METADATA_ONLY'
            )
        ),

    CONSTRAINT chk_dataset_refresh_status
        CHECK
        (
            refresh_status IN
            (
                'RUNNING',
                'SUCCESS',
                'FAILED',
                'CANCELLED'
            )
        ),

    CONSTRAINT chk_dataset_refresh_retry
        CHECK (retry_number >= 0),

    CONSTRAINT chk_dataset_refresh_duration
        CHECK
        (
            duration_ms IS NULL
            OR duration_ms >= 0
        ),

    CONSTRAINT chk_dataset_refresh_completed
        CHECK
        (
            completed_at IS NULL
            OR completed_at >= started_at
        ),

    CONSTRAINT chk_dataset_refresh_rows_read
        CHECK (rows_read >= 0),

    CONSTRAINT chk_dataset_refresh_rows_processed
        CHECK (rows_processed >= 0),

    CONSTRAINT chk_dataset_refresh_rows_inserted
        CHECK (rows_inserted >= 0),

    CONSTRAINT chk_dataset_refresh_rows_updated
        CHECK (rows_updated >= 0),

    CONSTRAINT chk_dataset_refresh_rows_deleted
        CHECK (rows_deleted >= 0),

    CONSTRAINT chk_dataset_refresh_rows_failed
        CHECK (rows_failed >= 0)
);

-- ============================================================================
-- INDEXES
-- ============================================================================

CREATE INDEX IF NOT EXISTS idx_dataset_refresh_dataset
ON structured.dataset_refresh_history
(
    dataset_id
);

CREATE INDEX IF NOT EXISTS idx_dataset_refresh_status
ON structured.dataset_refresh_history
(
    refresh_status
);

CREATE INDEX IF NOT EXISTS idx_dataset_refresh_type
ON structured.dataset_refresh_history
(
    refresh_type
);

CREATE INDEX IF NOT EXISTS idx_dataset_refresh_started
ON structured.dataset_refresh_history
(
    started_at DESC
);

CREATE INDEX IF NOT EXISTS idx_dataset_refresh_completed
ON structured.dataset_refresh_history
(
    completed_at DESC
);

CREATE INDEX IF NOT EXISTS idx_dataset_refresh_execution
ON structured.dataset_refresh_history
(
    execution_id
);

-- ============================================================================
-- UPDATED_AT TRIGGER
-- ============================================================================

DROP TRIGGER IF EXISTS trg_dataset_refresh_history_set_updated_at ON structured.dataset_refresh_history;

CREATE TRIGGER trg_dataset_refresh_history_set_updated_at
BEFORE UPDATE
ON structured.dataset_refresh_history
FOR EACH ROW
EXECUTE FUNCTION common.set_updated_at();

-- ============================================================================
-- TABLE COMMENT
-- ============================================================================

COMMENT ON TABLE structured.dataset_refresh_history IS
'Stores the execution history of dataset refresh operations, including execution metadata, operational metrics, timing information, retry history, and execution outcomes.';

-- ============================================================================
-- COLUMN COMMENTS
-- ============================================================================

COMMENT ON COLUMN structured.dataset_refresh_history.refresh_id IS
'Unique identifier for the refresh execution.';

COMMENT ON COLUMN structured.dataset_refresh_history.dataset_id IS
'Reference to the dataset being refreshed.';

COMMENT ON COLUMN structured.dataset_refresh_history.execution_id IS
'Unique execution identifier generated for the refresh operation.';

COMMENT ON COLUMN structured.dataset_refresh_history.refresh_type IS
'Origin of the refresh request.';

COMMENT ON COLUMN structured.dataset_refresh_history.refresh_mode IS
'Execution mode of the refresh process.';

COMMENT ON COLUMN structured.dataset_refresh_history.refresh_status IS
'Current or final execution status of the refresh.';

COMMENT ON COLUMN structured.dataset_refresh_history.retry_number IS
'Retry attempt number for this execution.';

COMMENT ON COLUMN structured.dataset_refresh_history.started_at IS
'Timestamp when refresh execution started.';

COMMENT ON COLUMN structured.dataset_refresh_history.completed_at IS
'Timestamp when refresh execution completed.';

COMMENT ON COLUMN structured.dataset_refresh_history.duration_ms IS
'Execution duration in milliseconds.';

COMMENT ON COLUMN structured.dataset_refresh_history.rows_read IS
'Number of rows read from the source.';

COMMENT ON COLUMN structured.dataset_refresh_history.rows_processed IS
'Number of rows processed during refresh.';

COMMENT ON COLUMN structured.dataset_refresh_history.rows_inserted IS
'Number of rows inserted into the destination.';

COMMENT ON COLUMN structured.dataset_refresh_history.rows_updated IS
'Number of rows updated in the destination.';

COMMENT ON COLUMN structured.dataset_refresh_history.rows_deleted IS
'Number of rows deleted from the destination.';

COMMENT ON COLUMN structured.dataset_refresh_history.rows_failed IS
'Number of rows that failed processing.';

COMMENT ON COLUMN structured.dataset_refresh_history.error_code IS
'Machine-readable error code describing the failure.';

COMMENT ON COLUMN structured.dataset_refresh_history.error_message IS
'Detailed error message captured during refresh execution.';

COMMENT ON COLUMN structured.dataset_refresh_history.triggered_by IS
'User or service responsible for initiating the refresh.';

COMMENT ON COLUMN structured.dataset_refresh_history.created_at IS
'Timestamp when the refresh history record was created.';

COMMENT ON COLUMN structured.dataset_refresh_history.updated_at IS
'Timestamp when the refresh history record was last updated.';