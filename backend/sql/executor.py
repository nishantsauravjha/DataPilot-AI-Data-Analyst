from __future__ import annotations

from decimal import Decimal

import pandas as pd
from sqlalchemy import text

from backend.database.connection import engine
from backend.sql.validator import validate_sql


MAX_ROWS = 10000


def _normalize_dataframe_types(
    dataframe: pd.DataFrame,
) -> pd.DataFrame:
    """
    Normalize SQLAlchemy/PostgreSQL scalar types into
    predictable Pandas dtypes.

    PostgreSQL aggregate functions such as SUM() can
    return Decimal values. Pandas stores Decimal columns
    as object dtype, which prevents downstream analysis
    and visualization from recognizing them as numeric.

    This function converts Decimal-only numeric columns
    into float64 while preserving genuine strings,
    dates, booleans, and other values.
    """

    if dataframe.empty:
        return dataframe

    result = dataframe.copy()

    for column in result.columns:

        series = result[column]

        # Already numeric: nothing to do.
        if pd.api.types.is_numeric_dtype(series):
            continue

        # Already datetime: preserve it.
        if pd.api.types.is_datetime64_any_dtype(
            series
        ):
            continue

        non_null = series.dropna()

        if non_null.empty:
            continue

        # ----------------------------------------------------
        # PostgreSQL NUMERIC / DECIMAL
        # ----------------------------------------------------

        if all(
            isinstance(value, Decimal)
            for value in non_null
        ):
            result[column] = pd.to_numeric(
                series,
                errors="coerce",
            )

            continue

        # ----------------------------------------------------
        # Mixed numeric values
        # ----------------------------------------------------

        if all(
            isinstance(
                value,
                (
                    int,
                    float,
                    Decimal,
                ),
            )
            for value in non_null
        ):
            result[column] = pd.to_numeric(
                series,
                errors="coerce",
            )

            continue

    return result


def execute_query(
    sql: str,
) -> pd.DataFrame:
    """
    Validate and execute a read-only SQL query.

    Returns:
        A Pandas DataFrame with normalized SQL types.

    Notes:
        - SQL is validated before execution.
        - Maximum returned rows are capped at MAX_ROWS.
        - PostgreSQL Decimal values are normalized into
          numeric Pandas dtypes for analysis/charting.
    """

    safe_sql = validate_sql(sql)

    with engine.connect() as connection:

        result = connection.execute(
            text(safe_sql)
        )

        rows = result.fetchmany(
            MAX_ROWS
        )

        dataframe = pd.DataFrame(
            rows,
            columns=result.keys(),
        )

    return _normalize_dataframe_types(
        dataframe
    )