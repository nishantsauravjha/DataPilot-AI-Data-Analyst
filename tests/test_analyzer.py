import pandas as pd

from backend.analysis.analyzer import analyze_dataframe


def test_analyze_dataframe_basic():
    df = pd.DataFrame(
        {
            "product_name": [
                "iPhone",
                "MacBook",
                "AirPods",
            ],
            "revenue": [
                1000,
                2500,
                1500,
            ],
            "quantity": [
                10,
                5,
                20,
            ],
        }
    )

    result = analyze_dataframe(df)

    assert result["row_count"] == 3
    assert result["column_count"] == 3

    assert result["column_types"]["numeric"] == [
        "revenue",
        "quantity",
    ]

    assert result["column_types"]["categorical"] == [
        "product_name",
    ]

    assert result["numeric_summary"]["revenue"]["sum"] == 5000
    assert result["numeric_summary"]["revenue"]["max"] == 2500

    assert (
        result["extremes"]["revenue"]["maximum"]["row"][
            "product_name"
        ]
        == "MacBook"
    )


def test_empty_dataframe():
    df = pd.DataFrame(
        columns=[
            "product_name",
            "revenue",
        ]
    )

    result = analyze_dataframe(df)

    assert result["empty"] is True
    assert result["row_count"] == 0
    assert result["preview"] == []


def test_datetime_values_are_json_safe():
    df = pd.DataFrame(
        {
            "order_date": pd.to_datetime(
                [
                    "2026-01-01",
                    "2026-01-02",
                ]
            ),
            "revenue": [100, 200],
        }
    )

    result = analyze_dataframe(df)

    assert result["column_types"]["datetime"] == [
        "order_date"
    ]

    assert result["preview"][0]["order_date"] == (
        "2026-01-01T00:00:00"
    )


def test_categorical_summary():
    df = pd.DataFrame(
        {
            "region": [
                "North",
                "North",
                "South",
            ]
        }
    )

    result = analyze_dataframe(df)

    summary = result["categorical_summary"]["region"]

    assert summary["unique_count"] == 2
    assert summary["top_values"][0]["value"] == "North"
    assert summary["top_values"][0]["count"] == 2