from __future__ import annotations

from dataclasses import dataclass
from typing import Any

import pandas as pd

from backend.core.config import settings
from backend.sql.executor import (
    SQLExecutionError,
    SQLExplainError,
    execute_query,
    explain_query,
)
from backend.sql.generator import (
    correct_sql,
    generate_sql,
)
from backend.sql.schema_formatter import format_schema
from backend.sql.schema_retriever import get_latest_dataset_schema
from backend.sql.validator import validate_sql


@dataclass
class SQLPipelineResult:
    sql: str
    explanation: str
    confidence: float
    dataframe: pd.DataFrame

    attempts: int
    corrected: bool

    explain: dict[str, Any]
    result_check: dict[str, Any]


def _get_schema_context() -> str:
    schema = get_latest_dataset_schema()

    if not schema:
        raise RuntimeError(
            "No dataset schema is available."
        )

    return format_schema(schema)


def _check_result(
    dataframe: pd.DataFrame,
) -> dict[str, Any]:
    """
    Deterministic result sanity check.

    Empty results are valid and are NOT treated as SQL failures.
    """

    if not isinstance(dataframe, pd.DataFrame):
        return {
            "valid": False,
            "empty": False,
            "reason": "SQL executor returned an invalid result.",
        }

    if dataframe.columns.empty:
        return {
            "valid": False,
            "empty": dataframe.empty,
            "reason": "Query returned no columns.",
        }

    if dataframe.empty:
        return {
            "valid": True,
            "empty": True,
            "reason": "Query executed successfully but returned no rows.",
        }

    return {
        "valid": True,
        "empty": False,
        "row_count": len(dataframe),
        "column_count": len(dataframe.columns),
        "columns": [
            str(column)
            for column in dataframe.columns
        ],
    }


def _error_text(exc: Exception) -> str:
    """
    Convert execution/planning errors into a bounded string
    suitable for the correction model.
    """

    message = str(exc).strip()

    # Prevent accidentally sending massive DB traces to the LLM.
    return message[:4000]


def run_sql_pipeline(
    question: str,
) -> SQLPipelineResult:
    """
    Production SQL pipeline.

    Flow:

        Question
          ↓
        Schema
          ↓
        SQL generation
          ↓
        Validation
          ↓
        EXPLAIN
          ↓
        Execute
          ↓
        Result check
          ↓
        Optional correction/retry
    """

    if not question.strip():
        raise ValueError(
            "Question cannot be empty."
        )

    schema = _get_schema_context()

    generated = generate_sql(
        question=question,
        schema=schema,
    )

    sql = generated["sql"]
    explanation = generated["explanation"]
    confidence = float(generated["confidence"])

    max_retries = max(
        0,
        int(settings.SQL_MAX_RETRIES),
    )

    attempts = 0
    corrected = False

    last_error: Exception | None = None
    explain_result: dict[str, Any] = {}

    while attempts <= max_retries:

        attempts += 1

        try:
            # ----------------------------------------------
            # 1. Validate
            # ----------------------------------------------

            sql = validate_sql(sql)

            # ----------------------------------------------
            # 2. EXPLAIN
            # ----------------------------------------------

            if settings.SQL_EXPLAIN_ENABLED:
                explain_result = explain_query(sql)
            else:
                explain_result = {
                    "valid": True,
                    "plan_available": False,
                    "plan": None,
                }

            # ----------------------------------------------
            # 3. Execute
            # ----------------------------------------------

            dataframe = execute_query(sql)

            # ----------------------------------------------
            # 4. Check result
            # ----------------------------------------------

            result_check = _check_result(dataframe)

            if not result_check["valid"]:
                raise SQLExecutionError(
                    result_check["reason"]
                )

            return SQLPipelineResult(
                sql=sql,
                explanation=explanation,
                confidence=confidence,
                dataframe=dataframe,
                attempts=attempts,
                corrected=corrected,
                explain=explain_result,
                result_check=result_check,
            )

        except (
            ValueError,
            SQLExplainError,
            SQLExecutionError,
        ) as exc:

            last_error = exc

            if attempts > max_retries:
                break

            corrected_result = correct_sql(
                question=question,
                schema=schema,
                previous_sql=sql,
                error=_error_text(exc),
            )

            sql = corrected_result["sql"]
            explanation = corrected_result["explanation"]
            confidence = float(
                corrected_result["confidence"]
            )

            corrected = True

    raise RuntimeError(
        "SQL pipeline failed after "
        f"{attempts} attempt(s): "
        f"{_error_text(last_error) if last_error else 'unknown error'}"
    )