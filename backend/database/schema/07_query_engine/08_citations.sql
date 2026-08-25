/*
===============================================================================
 OmniBrain Database Project
 Module      : Query Engine
 File        : 08_citations.sql
 Schema      : query_engine
 Author      : OmniBrain Database Team
 Description : Stores evidence references supporting generated responses.
===============================================================================

DESCRIPTION
-----------
Each row represents ONE evidence reference used to support a generated
response.

A citation links

Response
        │
        ▼
Context Item
        │
        ▼
Chunk / Image / Table / Structured Record

This enables explainable AI by allowing every generated answer to reference
its supporting evidence.

This table intentionally does NOT duplicate document metadata, page numbers,
or source content. Those remain in the Knowledge and Structured schemas.

DEPENDENCIES
------------
query_engine.responses
query_engine.context_items
public.update_updated_at_column()

REFERENCED BY
-------------
query_engine.feedback

===============================================================================
*/

SET search_path TO query_engine, public;

-- ============================================================================
-- TABLE : citations
-- ============================================================================

CREATE TABLE IF NOT EXISTS query_engine.citations
(

    ---------------------------------------------------------------------------
    -- Primary Key
    ---------------------------------------------------------------------------

    citation_id UUID PRIMARY KEY
        DEFAULT uuid_generate_v4(),

    ---------------------------------------------------------------------------
    -- Relationships
    ---------------------------------------------------------------------------

    response_id UUID NOT NULL,

    context_item_id UUID NOT NULL,

    ---------------------------------------------------------------------------
    -- Citation Information
    ---------------------------------------------------------------------------

    citation_order INTEGER NOT NULL,

    citation_type VARCHAR(20)
        NOT NULL
        DEFAULT 'DIRECT',

    support_confidence NUMERIC(5,4),

    is_primary BOOLEAN NOT NULL
        DEFAULT FALSE,

    quoted_text TEXT,

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

    ---------------------------------------------------------------------------
    -- Constraints
    ---------------------------------------------------------------------------

    CONSTRAINT chk_citation_order
        CHECK (citation_order > 0),

    CONSTRAINT chk_support_confidence
        CHECK
        (
            support_confidence IS NULL
            OR
            (
                support_confidence >= 0
                AND support_confidence <= 1
            )
        ),

    CONSTRAINT chk_citation_type
        CHECK
        (
            citation_type IN
            (
                'DIRECT',
                'SUPPORTING',
                'BACKGROUND'
            )
        ),


    CONSTRAINT chk_quoted_text
        CHECK
        (
            quoted_text IS NULL
            OR
            length(trim(quoted_text)) > 0
        ),

    ---------------------------------------------------------------------------
    -- Foreign Keys
    ---------------------------------------------------------------------------

    CONSTRAINT fk_citation_response
        FOREIGN KEY (response_id)
        REFERENCES query_engine.responses(response_id)
        ON UPDATE CASCADE
        ON DELETE CASCADE,

    CONSTRAINT fk_citation_context_item
        FOREIGN KEY (context_item_id)
        REFERENCES query_engine.context_items(context_item_id)
        ON UPDATE CASCADE
        ON DELETE CASCADE,

    ---------------------------------------------------------------------------
    -- Unique Constraints
    ---------------------------------------------------------------------------

    CONSTRAINT uq_response_citation_order
        UNIQUE
        (
            response_id,
            citation_order
        )

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
        WHERE conname = 'chk_quoted_text_length'
          AND conrelid = 'query_engine.citations'::regclass
    ) THEN
        ALTER TABLE query_engine.citations
            ADD CONSTRAINT chk_quoted_text_length
            CHECK
            (
                quoted_text IS NULL
                OR
                length(quoted_text) <= 5000
            );
    END IF;
END $$;

-- ============================================================================
-- TABLE COMMENT
-- ============================================================================

COMMENT ON TABLE query_engine.citations IS
'Stores evidence references supporting generated responses. Each citation links a response to a retrieved context item, enabling explainable AI and source attribution.';

-- ============================================================================
-- COLUMN COMMENTS
-- ============================================================================

COMMENT ON COLUMN query_engine.citations.citation_id IS
'Unique identifier of the citation.';

COMMENT ON COLUMN query_engine.citations.response_id IS
'Response supported by this citation.';

COMMENT ON COLUMN query_engine.citations.context_item_id IS
'Retrieved evidence referenced by this citation.';

COMMENT ON COLUMN query_engine.citations.citation_order IS
'Display order of the citation within the response.';

COMMENT ON COLUMN query_engine.citations.citation_type IS
'Relationship between the cited evidence and the generated response.';

COMMENT ON COLUMN query_engine.citations.support_confidence IS
'Confidence score representing how strongly the cited evidence supports the generated response.';

COMMENT ON COLUMN query_engine.citations.is_primary IS
'Indicates whether this citation is considered one of the primary supporting evidence items.';

COMMENT ON COLUMN query_engine.citations.quoted_text IS
'Optional excerpt from the supporting evidence that directly backs the generated response.';

COMMENT ON COLUMN query_engine.citations.metadata IS
'Flexible JSON metadata containing renderer information, highlighting data, evidence annotations, and future citation extensions.';

COMMENT ON COLUMN query_engine.citations.created_at IS
'Timestamp when the citation record was created.';

COMMENT ON COLUMN query_engine.citations.updated_at IS
'Timestamp automatically updated whenever the row changes.';

-- ============================================================================
-- UPDATED_AT TRIGGER
-- ============================================================================

DROP TRIGGER IF EXISTS trg_citations_updated_at ON query_engine.citations;

CREATE TRIGGER trg_citations_updated_at
BEFORE UPDATE
ON query_engine.citations
FOR EACH ROW
EXECUTE FUNCTION public.update_updated_at_column();

