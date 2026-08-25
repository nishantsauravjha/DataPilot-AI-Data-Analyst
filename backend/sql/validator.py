from __future__ import annotations

import re


FORBIDDEN_KEYWORDS = {
    "INSERT",
    "UPDATE",
    "DELETE",
    "DROP",
    "ALTER",
    "TRUNCATE",
    "CREATE",
    "GRANT",
    "REVOKE",
    "MERGE",
    "CALL",
    "EXEC",
}


def validate_sql(sql: str) -> str:
    """
    Validate and normalize LLM-generated SQL.

    Only SELECT statements are allowed.
    """

    if not sql or not sql.strip():
        raise ValueError(
            "SQL cannot be empty."
        )

    sql = sql.strip()

    # Remove a trailing semicolon.
    sql = sql.rstrip(";").strip()

    # Reject multiple statements.
    if ";" in sql:
        raise ValueError(
            "Multiple SQL statements are not allowed."
        )

    # Must begin with SELECT or WITH.
    if not re.match(
        r"^(SELECT|WITH)\b",
        sql,
        flags=re.IGNORECASE,
    ):
        raise ValueError(
            "Only SELECT statements are allowed."
        )

    # Reject dangerous keywords anywhere in query.
    for keyword in FORBIDDEN_KEYWORDS:
        pattern = rf"\b{keyword}\b"

        if re.search(
            pattern,
            sql,
            flags=re.IGNORECASE,
        ):
            raise ValueError(
                f"Forbidden SQL keyword: {keyword}"
            )

    return sql