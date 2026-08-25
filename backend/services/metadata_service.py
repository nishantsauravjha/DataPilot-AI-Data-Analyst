from __future__ import annotations

from datetime import datetime, timezone
from uuid import UUID

from sqlalchemy import text

from backend.database.connection import engine


def create_data_source(
    source_name: str,
    source_type: str,
    connection_identifier: str,
    description: str | None = None,
) -> UUID:
    """
    Register a structured data source.
    """

    query = text(
        """
        INSERT INTO structured.data_sources (
            source_name,
            source_type,
            connection_mode,
            connection_identifier,
            description
        )
        VALUES (
            :source_name,
            :source_type,
            'LOCAL',
            :connection_identifier,
            :description
        )
        RETURNING source_id
        """
    )

    with engine.begin() as connection:
        result = connection.execute(
            query,
            {
                "source_name": source_name,
                "source_type": source_type,
                "connection_identifier": connection_identifier,
                "description": description,
            },
        )

        return result.scalar_one()


def create_dataset(
    source_id: UUID,
    dataset_name: str,
    display_name: str,
    database_name: str,
    database_schema: str,
    database_engine: str,
    description: str | None = None,
) -> UUID:
    """
    Register a dataset in structured.datasets.
    """

    query = text(
        """
        INSERT INTO structured.datasets (
            source_id,
            dataset_name,
            display_name,
            description,
            database_name,
            database_schema,
            dataset_type,
            database_engine,
            dataset_status,
            dataset_version,
            last_synced_at
        )
        VALUES (
            :source_id,
            :dataset_name,
            :display_name,
            :description,
            :database_name,
            :database_schema,
            :dataset_type,
            :database_engine,
            'active',
            '1.0',
            :last_synced_at
        )
        RETURNING dataset_id
        """
    )

    with engine.begin() as connection:
        result = connection.execute(
            query,
            {
                "source_id": source_id,
                "dataset_name": dataset_name,
                "display_name": display_name,
                "description": description,
                "database_name": database_name,
                "database_schema": database_schema,
                "dataset_type": "analytics",
                "database_engine": database_engine,
                "last_synced_at": datetime.now(timezone.utc),
            },
        )

        return result.scalar_one()


def create_dataset_table(
    dataset_id: UUID,
    table_name: str,
    table_schema: str,
) -> UUID:
    """
    Register a physical table in structured.dataset_tables.
    """

    query = text(
        """
        INSERT INTO structured.dataset_tables (
            dataset_id,
            table_name,
            display_name,
            table_schema,
            table_type,
            table_status,
            last_synced_at
        )
        VALUES (
            :dataset_id,
            :table_name,
            :display_name,
            :table_schema,
            'BASE_TABLE',
            'ACTIVE',
            :last_synced_at
        )
        RETURNING table_id
        """
    )

    with engine.begin() as connection:
        result = connection.execute(
            query,
            {
                "dataset_id": dataset_id,
                "table_name": table_name,
                "display_name": table_name.replace("_", " ").title(),
                "table_schema": table_schema,
                "last_synced_at": datetime.now(timezone.utc),
            },
        )

        return result.scalar_one()


def create_dataset_columns(
    table_id: UUID,
    column_profiles: list[dict],
) -> list[UUID]:
    """
    Register DataFrame column metadata.
    """

    query = text(
        """
        INSERT INTO structured.dataset_columns (
            table_id,
            column_name,
            column_display_name,
            ordinal_position,
            logical_data_type,
            physical_data_type,
            is_nullable,
            is_primary_key,
            is_foreign_key,
            is_unique,
            is_indexed,
            semantic_role,
            sample_value,
            is_searchable,
            is_filterable,
            is_sortable,
            column_status,
            last_synced_at
        )
        VALUES (
            :table_id,
            :column_name,
            :column_display_name,
            :ordinal_position,
            :logical_data_type,
            :physical_data_type,
            :is_nullable,
            false,
            false,
            :is_unique,
            false,
            :semantic_role,
            :sample_value,
            true,
            true,
            true,
            'ACTIVE',
            :last_synced_at
        )
        RETURNING column_id
        """
    )

    created_ids = []

    with engine.begin() as connection:
        for profile in column_profiles:
            result = connection.execute(
                query,
                {
                    "table_id": table_id,
                    "column_name": profile["column_name"],
                    "column_display_name": profile["column_name"].replace(
                        "_",
                        " ",
                    ).title(),
                    "ordinal_position": profile["ordinal_position"],
                    "logical_data_type": profile["logical_data_type"],
                    "physical_data_type": profile["physical_data_type"],
                    "is_nullable": profile["is_nullable"],
                    "is_unique": profile["is_unique"],
                    "semantic_role": profile["semantic_role"],
                    "sample_value": profile["sample_value"],
                    "last_synced_at": datetime.now(timezone.utc),
                },
            )

            created_ids.append(result.scalar_one())

    return created_ids