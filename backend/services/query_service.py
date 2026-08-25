from __future__ import annotations

from backend.sql.executor import execute_query
from backend.sql.schema_formatter import format_schema
from backend.sql.schema_retriever import get_latest_dataset_schema


def execute_dataset_query(
    sql: str,
) -> dict:
    """
    Execute a validated DataPilot SQL query
    and return structured results.
    """

    dataframe = execute_query(sql)

    return {
        "columns": list(dataframe.columns),
        "rows": dataframe.to_dict(
            orient="records"
        ),
        "row_count": len(dataframe),
    }


def get_latest_schema_context() -> str:
    """
    Return formatted schema context for the SQL agent.
    """

    schema = get_latest_dataset_schema()

    return format_schema(schema)