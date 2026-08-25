from __future__ import annotations

import re

import pandas as pd
from sqlalchemy import text

from backend.database.connection import engine


PHYSICAL_SCHEMA = "uploaded_data"


def sanitize_identifier(value: str) -> str:
    """
    Convert an arbitrary column/table name into a safe PostgreSQL identifier.
    """

    value = str(value).strip().lower()

    value = re.sub(r"[^a-zA-Z0-9_]+", "_", value)
    value = re.sub(r"_+", "_", value)
    value = value.strip("_")

    if not value:
        value = "column"

    if value[0].isdigit():
        value = f"col_{value}"

    return value[:63]


def make_unique_identifiers(names: list[str]) -> list[str]:
    """
    Ensure PostgreSQL identifiers are unique.
    """

    result = []
    counts: dict[str, int] = {}

    for name in names:
        base = sanitize_identifier(name)

        if base not in counts:
            counts[base] = 0
            result.append(base)
            continue

        counts[base] += 1
        candidate = f"{base}_{counts[base]}"

        while candidate in result:
            counts[base] += 1
            candidate = f"{base}_{counts[base]}"

        result.append(candidate)

    return result


def infer_postgres_type(series: pd.Series) -> str:
    """
    Convert a pandas Series into a PostgreSQL column type.
    """

    dtype = series.dtype

    if pd.api.types.is_bool_dtype(dtype):
        return "BOOLEAN"

    if pd.api.types.is_integer_dtype(dtype):
        return "BIGINT"

    if pd.api.types.is_float_dtype(dtype):
        return "DOUBLE PRECISION"

    if pd.api.types.is_datetime64_any_dtype(dtype):
        return "TIMESTAMP"

    return "TEXT"


def create_physical_table(
    df: pd.DataFrame,
    table_name: str,
) -> tuple[str, list[str]]:
    """
    Create a physical PostgreSQL table for an uploaded DataFrame.

    Returns:
        (sanitized_table_name, sanitized_column_names)
    """

    physical_table = sanitize_identifier(table_name)
    columns = make_unique_identifiers(list(df.columns))

    column_definitions = []

    for original_column, column_name in zip(df.columns, columns):
        postgres_type = infer_postgres_type(df[original_column])

        column_definitions.append(
            f'"{column_name}" {postgres_type}'
        )

    create_sql = f'''
        CREATE TABLE IF NOT EXISTS "{PHYSICAL_SCHEMA}"."{physical_table}" (
            {", ".join(column_definitions)}
        )
    '''

    with engine.begin() as connection:
        connection.execute(text(create_sql))

    return physical_table, columns


def insert_dataframe(
    df: pd.DataFrame,
    table_name: str,
    column_names: list[str],
) -> int:
    """
    Insert DataFrame rows into the physical PostgreSQL table.
    """

    if df.empty:
        return 0

    upload_df = df.copy()
    upload_df.columns = column_names

    upload_df.to_sql(
        name=table_name,
        con=engine,
        schema=PHYSICAL_SCHEMA,
        if_exists="append",
        index=False,
        method="multi",
    )

    return len(upload_df)