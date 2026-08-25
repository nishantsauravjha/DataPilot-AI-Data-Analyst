from __future__ import annotations

import pandas as pd


def infer_logical_type(series: pd.Series) -> str:
    """
    Map a pandas Series to one of the logical types
    supported by structured.dataset_columns.
    """

    dtype = series.dtype

    if pd.api.types.is_bool_dtype(dtype):
        return "BOOLEAN"

    if pd.api.types.is_integer_dtype(dtype):
        return "INTEGER"

    if pd.api.types.is_float_dtype(dtype):
        return "DECIMAL"

    if pd.api.types.is_datetime64_any_dtype(dtype):
        return "DATETIME"

    if pd.api.types.is_string_dtype(dtype):
        return "STRING"

    return "OTHER"


def infer_semantic_role(
    column_name: str,
    series: pd.Series,
) -> str | None:
    """
    Lightweight semantic-role inference.

    This is intentionally heuristic for the MVP.
    The LLM-based semantic layer can be added later.
    """

    name = column_name.lower()

    if "id" == name or name.endswith("_id"):
        return "IDENTIFIER"

    if any(
        keyword in name
        for keyword in ("date", "time", "timestamp")
    ):
        return "DATETIME"

    if any(
        keyword in name
        for keyword in ("revenue", "sales", "amount", "price", "cost", "profit")
    ):
        return "MEASURE"

    if any(
        keyword in name
        for keyword in ("name", "category", "region", "country", "city", "product")
    ):
        return "DIMENSION"

    return None


def profile_dataframe(df: pd.DataFrame) -> list[dict]:
    """
    Generate column-level metadata for a DataFrame.
    """

    profiles = []

    for position, column in enumerate(df.columns, start=1):
        series = df[column]

        non_null = series.dropna()

        sample_value = None

        if not non_null.empty:
            sample_value = str(non_null.iloc[0])

        profiles.append(
            {
                "column_name": str(column),
                "ordinal_position": position,
                "logical_data_type": infer_logical_type(series),
                "physical_data_type": str(series.dtype),
                "is_nullable": bool(series.isna().any()),
                "is_unique": bool(series.nunique(dropna=True) == len(non_null)),
                "sample_value": sample_value,
                "semantic_role": infer_semantic_role(
                    str(column),
                    series,
                ),
            }
        )

    return profiles