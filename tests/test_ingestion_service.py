from pathlib import Path

import pandas as pd
from sqlalchemy import text

from backend.services.ingestion_service import ingest_dataset
from backend.database.connection import engine


def test_ingest_dataset(tmp_path: Path):
    file_path = tmp_path / "sales.csv"

    df = pd.DataFrame(
        {
            "Product Name": ["iPhone", "MacBook", "AirPods"],
            "Quantity": [10, 5, 20],
            "Revenue": [1000.0, 2500.0, 1500.0],
        }
    )

    df.to_csv(file_path, index=False)

    result = ingest_dataset(file_path)

    assert result["source_type"] == "CSV"
    assert result["rows"] == 3
    assert result["columns"] == 3
    assert result["table_name"] == "sales"

    try:
        with engine.connect() as connection:
            count = connection.execute(
                text(
                    'SELECT COUNT(*) '
                    'FROM "uploaded_data"."sales"'
                )
            ).scalar()

            assert count == 3

    finally:
        with engine.begin() as connection:
            connection.execute(
                text(
                    'DROP TABLE IF EXISTS '
                    '"uploaded_data"."sales"'
                )
            )

            connection.execute(
                text(
                    """
                    DELETE FROM structured.data_sources
                    WHERE source_name = :source_name
                    """
                ),
                {"source_name": "sales.csv"},
            )