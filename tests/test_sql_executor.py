from decimal import Decimal

import pandas as pd

from backend.sql.executor import _normalize_dataframe_types


def test_decimal_columns_are_normalized_to_numeric():

    dataframe = pd.DataFrame(
        {
            "product_name": [
                "iPhone",
                "MacBook",
            ],
            "total_revenue": [
                Decimal("1000.50"),
                Decimal("2500.75"),
            ],
        }
    )

    result = _normalize_dataframe_types(
        dataframe
    )

    assert pd.api.types.is_numeric_dtype(
        result["total_revenue"]
    )

    assert result[
        "total_revenue"
    ].iloc[0] == 1000.50

    assert result[
        "total_revenue"
    ].iloc[1] == 2500.75