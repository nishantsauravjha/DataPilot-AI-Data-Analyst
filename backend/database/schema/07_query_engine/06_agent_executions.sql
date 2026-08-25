/*
===============================================================================
 OmniBrain Database Project
 Module      : Query Engine
 File        : 06_agent_executions.sql
 Schema      : query_engine
 Author      : OmniBrain Database Team
 Description : Stores execution records for every AI agent participating
               in query processing.
===============================================================================

DESCRIPTION
-----------
Each row represents ONE execution of ONE agent while processing a query.

Examples
--------

Query
  │
  ▼
Supervisor Agent
  │
  ├──────────────┬───────────────┐
  ▼              ▼               ▼
Retriever     SQL Agent     Vision Agent

Each execution becomes one row.

This table stores execution metadata only.

It intentionally DOES NOT store

• Final response text
• Retrieved evidence
• Citations
• Token usage
• Costs
• Latency

Those belong to their respective tables.

DEPENDENCIES
------------
query_engine.queries
public.update_updated_at_column()

REFERENCED BY
-------------
query_engine.responses
query_engine.metrics

===============================================================================
*/

SET search_path TO query_engine, public;

-- ============================================================================
-- TABLE : agent_executions
-- ============================================================================

CREATE TABLE IF NOT EXISTS query_engine.agent_executions
(

    ---------------------------------------------------------------------------
    -- Primary Key
    ---------------------------------------------------------------------------

    agent_execution_id UUID PRIMARY KEY
        DEFAULT uuid_generate_v4(),

    ---------------------------------------------------------------------------
    -- Relationships
    ---------------------------------------------------------------------------

    query_id UUID NOT NULL,

    parent_execution_id UUID,

    ---------------------------------------------------------------------------
    -- Agent Information
    ---------------------------------------------------------------------------

    agent_name TEXT NOT NULL,

    agent_version VARCHAR(50),

    execution_role VARCHAR(30)
        NOT NULL,

    execution_status VARCHAR(30)
        NOT NULL
        DEFAULT 'PENDING',

    execution_sequence INTEGER
        NOT NULL,

    ---------------------------------------------------------------------------
    -- Tool Information
    ---------------------------------------------------------------------------

    tool_name TEXT,

    tool_call_id VARCHAR(255),

    ---------------------------------------------------------------------------
    -- Execution Summary
    ---------------------------------------------------------------------------

    input_summary TEXT,

    output_summary TEXT,

    ---------------------------------------------------------------------------
    -- Error Information
    ---------------------------------------------------------------------------

    error_code VARCHAR(100),

    error_message TEXT,

    ---------------------------------------------------------------------------
    -- Retry Information
    ---------------------------------------------------------------------------

    retry_count SMALLINT
        NOT NULL
        DEFAULT 0,

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

    CONSTRAINT chk_execution_role
        CHECK
        (
            execution_role IN
            (
                'SUPERVISOR',
                'PLANNER',
                'RETRIEVER',
                'WORKER',
                'SYNTHESIZER',
                'VALIDATOR'
            )
        ),

    CONSTRAINT chk_execution_status
        CHECK
        (
            execution_status IN
            (
                'PENDING',
                'RUNNING',
                'COMPLETED',
                'FAILED',
                'SKIPPED',
                'CANCELLED'
            )
        ),

    CONSTRAINT chk_execution_sequence
        CHECK (execution_sequence > 0),

    CONSTRAINT chk_retry_count
        CHECK (retry_count >= 0),

    CONSTRAINT chk_version
        CHECK (version > 0),

    CONSTRAINT chk_tool_name
        CHECK
        (
            tool_name IS NULL
            OR
            length(trim(tool_name)) > 0
        ),

    CONSTRAINT chk_error_code
        CHECK
        (
            error_code IS NULL
            OR
            length(trim(error_code)) > 0
        ),

    ---------------------------------------------------------------------------
    -- Foreign Keys
    ---------------------------------------------------------------------------

    CONSTRAINT fk_agent_execution_query
        FOREIGN KEY (query_id)
        REFERENCES query_engine.queries(query_id)
        ON UPDATE CASCADE
        ON DELETE CASCADE,

    CONSTRAINT fk_parent_agent_execution
        FOREIGN KEY (parent_execution_id)
        REFERENCES query_engine.agent_executions(agent_execution_id)
        ON UPDATE CASCADE
        ON DELETE SET NULL,

    ---------------------------------------------------------------------------
    -- Unique Constraints
    ---------------------------------------------------------------------------

    CONSTRAINT uq_execution_sequence
        UNIQUE
        (
            query_id,
            execution_sequence
        )

)

WITH
(
    fillfactor = 90
);

-- ============================================================================
-- TABLE COMMENT
-- ============================================================================

COMMENT ON TABLE query_engine.agent_executions IS
'Stores one execution record for each AI agent participating in query processing. Each row represents a single execution attempt within the agent orchestration pipeline.';

-- ============================================================================
-- COLUMN COMMENTS
-- ============================================================================

COMMENT ON COLUMN query_engine.agent_executions.agent_execution_id IS
'Unique identifier for the agent execution.';

COMMENT ON COLUMN query_engine.agent_executions.query_id IS
'Logical query that initiated this agent execution.';

COMMENT ON COLUMN query_engine.agent_executions.parent_execution_id IS
'Optional parent execution used to model hierarchical or recursive agent workflows.';

COMMENT ON COLUMN query_engine.agent_executions.agent_name IS
'Logical name of the executing AI agent.';

COMMENT ON COLUMN query_engine.agent_executions.agent_version IS
'Version of the executing agent implementation.';

COMMENT ON COLUMN query_engine.agent_executions.execution_role IS
'Functional role performed by the agent during orchestration.';

COMMENT ON COLUMN query_engine.agent_executions.execution_status IS
'Current lifecycle state of this execution.';

COMMENT ON COLUMN query_engine.agent_executions.execution_sequence IS
'Execution order within the query pipeline.';

COMMENT ON COLUMN query_engine.agent_executions.tool_name IS
'External tool or subsystem invoked by this execution.';

COMMENT ON COLUMN query_engine.agent_executions.tool_call_id IS
'Identifier returned by the external tool invocation, if available.';

COMMENT ON COLUMN query_engine.agent_executions.input_summary IS
'Short summary of the information provided to the agent.';

COMMENT ON COLUMN query_engine.agent_executions.output_summary IS
'Short summary of the result produced by the agent.';

COMMENT ON COLUMN query_engine.agent_executions.error_code IS
'Machine-readable error identifier produced during execution.';

COMMENT ON COLUMN query_engine.agent_executions.error_message IS
'Human-readable description of any execution failure.';

COMMENT ON COLUMN query_engine.agent_executions.retry_count IS
'Number of retry attempts performed for this execution.';

COMMENT ON COLUMN query_engine.agent_executions.metadata IS
'Flexible JSON document storing routing decisions, reasoning metadata, planner outputs, temporary execution configuration, and future extensions.';

COMMENT ON COLUMN query_engine.agent_executions.version IS
'Schema version of the execution record.';

COMMENT ON COLUMN query_engine.agent_executions.created_at IS
'Timestamp when the execution record was created.';

COMMENT ON COLUMN query_engine.agent_executions.updated_at IS
'Timestamp automatically updated whenever the row changes.';

-- ============================================================================
-- UPDATED_AT TRIGGER
-- ============================================================================

DROP TRIGGER IF EXISTS trg_agent_executions_updated_at ON query_engine.agent_executions;

CREATE TRIGGER trg_agent_executions_updated_at
BEFORE UPDATE
ON query_engine.agent_executions
FOR EACH ROW
EXECUTE FUNCTION public.update_updated_at_column();