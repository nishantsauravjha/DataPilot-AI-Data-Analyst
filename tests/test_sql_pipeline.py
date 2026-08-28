from unittest.mock import patch

import pandas as pd

from backend.sql.pipeline import (
    _check_result,
)


def test_empty_result_is_valid():
    df = pd.DataFrame(
        columns=["product_name", "revenue"]
    )

    result = _check_result(df)

    assert result["valid"] is True
    assert result["empty"] is True


def test_non_empty_result_is_valid():
    df = pd.DataFrame(
        [
            {
                "product_name": "MacBook",
                "revenue": 6500.0,
            }
        ]
    )

    result = _check_result(df)

    assert result["valid"] is True
    assert result["empty"] is False
    assert result["row_count"] == 1
    assert result["column_count"] == 2


def test_invalid_result_is_rejected():
    result = _check_result(
        None
    )

    assert result["valid"] is False