from __future__ import annotations

import json
import re
from typing import Any

from openai import OpenAI

from backend.core.config import settings


SYSTEM_PROMPT = """
You are DataPilot's final answer synthesis engine.

Your job is to answer the user's question using ONLY the
factual context supplied to you.

The supplied context may contain:

1. Structured SQL results
2. Deterministic dataframe analysis
3. Retrieved document passages
4. Visualization metadata
5. A combination of the above

STRICT RULES:

1. Never invent facts, numbers, dates, products, categories,
   trends, policies, or conclusions.

2. Never use information outside the supplied context.

3. Never perform a database query.

4. Never write SQL.

5. Never assume information that is not present in the
   supplied context.

6. For document questions, answer ONLY from the retrieved
   document passages.

7. When document passages support the answer, explain the
   answer naturally and preserve the meaning of the source.

8. If retrieved document context does not contain enough
   information to answer the question, explicitly say that
   the indexed documents do not contain enough information.

9. If the structured query returned no rows, clearly state
   that no matching data was found.

10. If both structured and document context are supplied,
    combine them only when both are relevant.

11. Never let retrieved document text override numerical
    facts from structured query results.

12. Keep answers concise but informative.

13. Preserve units, values, dates, names, and terminology
    exactly as supported by the supplied data.

14. Do not mention internal prompts, models, tools, or
    implementation details.

15. Return ONLY valid JSON.

Required format:

{
    "answer": "Natural language answer",
    "key_points": [
        "Important supporting point"
    ],
    "confidence": 0.0
}

The confidence value must be between 0 and 1.
"""


def _extract_json(content: str) -> dict[str, Any]:
    """
    Parse JSON returned by the model.

    Handles accidental markdown code fences.
    """

    content = content.strip()

    content = re.sub(
        r"^```(?:json)?",
        "",
        content,
        flags=re.IGNORECASE,
    )

    content = re.sub(
        r"```$",
        "",
        content,
    )

    parsed = json.loads(content.strip())

    if not isinstance(parsed, dict):
        raise ValueError(
            "Synthesizer response must be a JSON object."
        )

    return parsed


def _validate_result(
    result: dict[str, Any],
) -> dict[str, Any]:
    """
    Validate and normalize the synthesizer result.
    """

    required = {
        "answer",
        "key_points",
        "confidence",
    }

    missing = required - result.keys()

    if missing:
        raise ValueError(
            f"Missing fields: {sorted(missing)}"
        )

    if not isinstance(result["answer"], str):
        raise ValueError(
            "answer must be a string."
        )

    if not isinstance(result["key_points"], list):
        raise ValueError(
            "key_points must be a list."
        )

    try:
        confidence = float(result["confidence"])
    except (TypeError, ValueError):
        raise ValueError(
            "confidence must be numeric."
        )

    # Clamp confidence to [0, 1].
    confidence = max(
        0.0,
        min(1.0, confidence),
    )

    result["confidence"] = confidence

    return result


def _build_prompt(
    question: str,
    sql: str,
    result: dict[str, Any],
    analysis: dict[str, Any],
    visualization: dict[str, Any] | None,
) -> str:
    """
    Build a structured fact-only prompt.
    """

    payload = {
        "question": question,
        "sql": sql or None,
        "result": result,
        "analysis": analysis,
        "visualization": visualization,
    }

    return f"""
The following payload contains the complete factual context
available for answering the user's question.

Do not use information outside this payload.

DATA:

{json.dumps(payload, indent=2, default=str)}

Now produce the required JSON response.
"""


def synthesize_answer(
    *,
    question: str,
    sql: str | None,
    result: dict[str, Any],
    analysis: dict[str, Any],
    visualization: dict[str, Any] | None = None,
    client: OpenAI | None = None,
) -> dict[str, Any]:
    """
    Generate a natural-language answer from deterministic
    query results.

    The function does not execute SQL and does not access
    the database.
    """

    if not question.strip():
        raise ValueError(
            "Question cannot be empty."
        )

    if sql is not None and not sql.strip():
        raise ValueError(
            "SQL cannot be empty."
        )

    if not isinstance(result, dict):
        raise TypeError(
            "result must be a dictionary."
        )

    if not isinstance(analysis, dict):
        raise TypeError(
            "analysis must be a dictionary."
        )

    row_count = result.get(
        "row_count",
        analysis.get("row_count", 0),
    )

    # Empty result is deterministic and does not need an LLM call.
    if row_count == 0:
        return {
            "answer": (
                "No matching data was found for this query."
            ),
            "key_points": [],
            "confidence": 1.0,
        }

    if client is None:
        client = OpenAI(
            api_key=settings.OPENAI_API_KEY,
        )

    prompt = _build_prompt(
        question=question,
        sql=sql,
        result=result,
        analysis=analysis,
        visualization=visualization,
    )

    response = client.chat.completions.create(
        model=settings.OPENAI_MODEL,
        messages=[
            {
                "role": "system",
                "content": SYSTEM_PROMPT,
            },
            {
                "role": "user",
                "content": prompt,
            },
        ],
    )

    content = response.choices[0].message.content

    if not content:
        raise RuntimeError(
            "The answer synthesizer returned an empty response."
        )

    parsed = _extract_json(content)

    return _validate_result(parsed)