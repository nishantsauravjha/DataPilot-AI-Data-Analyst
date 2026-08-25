import pandas as pd
from sqlalchemy import text

from backend.database.connection import engine
from backend.ingestion.profiler import profile_dataframe
from backend.services.metadata_service import (
    create_data_source,
    create_dataset,
    create_dataset_columns,
    create_dataset_table,
)


def test_metadata_registration():
    df = pd.DataFrame(
        {
            "product_name": ["iPhone", "MacBook"],
            "quantity": [10, 5],
            "revenue": [1000.0, 2500.0],
        }
    )

    profiles = profile_dataframe(df)

    source_id = None
    dataset_id = None

    try:
        source_id = create_data_source(
            source_name="test_sales_source",
            source_type="CSV",
            connection_identifier="data/test_sales.csv",
        )

        dataset_id = create_dataset(
            source_id=source_id,
            dataset_name="test_sales",
            display_name="Test Sales",
            database_name="datapilot",
            database_schema="uploaded_data",
            database_engine="csv",
        )

        table_id = create_dataset_table(
            dataset_id=dataset_id,
            table_name="test_sales",
            table_schema="uploaded_data",
        )

        column_ids = create_dataset_columns(
            table_id=table_id,
            column_profiles=profiles,
        )

        assert source_id is not None
        assert dataset_id is not None
        assert table_id is not None
        assert len(column_ids) == 3

    finally:
        # dataset deletion cascades to dataset_tables
        # and dataset_columns.
        if dataset_id is not None:
            with engine.begin() as connection:
                connection.execute(
                    text(
                        """
                        DELETE FROM structured.datasets
                        WHERE dataset_id = :dataset_id
                        """
                    ),
                    {"dataset_id": dataset_id},
                )

        # Remove the parent data source.
        if source_id is not None:
            with engine.begin() as connection:
                connection.execute(
                    text(
                        """
                        DELETE FROM structured.data_sources
                        WHERE source_id = :source_id
                        """
                    ),
                    {"source_id": source_id},
                )