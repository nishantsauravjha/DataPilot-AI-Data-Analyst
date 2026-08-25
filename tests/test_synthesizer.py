from unittest.mock import MagicMock

import pytest

from backend.analysis.synthesizer import (
    _extract_json,
    _validate_result,
    synthesize_answer,
)


def test_extract_json():
    content = """
    {
        "answer": "MacBook generated the highest revenue.",
        "key_points": [
            "MacBook generated 6500."
        ],
        "confidence": 0.95
    }
    """

    result = _extract_json(content)

    assert result["answer"].startswith(
        "MacBook"
    )
    assert result["confidence"] == 0.95


def test_extract_markdown_json():
    content = """
    ```json
    {
        "answer": "Revenue was 6500.",
        "key_points": [
            "Total revenue is 6500."
        ],
        "confidence": 0.9
    }
    ```
    """

    result = _extract_json(content)

    assert result["answer"] == (
        "Revenue was 6500."
    )


def test_validation():
    result = _validate_result(
        {
            "answer": "MacBook generated the highest revenue.",
            "key_points": [
                "Revenue was 6500."
            ],
            "confidence": 0.95,
        }
    )

    assert result["confidence"] == 0.95


def test_confidence_is_clamped():
    result = _validate_result(
        {
            "answer": "Answer.",
            "key_points": [],
            "confidence": 4.5,
        }
    )

    assert result["confidence"] == 1.0


def test_missing_field_rejected():
    with pytest.raises(ValueError):
        _validate_result(
            {
                "answer": "Answer.",
                "confidence": 0.9,
            }
        )


def test_empty_question_rejected():
    with pytest.raises(ValueError):
        synthesize_answer(
            question="",
            sql="SELECT 1",
            result={"row_count": 1},
            analysis={},
        )


def test_empty_sql_rejected():
    with pytest.raises(ValueError):
        synthesize_answer(
            question="What is the revenue?",
            sql="",
            result={"row_count": 1},
            analysis={},
        )


def test_empty_result_does_not_call_llm():
    client = MagicMock()

    result = synthesize_answer(
        question="Which product sold the most?",
        sql="SELECT product_name FROM sales",
        result={
            "row_count": 0,
            "rows": [],
        },
        analysis={
            "row_count": 0,
        },
        client=client,
    )

    assert result["confidence"] == 1.0
    assert "No matching data" in result["answer"]

    client.chat.completions.create.assert_not_called()