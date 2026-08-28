from __future__ import annotations

from typing import Any

import pandas as pd
from sqlalchemy import text

from backend.core.config import settings
from backend.database.connection import engine
from backend.sql.validator import validate_sql


MAX_ROWS = settings.SQL_MAX_ROWS


class SQLExecutionError(RuntimeError):
    """Raised when a validated SQL query cannot be executed."""


class SQLExplainError(RuntimeError):
    """Raised when PostgreSQL cannot plan a validated SQL query."""


def _validated_sql(sql: str) -> str:
    """
    Validate SQL before it reaches PostgreSQL.
    """

    if not sql or not sql.strip():
        raise ValueError("SQL cannot be empty.")

    return validate_sql(sql)


def explain_query(sql: str) -> dict[str, Any]:
    """
    Ask PostgreSQL to plan the query without executing it.

    EXPLAIN is performed only after SQL validation.

    Returns a small structured payload rather than exposing
    PostgreSQL's complete internal plan to callers.
    """

    safe_sql = _validated_sql(sql)

    explain_sql = f"""
    EXPLAIN (FORMAT JSON)
    {safe_sql}
    """

    try:
        with engine.connect() as connection:
            connection.execute(
                text(
                    f"SET LOCAL statement_timeout = "
                    f"{int(settings.SQL_STATEMENT_TIMEOUT_MS)}"
                )
            )

            result = connection.execute(text(explain_sql))

            row = result.fetchone()

            if row is None:
                raise SQLExplainError(
                    "PostgreSQL returned an empty EXPLAIN plan."
                )

            raw_plan = row[0]

            return {
                "valid": True,
                "plan_available": True,
                "plan": raw_plan,
            }

    except Exception as exc:
        raise SQLExplainError(
            f"SQL EXPLAIN failed: {exc}"
        ) from exc


def execute_query(sql: str) -> pd.DataFrame:
    """
    Validate and execute a read-only SQL query.

    A statement timeout is applied for safety.

    Returns:
        Pandas DataFrame containing at most MAX_ROWS rows.
    """

    safe_sql = _validated_sql(sql)

    try:
        with engine.connect() as connection:
            connection.execute(
                text(
                    f"SET LOCAL statement_timeout = "
                    f"{int(settings.SQL_STATEMENT_TIMEOUT_MS)}"
                )
            )

            result = connection.execute(
                text(safe_sql)
            )

            rows = result.fetchmany(MAX_ROWS)

            dataframe = pd.DataFrame(
                rows,
                columns=result.keys(),
            )

            return _normalize_dataframe_types(dataframe)

    except Exception as exc:
        raise SQLExecutionError(
            f"SQL execution failed: {exc}"
        ) from exc


def _normalize_dataframe_types(
    dataframe: pd.DataFrame,
) -> pd.DataFrame:
    """
    Normalize PostgreSQL values into useful Pandas dtypes.

    PostgreSQL NUMERIC/DECIMAL values commonly arrive as
    Decimal objects and therefore appear as object dtype.
    This converts numeric-like columns into real numeric
    Pandas dtypes.

    Datetime-like object columns are also normalized where
    conversion is unambiguous.
    """

    dataframe = dataframe.copy()

    for column in dataframe.columns:
        series = dataframe[column]

        if series.empty:
            continue

        # ----------------------------------------------------
        # Numeric normalization
        # ----------------------------------------------------
        #
        # PostgreSQL NUMERIC/DECIMAL values can arrive as
        # Decimal objects inside an object-dtype Series.
        #
        if series.dtype == "object":
            numeric = pd.to_numeric(
                series,
                errors="coerce",
            )

            if numeric.notna().all():
                dataframe[column] = numeric
                continue

        # ----------------------------------------------------
        # Datetime normalization
        # ----------------------------------------------------

        if series.dtype == "object":
            try:
                parsed = pd.to_datetime(
                    series,
                    errors="raise",
                )

                if not parsed.isna().all():
                    dataframe[column] = parsed

            except (TypeError, ValueError):
                pass

    return dataframe


# Backward-compatible internal alias.
#
# Some existing code may already use the shorter helper name.
_normalize_dataframe = _normalize_dataframe_types