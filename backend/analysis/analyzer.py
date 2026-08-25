from __future__ import annotations

from datetime import date, datetime
from decimal import Decimal
from typing import Any

import pandas as pd


def _json_safe(value: Any) -> Any:
    """
    Convert Pandas / database values into JSON-serializable values.
    """

    if value is None:
        return None

    if isinstance(value, (pd.Timestamp, datetime, date)):
        return value.isoformat()

    if isinstance(value, Decimal):
        return float(value)

    if hasattr(value, "item"):
        try:
            return value.item()
        except (ValueError, TypeError):
            pass

    return value


def _clean_records(df: pd.DataFrame) -> list[dict[str, Any]]:
    """
    Convert DataFrame rows into JSON-safe dictionaries.
    """

    records = df.to_dict(orient="records")

    return [
        {
            str(key): _json_safe(value)
            for key, value in record.items()
        }
        for record in records
    ]


def _detect_column_types(
    df: pd.DataFrame,
) -> dict[str, list[str]]:
    """
    Detect useful column categories for downstream analysis.
    """

    numeric_columns = [
        str(column)
        for column in df.select_dtypes(
            include="number"
        ).columns
    ]

    datetime_columns = [
        str(column)
        for column in df.select_dtypes(
            include=["datetime", "datetimetz"]
        ).columns
    ]

    categorical_columns = [
        str(column)
        for column in df.select_dtypes(
            include=["object", "str", "category", "bool"]
        ).columns
        if column not in datetime_columns
    ]

    return {
        "numeric": numeric_columns,
        "categorical": categorical_columns,
        "datetime": datetime_columns,
    }


def _numeric_summary(
    df: pd.DataFrame,
    numeric_columns: list[str],
) -> dict[str, dict[str, Any]]:
    """
    Generate deterministic descriptive statistics.
    """

    summary: dict[str, dict[str, Any]] = {}

    for column in numeric_columns:
        series = pd.to_numeric(
            df[column],
            errors="coerce",
        ).dropna()

        if series.empty:
            continue

        summary[column] = {
            "count": int(series.count()),
            "sum": _json_safe(series.sum()),
            "mean": _json_safe(series.mean()),
            "median": _json_safe(series.median()),
            "min": _json_safe(series.min()),
            "max": _json_safe(series.max()),
        }

    return summary


def _categorical_summary(
    df: pd.DataFrame,
    categorical_columns: list[str],
) -> dict[str, dict[str, Any]]:
    """
    Generate useful summaries for categorical columns.
    """

    summary: dict[str, dict[str, Any]] = {}

    for column in categorical_columns:
        series = df[column].dropna()

        if series.empty:
            continue

        value_counts = series.value_counts()

        top_values = []

        for value, count in value_counts.head(10).items():
            top_values.append(
                {
                    "value": _json_safe(value),
                    "count": int(count),
                }
            )

        summary[column] = {
            "unique_count": int(series.nunique()),
            "top_values": top_values,
        }

    return summary


def _find_extremes(
    df: pd.DataFrame,
    numeric_columns: list[str],
) -> dict[str, dict[str, Any]]:
    """
    Find minimum and maximum values with their corresponding rows.
    """

    extremes: dict[str, dict[str, Any]] = {}

    for column in numeric_columns:
        series = pd.to_numeric(
            df[column],
            errors="coerce",
        )

        valid = series.dropna()

        if valid.empty:
            continue

        max_index = valid.idxmax()
        min_index = valid.idxmin()

        max_row = df.loc[max_index].to_dict()
        min_row = df.loc[min_index].to_dict()

        extremes[column] = {
            "maximum": {
                "value": _json_safe(valid.loc[max_index]),
                "row": {
                    str(key): _json_safe(value)
                    for key, value in max_row.items()
                },
            },
            "minimum": {
                "value": _json_safe(valid.loc[min_index]),
                "row": {
                    str(key): _json_safe(value)
                    for key, value in min_row.items()
                },
            },
        }

    return extremes


def analyze_dataframe(
    df: pd.DataFrame,
    *,
    max_preview_rows: int = 100,
) -> dict[str, Any]:
    """
    Analyze a SQL result DataFrame.

    The analyzer is deterministic and does not call an LLM.

    Returns:
        A JSON-safe analysis payload containing:

        - row_count
        - column_count
        - columns
        - column_types
        - numeric_summary
        - categorical_summary
        - extremes
        - preview
        - empty
    """

    if not isinstance(df, pd.DataFrame):
        raise TypeError(
            "analyze_dataframe expects a pandas DataFrame."
        )

    column_names = [
        str(column)
        for column in df.columns
    ]

    column_types = _detect_column_types(df)

    if df.empty:
        return {
            "row_count": 0,
            "column_count": len(column_names),
            "columns": column_names,
            "column_types": column_types,
            "numeric_summary": {},
            "categorical_summary": {},
            "extremes": {},
            "preview": [],
            "empty": True,
        }

    numeric_summary = _numeric_summary(
        df,
        column_types["numeric"],
    )

    categorical_summary = _categorical_summary(
        df,
        column_types["categorical"],
    )

    extremes = _find_extremes(
        df,
        column_types["numeric"],
    )

    preview_df = df.head(max_preview_rows)

    return {
        "row_count": int(len(df)),
        "column_count": int(len(column_names)),
        "columns": column_names,
        "column_types": column_types,
        "numeric_summary": numeric_summary,
        "categorical_summary": categorical_summary,
        "extremes": extremes,
        "preview": _clean_records(preview_df),
        "empty": False,
    }