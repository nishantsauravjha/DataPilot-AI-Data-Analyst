from __future__ import annotations

import json
import re
from typing import Any

from openai import OpenAI

from backend.core.config import settings


# ============================================================
# OpenAI Client
# ============================================================

client = OpenAI(
    api_key=settings.OPENAI_API_KEY,
)


# ============================================================
# System Prompt
# ============================================================

SYSTEM_PROMPT = """
You are DataPilot's SQL generation engine.

Your job is to convert a user's natural-language question
into ONE safe PostgreSQL query using ONLY the database
schema provided by DataPilot.

IMPORTANT:

- Generate exactly ONE SQL statement.
- The statement must be read-only.
- SELECT statements are allowed.
- WITH ... SELECT statements are allowed.
- Never generate INSERT.
- Never generate UPDATE.
- Never generate DELETE.
- Never generate DROP.
- Never generate ALTER.
- Never generate CREATE.
- Never generate TRUNCATE.
- Never generate GRANT.
- Never generate REVOKE.
- Never generate MERGE.
- Never generate CALL or EXEC.
- Never generate multiple statements.
- Never invent tables.
- Never invent columns.
- Use ONLY tables and columns present in the supplied schema.
- Use PostgreSQL syntax.
- Use explicit column names.
- Use table aliases when helpful.
- For aggregation questions, use appropriate aggregate
  functions and GROUP BY.
- For ranking questions, use ORDER BY and LIMIT.
- For "highest", "lowest", "best", "worst", etc.,
  correctly interpret the requested metric.
- For questions asking for a single top result, use LIMIT 1.
- For raw-row queries, use a reasonable LIMIT.
- Never expose database credentials.
- Never reference tables outside the supplied schema.

Return ONLY valid JSON.

Required format:

{
    "sql": "SELECT ...",
    "explanation": "Brief explanation of what the query does.",
    "confidence": 0.95
}

The confidence value must be a number between 0 and 1.
"""


# ============================================================
# JSON Parsing
# ============================================================


def _extract_json(content: str) -> dict[str, Any]:
    """
    Parse JSON returned by the LLM.

    Handles:
    - Normal JSON
    - Markdown JSON code fences
    - Surrounding whitespace
    """

    if not content or not content.strip():
        raise ValueError(
            "The SQL model returned an empty response."
        )

    content = content.strip()

    # Remove markdown code fences if the model added them.
    content = re.sub(
        r"^```(?:json)?\s*",
        "",
        content,
        flags=re.IGNORECASE,
    )

    content = re.sub(
        r"\s*```$",
        "",
        content,
    )

    try:
        result = json.loads(content)

    except json.JSONDecodeError as exc:
        raise ValueError(
            "The SQL model returned invalid JSON."
        ) from exc

    if not isinstance(result, dict):
        raise ValueError(
            "The SQL model response must be a JSON object."
        )

    return result


# ============================================================
# Result Validation
# ============================================================


def _validate_generation_result(
    result: dict[str, Any],
) -> dict[str, Any]:
    """
    Validate and normalize the structured LLM response.
    """

    required_fields = {
        "sql",
        "explanation",
        "confidence",
    }

    missing = required_fields - result.keys()

    if missing:
        raise ValueError(
            "SQL generator response is missing fields: "
            f"{sorted(missing)}"
        )

    sql = result["sql"]

    explanation = result["explanation"]

    confidence = result["confidence"]

    if not isinstance(sql, str) or not sql.strip():
        raise ValueError(
            "Generated SQL is empty."
        )

    if not isinstance(explanation, str):
        raise ValueError(
            "SQL explanation must be a string."
        )

    # Normalize confidence to a float.
    try:
        confidence = float(confidence)

    except (TypeError, ValueError) as exc:
        raise ValueError(
            "SQL confidence must be numeric."
        ) from exc

    # Keep confidence within the expected range.
    confidence = max(
        0.0,
        min(1.0, confidence),
    )

    return {
        "sql": sql.strip(),
        "explanation": explanation.strip(),
        "confidence": confidence,
    }


# ============================================================
# SQL Generation
# ============================================================


def generate_sql(
    question: str,
    schema: str,
) -> dict[str, Any]:
    """
    Generate a PostgreSQL query from a natural-language question.

    The generated SQL is subsequently validated by the SQL
    validation layer before execution.
    """

    if not isinstance(question, str):
        raise TypeError(
            "Question must be a string."
        )

    if not isinstance(schema, str):
        raise TypeError(
            "Schema must be a string."
        )

    question = question.strip()
    schema = schema.strip()

    if not question:
        raise ValueError(
            "Question cannot be empty."
        )

    if not schema:
        raise ValueError(
            "Schema context cannot be empty."
        )

    user_prompt = f"""
DATABASE SCHEMA
===============

{schema}


USER QUESTION
=============

{question}


Generate the safest correct PostgreSQL query for
the user's question using ONLY the schema above.

Return JSON only.
"""

    try:
        response = client.chat.completions.create(
            model=settings.OPENAI_MODEL,
            messages=[
                {
                    "role": "system",
                    "content": SYSTEM_PROMPT,
                },
                {
                    "role": "user",
                    "content": user_prompt,
                },
            ],
        )

    except Exception as exc:
        raise RuntimeError(
            f"SQL generation request failed: {exc}"
        ) from exc

    if not response.choices:
        raise RuntimeError(
            "The SQL model returned no choices."
        )

    content = response.choices[0].message.content

    if not content:
        raise RuntimeError(
            "The SQL model returned an empty response."
        )

    result = _extract_json(content)

    return _validate_generation_result(result)