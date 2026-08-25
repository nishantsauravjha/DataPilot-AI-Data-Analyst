import pytest

from backend.sql.validator import validate_sql


def test_valid_select():
    sql = """
        SELECT product_name, SUM(revenue)
        FROM uploaded_data.sales
        GROUP BY product_name
    """

    result = validate_sql(sql)

    assert result.startswith("SELECT")


def test_valid_cte():
    sql = """
        WITH totals AS (
            SELECT product_name, SUM(revenue) AS revenue
            FROM uploaded_data.sales
            GROUP BY product_name
        )
        SELECT *
        FROM totals
    """

    result = validate_sql(sql)

    assert result.startswith("WITH")


@pytest.mark.parametrize(
    "sql",
    [
        "DROP TABLE uploaded_data.sales",
        "DELETE FROM uploaded_data.sales",
        "UPDATE uploaded_data.sales SET revenue = 0",
        "INSERT INTO uploaded_data.sales VALUES (1)",
        "ALTER TABLE uploaded_data.sales ADD COLUMN x TEXT",
        "TRUNCATE uploaded_data.sales",
    ],
)
def test_dangerous_sql_rejected(sql):
    with pytest.raises(ValueError):
        validate_sql(sql)


def test_multiple_statements_rejected():
    with pytest.raises(ValueError):
        validate_sql(
            "SELECT * FROM uploaded_data.sales; "
            "DROP TABLE uploaded_data.sales;"
        )