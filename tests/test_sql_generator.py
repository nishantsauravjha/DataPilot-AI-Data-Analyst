import pytest

from backend.sql.generator import (
    _extract_json,
    _validate_generation_result,
)


def test_extract_json():
    content = """
    {
        "sql": "SELECT * FROM uploaded_data.sales LIMIT 10",
        "explanation": "Returns sample sales rows.",
        "confidence": 0.95
    }
    """

    result = _extract_json(content)

    assert result["sql"].startswith("SELECT")
    assert result["confidence"] == 0.95


def test_extract_markdown_json():
    content = """
    ```json
    {
        "sql": "SELECT product_name FROM uploaded_data.sales",
        "explanation": "Returns product names.",
        "confidence": 0.90
    }
    ```
    """

    result = _extract_json(content)

    assert result["sql"].startswith("SELECT")


def test_generation_result_validation():

    result = _validate_generation_result(
        {
            "sql": "SELECT 1",
            "explanation": "Test query.",
            "confidence": 0.8,
        }
    )

    assert result["sql"] == "SELECT 1"
    assert result["explanation"] == "Test query."
    assert result["confidence"] == 0.8


def test_confidence_is_clamped():

    result = _validate_generation_result(
        {
            "sql": "SELECT 1",
            "explanation": "Test query.",
            "confidence": 5,
        }
    )

    assert result["confidence"] == 1.0


def test_missing_field_rejected():

    with pytest.raises(ValueError):
        _validate_generation_result(
            {
                "sql": "SELECT 1",
                "explanation": "Test query.",
            }
        )


def test_empty_question_rejected():

    from backend.sql.generator import generate_sql

    with pytest.raises(ValueError):
        generate_sql(
            question="",
            schema="TABLE sales (revenue DECIMAL)",
        )