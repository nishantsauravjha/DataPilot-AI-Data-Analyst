from __future__ import annotations

from datetime import date, datetime
from decimal import Decimal
from typing import Any

import numpy as np
import pandas as pd

from backend.sql.executor import execute_query
from backend.sql.schema_formatter import format_schema
from backend.sql.schema_retriever import get_latest_dataset_schema


def _json_safe(value: Any) -> Any:

    if value is None:
        return None

    if isinstance(
        value,
        (
            pd.Timestamp,
            datetime,
            date,
        ),
    ):
        return value.isoformat()

    if isinstance(value, Decimal):
        return float(value)

    if isinstance(value, np.integer):
        return int(value)

    if isinstance(value, np.floating):
        value = float(value)

        if np.isnan(value) or np.isinf(value):
            return None

        return value

    if isinstance(value, np.bool_):
        return bool(value)

    if isinstance(value, float):

        if np.isnan(value) or np.isinf(value):
            return None

        return value

    if isinstance(value, np.ndarray):
        return [
            _json_safe(item)
            for item in value.tolist()
        ]

    if isinstance(value, dict):
        return {
            str(key): _json_safe(item)
            for key, item in value.items()
        }

    if isinstance(value, (list, tuple)):
        return [
            _json_safe(item)
            for item in value
        ]

    return value


def _clean_dataframe(
    dataframe: pd.DataFrame,
) -> pd.DataFrame:

    result = dataframe.copy()

    for column in result.columns:

        series = result[column]

        if pd.api.types.is_numeric_dtype(
            series
        ):
            continue

        if pd.api.types.is_datetime64_any_dtype(
            series
        ):
            continue

        if series.dtype == object:

            non_null = series.dropna()

            if non_null.empty:
                continue

            converted = pd.to_numeric(
                non_null,
                errors="coerce",
            )

            if converted.notna().all():

                result[column] = pd.to_numeric(
                    series,
                    errors="coerce",
                )

    return result


def execute_dataset_query(
    sql: str,
) -> dict[str, Any]:

    dataframe = execute_query(
        sql
    )

    dataframe = _clean_dataframe(
        dataframe
    )

    rows = dataframe.to_dict(
        orient="records"
    )

    return {
        "columns": [
            str(column)
            for column in dataframe.columns
        ],
        "rows": [
            _json_safe(row)
            for row in rows
        ],
        "row_count": int(
            len(dataframe)
        ),
    }


def get_latest_schema_context() -> str:

    schema = (
        get_latest_dataset_schema()
    )

    return format_schema(
        schema
    )