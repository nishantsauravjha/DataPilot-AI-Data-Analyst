import pandas as pd

from backend.visualization.chart_selector import (
    select_chart,
    validate_chart_spec,
)


def test_categorical_numeric_result_selects_bar():
    df = pd.DataFrame(
        {
            "product_name": [
                "MacBook",
                "iPhone",
                "AirPods",
            ],
            "total_revenue": [
                6500,
                2500,
                1500,
            ],
        }
    )

    spec = select_chart(df)

    assert spec["type"] == "bar"
    assert spec["x"] == "product_name"
    assert spec["y"] == "total_revenue"


def test_datetime_numeric_result_selects_line():
    df = pd.DataFrame(
        {
            "order_date": pd.to_datetime(
                [
                    "2026-01-01",
                    "2026-02-01",
                    "2026-03-01",
                ]
            ),
            "revenue": [
                1000,
                2500,
                3200,
            ],
        }
    )

    spec = select_chart(df)

    assert spec["type"] == "line"
    assert spec["x"] == "order_date"
    assert spec["y"] == "revenue"


def test_two_numeric_columns_select_scatter():
    df = pd.DataFrame(
        {
            "quantity": [
                5,
                10,
                20,
            ],
            "revenue": [
                1000,
                2500,
                5000,
            ],
        }
    )

    spec = select_chart(df)

    assert spec["type"] == "scatter"
    assert spec["x"] == "quantity"
    assert spec["y"] == "revenue"


def test_single_numeric_value_selects_metric():
    df = pd.DataFrame(
        {
            "total_revenue": [6500]
        }
    )

    spec = select_chart(df)

    assert spec["type"] == "metric"
    assert spec["y"] == "total_revenue"


def test_empty_dataframe_selects_table():
    df = pd.DataFrame(
        columns=[
            "product",
            "revenue",
        ]
    )

    spec = select_chart(df)

    assert spec["type"] == "table"


def test_chart_spec_validation():
    spec = {
        "type": "bar",
        "x": "product",
        "y": "revenue",
        "title": "Revenue by Product",
    }

    result = validate_chart_spec(spec)

    assert result == spec