import pandas as pd

from backend.ingestion.profiler import profile_dataframe


def test_profile_dataframe():
    df = pd.DataFrame(
        {
            "product": ["A", "B", "C"],
            "quantity": [10, 20, 30],
            "revenue": [100.5, 200.0, 300.75],
        }
    )

    profiles = profile_dataframe(df)

    assert len(profiles) == 3

    assert profiles[0]["column_name"] == "product"
    assert profiles[0]["logical_data_type"] == "STRING"

    assert profiles[1]["column_name"] == "quantity"
    assert profiles[1]["logical_data_type"] == "INTEGER"

    assert profiles[2]["column_name"] == "revenue"
    assert profiles[2]["logical_data_type"] == "DECIMAL"
    assert profiles[2]["semantic_role"] == "MEASURE"