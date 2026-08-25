/*
===============================================================================
 OmniBrain Database Project
 Module      : Query Engine
 File        : 00_lookup_tables.sql
 Schema      : query_engine
 Author      : OmniBrain Database Team
 Description : Master lookup tables used by the Query Engine.
===============================================================================

Purpose
-------
Provides immutable reference/master data for the Query Engine.

These tables intentionally replace PostgreSQL ENUMs because lookup tables
allow new values to be introduced without schema migrations.

Tables
------
1. query_statuses
2. query_intents
3. retrieval_strategies

===============================================================================
*/

SET search_path TO query_engine, public;

-- ============================================================================
-- QUERY STATUSES
-- ============================================================================

CREATE TABLE IF NOT EXISTS query_engine.query_statuses
(
    status_id SMALLINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,

    status_code VARCHAR(50) NOT NULL UNIQUE,

    display_name VARCHAR(100) NOT NULL,

    description TEXT,

    color_code VARCHAR(10),

    icon_name VARCHAR(50),

    display_order SMALLINT NOT NULL UNIQUE,

    is_terminal BOOLEAN NOT NULL DEFAULT FALSE,

    is_active BOOLEAN NOT NULL DEFAULT TRUE,

    is_system BOOLEAN NOT NULL DEFAULT TRUE,

    version INTEGER NOT NULL DEFAULT 1,

    metadata JSONB NOT NULL DEFAULT '{}'::jsonb,

    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,

    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT chk_query_status_display_order
        CHECK (display_order > 0)
);

COMMENT ON TABLE query_engine.query_statuses IS
'Master list of all possible query execution statuses.';

-- ============================================================================
-- QUERY INTENTS
-- ============================================================================

CREATE TABLE IF NOT EXISTS query_engine.query_intents
(
    intent_id SMALLINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,

    intent_code VARCHAR(50) NOT NULL UNIQUE,

    display_name VARCHAR(100) NOT NULL,

    description TEXT,

    color_code VARCHAR(10),

    icon_name VARCHAR(50),

    display_order SMALLINT NOT NULL UNIQUE,

    is_active BOOLEAN NOT NULL DEFAULT TRUE,

    is_system BOOLEAN NOT NULL DEFAULT TRUE,

    version INTEGER NOT NULL DEFAULT 1,

    metadata JSONB NOT NULL DEFAULT '{}'::jsonb,

    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,

    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT chk_query_intent_display_order
        CHECK (display_order > 0)
);

COMMENT ON TABLE query_engine.query_intents IS
'Master list of supported query intents.';

-- ============================================================================
-- RETRIEVAL STRATEGIES
-- ============================================================================

CREATE TABLE IF NOT EXISTS query_engine.retrieval_strategies
(
    strategy_id SMALLINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,

    strategy_code VARCHAR(50) NOT NULL UNIQUE,

    display_name VARCHAR(100) NOT NULL,

    description TEXT,

    category VARCHAR(50),

    color_code VARCHAR(10),

    icon_name VARCHAR(50),

    supports_vector BOOLEAN NOT NULL DEFAULT FALSE,

    supports_keyword BOOLEAN NOT NULL DEFAULT FALSE,

    supports_sql BOOLEAN NOT NULL DEFAULT FALSE,

    supports_graph BOOLEAN NOT NULL DEFAULT FALSE,

    supports_multimodal BOOLEAN NOT NULL DEFAULT FALSE,

    supports_agents BOOLEAN NOT NULL DEFAULT FALSE,

    display_order SMALLINT NOT NULL UNIQUE,

    is_active BOOLEAN NOT NULL DEFAULT TRUE,

    is_system BOOLEAN NOT NULL DEFAULT TRUE,

    version INTEGER NOT NULL DEFAULT 1,

    metadata JSONB NOT NULL DEFAULT '{}'::jsonb,

    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,

    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT chk_strategy_display_order
        CHECK (display_order > 0)
);

COMMENT ON TABLE query_engine.retrieval_strategies IS
'Master list of retrieval strategies supported by OmniBrain.';

-- ============================================================================
-- TRIGGERS
-- ============================================================================

DROP TRIGGER IF EXISTS trg_query_statuses_updated_at ON query_engine.query_statuses;

CREATE TRIGGER trg_query_statuses_updated_at
BEFORE UPDATE
ON query_engine.query_statuses
FOR EACH ROW
EXECUTE FUNCTION public.update_updated_at_column();

DROP TRIGGER IF EXISTS trg_query_intents_updated_at ON query_engine.query_intents;

CREATE TRIGGER trg_query_intents_updated_at
BEFORE UPDATE
ON query_engine.query_intents
FOR EACH ROW
EXECUTE FUNCTION public.update_updated_at_column();

DROP TRIGGER IF EXISTS trg_retrieval_strategies_updated_at ON query_engine.retrieval_strategies;

CREATE TRIGGER trg_retrieval_strategies_updated_at
BEFORE UPDATE
ON query_engine.retrieval_strategies
FOR EACH ROW
EXECUTE FUNCTION public.update_updated_at_column();

-- ============================================================================
-- SEED : QUERY STATUSES
-- ============================================================================

INSERT INTO query_engine.query_statuses
(
status_code,
display_name,
description,
color_code,
icon_name,
display_order,
is_terminal
)
VALUES
('PENDING','Pending','Query has been accepted.','#F59E0B','clock',1,FALSE),
('PROCESSING','Processing','Query is currently executing.','#3B82F6','loader',2,FALSE),
('COMPLETED','Completed','Query finished successfully.','#10B981','check-circle',3,TRUE),
('FAILED','Failed','Query execution failed.','#EF4444','x-circle',4,TRUE),
('CANCELLED','Cancelled','Query cancelled by the user.','#6B7280','ban',5,TRUE)
ON CONFLICT (status_code)
DO UPDATE SET
display_name = EXCLUDED.display_name,
description = EXCLUDED.description,
color_code = EXCLUDED.color_code,
icon_name = EXCLUDED.icon_name,
display_order = EXCLUDED.display_order,
is_terminal = EXCLUDED.is_terminal,
updated_at = CURRENT_TIMESTAMP;

-- ============================================================================
-- SEED : QUERY INTENTS
-- ============================================================================

INSERT INTO query_engine.query_intents
(
intent_code,
display_name,
description,
color_code,
icon_name,
display_order
)
VALUES
('QUESTION','Question Answering','General question answering.','#2563EB','message-circle',1),
('SUMMARIZATION','Summarization','Summarize supplied content.','#7C3AED','file-text',2),
('SEARCH','Semantic Search','Search knowledge base.','#059669','search',3),
('SQL','Structured Query','Execute Text-to-SQL workflow.','#DC2626','database',4),
('ANALYSIS','Analysis','Perform analytical reasoning.','#EA580C','brain',5),
('TRANSLATION','Translation','Translate between languages.','#0891B2','languages',6),
('CODE','Programming','Software engineering and coding.','#4F46E5','code',7),
('IMAGE','Image Understanding','Vision-language reasoning.','#9333EA','image',8)
ON CONFLICT (intent_code)
DO UPDATE SET
display_name = EXCLUDED.display_name,
description = EXCLUDED.description,
color_code = EXCLUDED.color_code,
icon_name = EXCLUDED.icon_name,
display_order = EXCLUDED.display_order,
updated_at = CURRENT_TIMESTAMP;

-- ============================================================================
-- SEED : RETRIEVAL STRATEGIES
-- ============================================================================

INSERT INTO query_engine.retrieval_strategies
(
strategy_code,
display_name,
description,
category,
color_code,
icon_name,
supports_vector,
supports_keyword,
supports_sql,
supports_graph,
supports_multimodal,
supports_agents,
display_order
)
VALUES
('VECTOR','Vector Search','Dense semantic retrieval.','SEARCH','#2563EB','cpu',TRUE,FALSE,FALSE,FALSE,TRUE,FALSE,1),
('KEYWORD','Keyword Search','Lexical retrieval.','SEARCH','#059669','search',FALSE,TRUE,FALSE,FALSE,FALSE,FALSE,2),
('HYBRID','Hybrid Retrieval','Dense + sparse retrieval.','SEARCH','#7C3AED','layers',TRUE,TRUE,FALSE,FALSE,TRUE,FALSE,3),
('SQL','Text-to-SQL','Structured relational retrieval.','DATABASE','#DC2626','database',FALSE,FALSE,TRUE,FALSE,FALSE,FALSE,4),
('GRAPH','Knowledge Graph','Graph traversal retrieval.','GRAPH','#EA580C','share-2',FALSE,FALSE,FALSE,TRUE,FALSE,FALSE,5),
('MULTI_AGENT','Multi-Agent','Supervisor orchestrates multiple agents.','AGENT','#9333EA','brain',TRUE,TRUE,TRUE,TRUE,TRUE,TRUE,6)
ON CONFLICT (strategy_code)
DO UPDATE SET
display_name = EXCLUDED.display_name,
description = EXCLUDED.description,
category = EXCLUDED.category,
color_code = EXCLUDED.color_code,
icon_name = EXCLUDED.icon_name,
supports_vector = EXCLUDED.supports_vector,
supports_keyword = EXCLUDED.supports_keyword,
supports_sql = EXCLUDED.supports_sql,
supports_graph = EXCLUDED.supports_graph,
supports_multimodal = EXCLUDED.supports_multimodal,
supports_agents = EXCLUDED.supports_agents,
display_order = EXCLUDED.display_order,
updated_at = CURRENT_TIMESTAMP;




/*
===============================================================================
 OmniBrain Database Project
 Module      : Query Engine
 File        : 00_query_priorities.sql
 Schema      : query_engine
 Author      : OmniBrain Database Team
 Description : Master lookup table defining query execution priorities.
===============================================================================

PURPOSE
-------
Defines the execution priority of queries submitted to OmniBrain.

Rather than storing numeric priority values directly in transactional
tables, this lookup table centralizes priority management and enables
future scheduling, queue management, and workload orchestration.

Examples
--------
BACKGROUND
LOW
NORMAL
HIGH
REALTIME
CRITICAL

Referenced By
-------------
query_engine.queries

===============================================================================
*/

SET search_path TO query_engine, public;

-- ============================================================================
-- QUERY PRIORITIES
-- ============================================================================

CREATE TABLE IF NOT EXISTS query_engine.query_priorities
(
    ---------------------------------------------------------------------------
    -- Primary Key
    ---------------------------------------------------------------------------
    priority_id SMALLINT
        GENERATED ALWAYS AS IDENTITY
        PRIMARY KEY,

    ---------------------------------------------------------------------------
    -- Business Identifier
    ---------------------------------------------------------------------------
    priority_code VARCHAR(50) NOT NULL UNIQUE,

    ---------------------------------------------------------------------------
    -- Display Information
    ---------------------------------------------------------------------------
    display_name VARCHAR(100) NOT NULL,

    description TEXT,

    color_code VARCHAR(10),

    icon_name VARCHAR(50),

    ---------------------------------------------------------------------------
    -- Scheduling Information
    ---------------------------------------------------------------------------
    priority_weight SMALLINT NOT NULL,

    display_order SMALLINT NOT NULL UNIQUE,

    ---------------------------------------------------------------------------
    -- Administration
    ---------------------------------------------------------------------------
    is_system BOOLEAN NOT NULL DEFAULT TRUE,

    is_active BOOLEAN NOT NULL DEFAULT TRUE,

    version INTEGER NOT NULL DEFAULT 1,

    metadata JSONB NOT NULL
        DEFAULT '{}'::jsonb,

    ---------------------------------------------------------------------------
    -- Audit
    ---------------------------------------------------------------------------
    created_at TIMESTAMPTZ NOT NULL
        DEFAULT CURRENT_TIMESTAMP,

    updated_at TIMESTAMPTZ NOT NULL
        DEFAULT CURRENT_TIMESTAMP,

    ---------------------------------------------------------------------------
    -- Constraints
    ---------------------------------------------------------------------------

    CONSTRAINT chk_priority_weight
        CHECK (priority_weight > 0),

    CONSTRAINT chk_priority_display_order
        CHECK (display_order > 0)
);

COMMENT ON TABLE query_engine.query_priorities IS
'Master lookup table defining execution priorities for queries.';

COMMENT ON COLUMN query_engine.query_priorities.priority_code IS
'Immutable business identifier used internally.';

COMMENT ON COLUMN query_engine.query_priorities.priority_weight IS
'Numeric weight used by schedulers and execution queues. Higher values indicate higher priority.';

COMMENT ON COLUMN query_engine.query_priorities.display_order IS
'Ordering used for UI presentation.';

COMMENT ON COLUMN query_engine.query_priorities.metadata IS
'Extensible JSON metadata for future scheduling and routing features.';

-- ============================================================================
-- UPDATED_AT TRIGGER
-- ============================================================================

DROP TRIGGER IF EXISTS trg_query_priorities_updated_at ON query_engine.query_priorities;

CREATE TRIGGER trg_query_priorities_updated_at
BEFORE UPDATE
ON query_engine.query_priorities
FOR EACH ROW
EXECUTE FUNCTION public.update_updated_at_column();

-- ============================================================================
-- SEED DATA
-- ============================================================================

INSERT INTO query_engine.query_priorities
(
    priority_code,
    display_name,
    description,
    color_code,
    icon_name,
    priority_weight,
    display_order
)
VALUES

(
    'BACKGROUND',
    'Background',
    'Lowest priority. Executed when system resources are available.',
    '#94A3B8',
    'clock',
    10,
    1
),

(
    'LOW',
    'Low',
    'Low-priority user request.',
    '#22C55E',
    'chevrons-down',
    25,
    2
),

(
    'NORMAL',
    'Normal',
    'Default execution priority.',
    '#3B82F6',
    'minus',
    50,
    3
),

(
    'HIGH',
    'High',
    'High-priority execution.',
    '#F59E0B',
    'chevrons-up',
    75,
    4
),

(
    'REALTIME',
    'Real-Time',
    'Latency-sensitive interactive query.',
    '#8B5CF6',
    'zap',
    90,
    5
),

(
    'CRITICAL',
    'Critical',
    'Highest execution priority reserved for administrative or emergency workloads.',
    '#EF4444',
    'alert-triangle',
    100,
    6
)

ON CONFLICT (priority_code)
DO UPDATE
SET
    display_name    = EXCLUDED.display_name,
    description     = EXCLUDED.description,
    color_code      = EXCLUDED.color_code,
    icon_name       = EXCLUDED.icon_name,
    priority_weight = EXCLUDED.priority_weight,
    display_order   = EXCLUDED.display_order,
    updated_at      = CURRENT_TIMESTAMP;



-- ============================================================================
-- CONTEXT ITEM TYPES
-- ============================================================================

CREATE TABLE IF NOT EXISTS query_engine.context_item_types
(
    ---------------------------------------------------------------------------
    -- Primary Key
    ---------------------------------------------------------------------------

    item_type_id SMALLINT
        GENERATED ALWAYS AS IDENTITY
        PRIMARY KEY,

    ---------------------------------------------------------------------------
    -- Business Identifier
    ---------------------------------------------------------------------------

    item_type_code VARCHAR(50)
        NOT NULL
        UNIQUE,

    ---------------------------------------------------------------------------
    -- Display Information
    ---------------------------------------------------------------------------

    display_name VARCHAR(100)
        NOT NULL,

    description TEXT,

    color_code VARCHAR(10),

    icon_name VARCHAR(50),

    ---------------------------------------------------------------------------
    -- Ordering
    ---------------------------------------------------------------------------

    display_order SMALLINT
        NOT NULL
        UNIQUE,

    ---------------------------------------------------------------------------
    -- Administration
    ---------------------------------------------------------------------------

    is_system BOOLEAN
        NOT NULL
        DEFAULT TRUE,

    is_active BOOLEAN
        NOT NULL
        DEFAULT TRUE,

    version INTEGER
        NOT NULL
        DEFAULT 1,

    metadata JSONB
        NOT NULL
        DEFAULT '{}'::jsonb,

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

    CONSTRAINT chk_context_item_display_order
        CHECK (display_order > 0)

);

COMMENT ON TABLE query_engine.context_item_types IS
'Master lookup table defining supported evidence types returned during retrieval.';

COMMENT ON COLUMN query_engine.context_item_types.item_type_code IS
'Immutable business identifier for the evidence type.';

COMMENT ON COLUMN query_engine.context_item_types.display_name IS
'Human-readable name displayed in the UI.';

COMMENT ON COLUMN query_engine.context_item_types.metadata IS
'Extensible metadata describing future evidence-type capabilities.';

-- ============================================================================
-- UPDATED_AT TRIGGER
-- ============================================================================

DROP TRIGGER IF EXISTS trg_context_item_types_updated_at ON query_engine.context_item_types;

CREATE TRIGGER trg_context_item_types_updated_at
BEFORE UPDATE
ON query_engine.context_item_types
FOR EACH ROW
EXECUTE FUNCTION public.update_updated_at_column();

-- ============================================================================
-- SEED DATA
-- ============================================================================

INSERT INTO query_engine.context_item_types
(
    item_type_code,
    display_name,
    description,
    color_code,
    icon_name,
    display_order
)
VALUES

(
'CHUNK',
'Text Chunk',
'Semantic text chunk extracted from a document.',
'#2563EB',
'file-text',
1
),

(
'IMAGE',
'Image',
'Image extracted from a document.',
'#9333EA',
'image',
2
),

(
'TABLE',
'Table',
'Structured table extracted from a document.',
'#F59E0B',
'table',
3
),

(
'STRUCTURED',
'Structured Data',
'Structured database record returned from SQL retrieval.',
'#10B981',
'database',
4
),

(
'GRAPH_NODE',
'Graph Node',
'Knowledge graph node returned during graph retrieval.',
'#06B6D4',
'share-2',
5
),

(
'GRAPH_EDGE',
'Graph Edge',
'Relationship between graph nodes.',
'#0891B2',
'git-branch',
6
),

(
'AUDIO_SEGMENT',
'Audio Segment',
'Relevant audio segment.',
'#8B5CF6',
'volume-2',
7
),

(
'VIDEO_SEGMENT',
'Video Segment',
'Relevant video segment.',
'#DC2626',
'video',
8
),

(
'WEB_PAGE',
'Web Page',
'Retrieved webpage or HTML document.',
'#0EA5E9',
'globe',
9
),

(
'CODE_BLOCK',
'Code Block',
'Retrieved source code snippet.',
'#6366F1',
'code',
10
)

ON CONFLICT (item_type_code)
DO UPDATE
SET

display_name = EXCLUDED.display_name,

description = EXCLUDED.description,

color_code = EXCLUDED.color_code,

icon_name = EXCLUDED.icon_name,

display_order = EXCLUDED.display_order,

updated_at = CURRENT_TIMESTAMP;