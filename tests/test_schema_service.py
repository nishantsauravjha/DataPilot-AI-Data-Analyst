import pandas as pd
from sqlalchemy import text

from backend.database.connection import engine
from backend.services.schema_service import (
    create_physical_table,
    insert_dataframe,
)


def test_create_and_insert_physical_table():
    df = pd.DataFrame(
        {
            "Product Name": ["iPhone", "MacBook", "AirPods"],
            "Quantity": [10, 5, 20],
            "Revenue": [1000.0, 2500.0, 1500.0],
        }
    )

    table_name = "test_sales"

    # Ensure the test starts from a clean state.
    with engine.begin() as connection:
        connection.execute(
            text(
                'DROP TABLE IF EXISTS '
                '"uploaded_data"."test_sales"'
            )
        )

    try:
        table_name, columns = create_physical_table(
            df,
            table_name,
        )

        inserted = insert_dataframe(
            df,
            table_name,
            columns,
        )

        assert inserted == 3

        with engine.connect() as connection:
            result = connection.execute(
                text(
                    'SELECT COUNT(*) '
                    'FROM "uploaded_data"."test_sales"'
                )
            )

            assert result.scalar() == 3

    finally:
        # Always clean up test data.
        with engine.begin() as connection:
            connection.execute(
                text(
                    'DROP TABLE IF EXISTS '
                    '"uploaded_data"."test_sales"'
                )
            )