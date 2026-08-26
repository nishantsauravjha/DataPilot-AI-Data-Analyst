from __future__ import annotations

from typing import Any

import pandas as pd


NUMERIC_TYPES = (
    "int",
    "float",
    "complex",
    "decimal",
)


def _is_numeric(series: pd.Series) -> bool:
    return pd.api.types.is_numeric_dtype(series)


def _is_datetime(series: pd.Series) -> bool:
    return pd.api.types.is_datetime64_any_dtype(series)


def select_chart(
    dataframe: pd.DataFrame,
) -> dict[str, Any]:

    if dataframe is None:
        return {
            "type": "table",
            "x": None,
            "y": None,
            "title": "Query Results",
            "reason": "No dataframe was provided.",
        }

    if dataframe.empty:
        return {
            "type": "table",
            "x": None,
            "y": None,
            "title": "No Results",
            "reason": "The query returned no rows.",
        }

    columns = list(
        dataframe.columns
    )

    numeric_columns = [
        column
        for column in columns
        if _is_numeric(
            dataframe[column]
        )
    ]

    datetime_columns = [
        column
        for column in columns
        if _is_datetime(
            dataframe[column]
        )
    ]

    categorical_columns = [
        column
        for column in columns
        if column not in numeric_columns
        and column not in datetime_columns
    ]

    row_count = len(dataframe)

    # --------------------------------------------------------
    # Time series
    # --------------------------------------------------------

    if datetime_columns and numeric_columns:
        x = datetime_columns[0]
        y = numeric_columns[0]

        return {
            "type": "line",
            "x": str(x),
            "y": str(y),
            "title": f"{y} over time",
            "reason": (
                "Datetime and numeric columns "
                "form a natural time-series chart."
            ),
        }

    # --------------------------------------------------------
    # Category + numeric
    # --------------------------------------------------------

    if categorical_columns and numeric_columns:

        x = categorical_columns[0]
        y = numeric_columns[0]

        unique_count = (
            dataframe[x]
            .nunique(dropna=True)
        )

        # Bar charts are ideal for grouped
        # categorical comparisons.
        if 1 <= unique_count <= 30:

            return {
                "type": "bar",
                "x": str(x),
                "y": str(y),
                "title": f"{y} by {x}",
                "reason": (
                    "A categorical dimension and numeric "
                    "measure are suitable for comparison."
                ),
            }

    # --------------------------------------------------------
    # Two numeric columns
    # --------------------------------------------------------

    if len(numeric_columns) >= 2:

        return {
            "type": "scatter",
            "x": str(numeric_columns[0]),
            "y": str(numeric_columns[1]),
            "title": (
                f"{numeric_columns[1]} vs "
                f"{numeric_columns[0]}"
            ),
            "reason": (
                "Two numeric measures can be compared "
                "using a scatter plot."
            ),
        }

    # --------------------------------------------------------
    # Single numeric result
    # --------------------------------------------------------

    if len(numeric_columns) == 1:

        column = numeric_columns[0]

        return {
            "type": "metric",
            "x": None,
            "y": str(column),
            "title": str(column),
            "reason": (
                "A single numeric value is best "
                "displayed as a metric."
            ),
        }

    # --------------------------------------------------------
    # Default
    # --------------------------------------------------------

    return {
        "type": "table",
        "x": None,
        "y": None,
        "title": "Query Results",
        "reason": (
            "No suitable visualization detected."
        ),
    }