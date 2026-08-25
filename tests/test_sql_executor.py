from backend.sql.executor import execute_query


def test_execute_select_query():
    sql = """
        SELECT
            product_name,
            SUM(revenue) AS total_revenue
        FROM uploaded_data."a189e9d77013400581d4fb59fb6d1784_sales"
        GROUP BY product_name
        ORDER BY total_revenue DESC
    """

    result = execute_query(sql)

    assert not result.empty
    assert "product_name" in result.columns
    assert "total_revenue" in result.columns

    assert result.iloc[0]["product_name"] == "MacBook"
    assert result.iloc[0]["total_revenue"] == 6500