from __future__ import annotations

from sqlalchemy import text

from backend.database.connection import engine


def get_dataset_schema(
    dataset_name: str | None = None,
) -> list[dict]:
    """
    Retrieve structured dataset metadata for SQL generation.

    If dataset_name is provided, return only that dataset.
    Otherwise return all active datasets.
    """

    query = text(
        """
        SELECT
            d.dataset_id,
            d.dataset_name,
            d.display_name AS dataset_display_name,
            d.description AS dataset_description,
            d.database_name,
            d.database_schema,
            d.database_engine,

            t.table_id,
            t.table_name,
            t.display_name AS table_display_name,
            t.description AS table_description,

            c.column_id,
            c.column_name,
            c.column_display_name,
            c.description AS column_description,
            c.ordinal_position,
            c.logical_data_type,
            c.physical_data_type,
            c.is_nullable,
            c.is_primary_key,
            c.is_foreign_key,
            c.is_unique,
            c.semantic_role,
            c.sample_value

        FROM structured.datasets d

        JOIN structured.dataset_tables t
            ON t.dataset_id = d.dataset_id

        JOIN structured.dataset_columns c
            ON c.table_id = t.table_id

        WHERE d.dataset_status = 'active'
          AND t.table_status = 'ACTIVE'
          AND c.column_status = 'ACTIVE'

          AND (
              CAST(:dataset_name AS TEXT) IS NULL
              OR d.dataset_name = CAST(:dataset_name AS TEXT)
              OR d.display_name = CAST(:dataset_name AS TEXT)
          )

        ORDER BY
            d.dataset_name,
            t.table_name,
            c.ordinal_position
        """
    )

    with engine.connect() as connection:
        rows = connection.execute(
            query,
            {
                "dataset_name": dataset_name,
            },
        ).mappings().all()

    return [dict(row) for row in rows]


def get_latest_dataset_schema() -> list[dict]:
    """
    Return the most recently created active dataset schema.
    """

    query = text(
        """
        SELECT dataset_name
        FROM structured.datasets
        WHERE dataset_status = 'active'
        ORDER BY created_at DESC
        LIMIT 1
        """
    )

    with engine.connect() as connection:
        dataset_name = connection.execute(
            query
        ).scalar_one_or_none()

    if not dataset_name:
        return []

    return get_dataset_schema(dataset_name)