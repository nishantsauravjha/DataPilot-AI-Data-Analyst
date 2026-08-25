from __future__ import annotations

import pandas as pd
from sqlalchemy import text

from backend.database.connection import engine
from backend.sql.validator import validate_sql


MAX_ROWS = 10000


def execute_query(sql: str) -> pd.DataFrame:
    """
    Validate and execute a read-only SQL query.

    Returns the result as a pandas DataFrame.
    """

    safe_sql = validate_sql(sql)

    with engine.connect() as connection:
        result = connection.execute(text(safe_sql))

        rows = result.fetchmany(MAX_ROWS)

        return pd.DataFrame(
            rows,
            columns=result.keys(),
        )