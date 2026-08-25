/*
===============================================================================
 OmniBrain Database Project
 Module      : Query Engine
 File        : 09_feedback.sql
 Schema      : query_engine
 Author      : OmniBrain Database Team
 Description : Stores human and automated evaluations of generated responses.
===============================================================================

DESCRIPTION
-----------
Each row represents ONE evaluation submitted for ONE generated response.

Feedback may originate from:

• End Users
• AI Evaluators
• Administrators
• Internal System Processes

A response may have multiple feedback records representing different
evaluation dimensions such as accuracy, relevance, completeness, or safety.

This table intentionally stores evaluation metadata only.

DEPENDENCIES
------------
query_engine.responses
auth.auth.users
public.update_updated_at_column()

===============================================================================
*/

SET search_path TO query_engine, public;

-- ============================================================================
-- TABLE : feedback
-- ============================================================================

CREATE TABLE IF NOT EXISTS query_engine.feedback
(

    ---------------------------------------------------------------------------
    -- Primary Key
    ---------------------------------------------------------------------------

    feedback_id UUID PRIMARY KEY
        DEFAULT uuid_generate_v4(),

    ---------------------------------------------------------------------------
    -- Relationships
    ---------------------------------------------------------------------------

    response_id UUID NOT NULL,

    user_id UUID,

    ---------------------------------------------------------------------------
    -- Feedback Information
    ---------------------------------------------------------------------------

    feedback_source VARCHAR(20)
        NOT NULL,

    feedback_type VARCHAR(30)
        NOT NULL,

    rating SMALLINT,

    is_helpful BOOLEAN,

    evaluation_label VARCHAR(30),

    comment TEXT,

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

    CONSTRAINT chk_feedback_source
        CHECK
        (
            feedback_source IN
            (
                'USER',
                'LLM',
                'ADMIN',
                'SYSTEM'
            )
        ),

    CONSTRAINT chk_feedback_type
        CHECK
        (
            feedback_type IN
            (
                'OVERALL',
                'ACCURACY',
                'RELEVANCE',
                'COMPLETENESS',
                'CITATIONS',
                'SAFETY'
            )
        ),

    CONSTRAINT chk_rating
        CHECK
        (
            rating IS NULL
            OR
            rating BETWEEN 1 AND 5
        ),

    CONSTRAINT chk_feedback_signal
        CHECK
        (
            rating IS NOT NULL
            OR
            is_helpful IS NOT NULL
        ),

    CONSTRAINT chk_evaluation_label
        CHECK
        (
            evaluation_label IS NULL
            OR
            length(trim(evaluation_label)) > 0
        ),

    CONSTRAINT chk_comment
        CHECK
        (
            comment IS NULL
            OR
            length(trim(comment)) > 0
        ),

    ---------------------------------------------------------------------------
    -- Foreign Keys
    ---------------------------------------------------------------------------

    CONSTRAINT fk_feedback_response
        FOREIGN KEY (response_id)
        REFERENCES query_engine.responses(response_id)
        ON UPDATE CASCADE
        ON DELETE CASCADE,

    CONSTRAINT fk_feedback_user
        FOREIGN KEY (user_id)
        REFERENCES auth.users(user_id)
        ON UPDATE CASCADE
        ON DELETE SET NULL,

    ---------------------------------------------------------------------------
    -- Unique Constraints
    ---------------------------------------------------------------------------

    CONSTRAINT uq_feedback_dimension
        UNIQUE
        (
            response_id,
            user_id,
            feedback_type
        )

)

WITH
(
    fillfactor = 90
);



-- ============================================================================
-- TABLE COMMENT
-- ============================================================================

COMMENT ON TABLE query_engine.feedback IS
'Stores human and automated evaluations for generated responses. Each row represents a single evaluation submitted by a user, administrator, AI evaluator, or internal system.';

-- ============================================================================
-- COLUMN COMMENTS
-- ============================================================================

COMMENT ON COLUMN query_engine.feedback.feedback_id IS
'Unique identifier of the feedback record.';

COMMENT ON COLUMN query_engine.feedback.response_id IS
'Generated response being evaluated.';

COMMENT ON COLUMN query_engine.feedback.user_id IS
'User who submitted the feedback. NULL indicates automated or system-generated evaluation.';

COMMENT ON COLUMN query_engine.feedback.feedback_source IS
'Origin of the evaluation (USER, LLM, ADMIN, or SYSTEM).';

COMMENT ON COLUMN query_engine.feedback.feedback_type IS
'Aspect of the response being evaluated, such as accuracy or relevance.';

COMMENT ON COLUMN query_engine.feedback.rating IS
'Optional star rating ranging from 1 (lowest) to 5 (highest).';

COMMENT ON COLUMN query_engine.feedback.is_helpful IS
'Optional binary helpful/not-helpful indicator.';

COMMENT ON COLUMN query_engine.feedback.evaluation_label IS
'Optional qualitative assessment such as EXCELLENT, GOOD, FAIR, or POOR.';

COMMENT ON COLUMN query_engine.feedback.comment IS
'Optional textual explanation provided with the evaluation.';

COMMENT ON COLUMN query_engine.feedback.metadata IS
'Flexible JSON metadata storing evaluator-specific information, evaluation context, reasoning details, client information, and future extensions.';

COMMENT ON COLUMN query_engine.feedback.created_at IS
'Timestamp when the feedback record was created.';

COMMENT ON COLUMN query_engine.feedback.updated_at IS
'Timestamp automatically updated whenever the row changes.';

-- ============================================================================
-- UPDATED_AT TRIGGER
-- ============================================================================

DROP TRIGGER IF EXISTS trg_feedback_updated_at ON query_engine.feedback;

CREATE TRIGGER trg_feedback_updated_at
BEFORE UPDATE
ON query_engine.feedback
FOR EACH ROW
EXECUTE FUNCTION public.update_updated_at_column();