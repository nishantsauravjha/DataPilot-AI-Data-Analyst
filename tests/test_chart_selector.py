import pandas as pd

from backend.visualization.chart_selector import (
    select_chart,
)


def test_category_numeric_returns_bar_chart():
    df = pd.DataFrame(
        {
            "product_name": [
                "iPhone",
                "MacBook",
                "AirPods",
            ],
            "total_revenue": [
                2500,
                6500,
                1500,
            ],
        }
    )

    result = select_chart(df)

    assert result["type"] == "bar"
    assert result["x"] == "product_name"
    assert result["y"] == "total_revenue"


def test_datetime_numeric_returns_line_chart():
    df = pd.DataFrame(
        {
            "order_date": pd.to_datetime(
                [
                    "2026-01-01",
                    "2026-02-01",
                ]
            ),
            "revenue": [
                1000,
                2500,
            ],
        }
    )

    result = select_chart(df)

    assert result["type"] == "line"
    assert result["x"] == "order_date"
    assert result["y"] == "revenue"


def test_single_numeric_returns_metric():
    df = pd.DataFrame(
        {
            "total_revenue": [6500]
        }
    )

    result = select_chart(df)

    assert result["type"] == "metric"


def test_empty_dataframe_returns_table():
    df = pd.DataFrame()

    result = select_chart(df)

    assert result["type"] == "table"