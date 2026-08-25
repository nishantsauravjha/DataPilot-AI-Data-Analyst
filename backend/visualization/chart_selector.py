from __future__ import annotations

from typing import Any

import pandas as pd


SUPPORTED_CHART_TYPES = {
    "bar",
    "line",
    "scatter",
    "pie",
    "table",
    "metric",
}


def _display_name(column: str) -> str:
    """
    Convert a database-style column name into a human-readable label.
    """

    return (
        column.replace("_", " ")
        .strip()
        .title()
    )


def _is_datetime_column(series: pd.Series) -> bool:
    """
    Determine whether a column represents datetime values.
    """

    if pd.api.types.is_datetime64_any_dtype(series):
        return True

    if pd.api.types.is_object_dtype(series):
        converted = pd.to_datetime(
            series,
            errors="coerce",
        )

        if len(series) == 0:
            return False

        return converted.notna().mean() >= 0.8

    return False


def _numeric_columns(df: pd.DataFrame) -> list[str]:
    return [
        str(column)
        for column in df.select_dtypes(
            include="number"
        ).columns
    ]


def _categorical_columns(df: pd.DataFrame) -> list[str]:
    return [
        str(column)
        for column in df.select_dtypes(
            include=[
                "object",
                "str",
                "category",
                "bool",
            ]
        ).columns
    ]


def _datetime_columns(df: pd.DataFrame) -> list[str]:
    columns: list[str] = []

    for column in df.columns:
        if _is_datetime_column(df[column]):
            columns.append(str(column))

    return columns


def _choose_categorical_column(
    df: pd.DataFrame,
) -> str | None:
    """
    Select the most useful categorical column.

    Preference is given to columns with a reasonable
    number of unique values.
    """

    candidates = _categorical_columns(df)

    if not candidates:
        return None

    # Prefer columns with between 2 and 20 categories.
    reasonable = [
        column
        for column in candidates
        if 2 <= df[column].nunique(dropna=True) <= 20
    ]

    if reasonable:
        return reasonable[0]

    return candidates[0]


def _choose_numeric_column(
    df: pd.DataFrame,
) -> str | None:
    """
    Choose the first numeric metric column.
    """

    numeric = _numeric_columns(df)

    if not numeric:
        return None

    return numeric[0]


def _make_title(
    chart_type: str,
    x: str | None,
    y: str | None,
) -> str:

    if chart_type == "metric":
        return _display_name(y or "Value")

    if chart_type == "pie":
        return f"{_display_name(y or 'Value')} by {_display_name(x or 'Category')}"

    if chart_type == "line":
        return f"{_display_name(y or 'Value')} Over Time"

    if chart_type == "scatter":
        return (
            f"{_display_name(y or 'Value')} "
            f"vs {_display_name(x or 'Value')}"
        )

    if chart_type == "bar":
        return (
            f"{_display_name(y or 'Value')} "
            f"by {_display_name(x or 'Category')}"
        )

    return "Query Results"


def select_chart(
    df: pd.DataFrame,
    *,
    max_categories_for_pie: int = 8,
) -> dict[str, Any]:
    """
    Automatically choose the most appropriate visualization
    for a SQL result DataFrame.

    The function returns a chart specification rather than
    a Plotly figure.

    This keeps visualization rendering separate from the API.
    """

    if not isinstance(df, pd.DataFrame):
        raise TypeError(
            "select_chart expects a pandas DataFrame."
        )

    if df.empty:
        return {
            "type": "table",
            "x": None,
            "y": None,
            "title": "Query Results",
            "reason": "The query returned no rows.",
        }

    numeric = _numeric_columns(df)
    categorical = _categorical_columns(df)
    datetime_columns = _datetime_columns(df)

    # --------------------------------------------------------
    # Single scalar result → metric card
    # --------------------------------------------------------

    if (
        len(df) == 1
        and len(df.columns) == 1
        and numeric
    ):
        value_column = numeric[0]

        return {
            "type": "metric",
            "x": None,
            "y": value_column,
            "title": _make_title(
                "metric",
                None,
                value_column,
            ),
            "reason": "Single numeric value.",
        }

    # --------------------------------------------------------
    # Time series → line chart
    # --------------------------------------------------------

    if datetime_columns and numeric:
        x = datetime_columns[0]
        y = numeric[0]

        return {
            "type": "line",
            "x": x,
            "y": y,
            "title": _make_title(
                "line",
                x,
                y,
            ),
            "reason": "Datetime dimension with numeric measure.",
        }

    # --------------------------------------------------------
    # Categorical + numeric → bar / pie
    # --------------------------------------------------------

    if categorical and numeric:
        x = _choose_categorical_column(df)
        y = numeric[0]

        if x is not None:
            category_count = df[x].nunique(
                dropna=True
            )

            if (
                category_count <= max_categories_for_pie
                and len(df) <= 12
            ):
                return {
                    "type": "bar",
                    "x": x,
                    "y": y,
                    "title": _make_title(
                        "bar",
                        x,
                        y,
                    ),
                    "reason": (
                        "Categorical dimension with numeric "
                        "measure."
                    ),
                }

            return {
                "type": "bar",
                "x": x,
                "y": y,
                "title": _make_title(
                    "bar",
                    x,
                    y,
                ),
                "reason": (
                    "Categorical dimension with numeric "
                    "measure."
                ),
            }

    # --------------------------------------------------------
    # Two numeric columns → scatter
    # --------------------------------------------------------

    if len(numeric) >= 2:
        x = numeric[0]
        y = numeric[1]

        return {
            "type": "scatter",
            "x": x,
            "y": y,
            "title": _make_title(
                "scatter",
                x,
                y,
            ),
            "reason": "Two numeric measures.",
        }

    # --------------------------------------------------------
    # Numeric-only result → table
    # --------------------------------------------------------

    if numeric:
        return {
            "type": "table",
            "x": None,
            "y": numeric[0],
            "title": "Query Results",
            "reason": "No suitable dimension for a chart.",
        }

    # --------------------------------------------------------
    # Fallback
    # --------------------------------------------------------

    return {
        "type": "table",
        "x": None,
        "y": None,
        "title": "Query Results",
        "reason": "No suitable visualization detected.",
    }


def validate_chart_spec(
    spec: dict[str, Any],
) -> dict[str, Any]:
    """
    Validate a generated chart specification.
    """

    if not isinstance(spec, dict):
        raise TypeError(
            "Chart specification must be a dictionary."
        )

    chart_type = spec.get("type")

    if chart_type not in SUPPORTED_CHART_TYPES:
        raise ValueError(
            f"Unsupported chart type: {chart_type}"
        )

    return spec