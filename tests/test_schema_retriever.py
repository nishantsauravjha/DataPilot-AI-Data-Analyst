from backend.sql.schema_formatter import format_schema
from backend.sql.schema_retriever import (
    get_latest_dataset_schema,
)


def test_schema_retrieval():
    schema = get_latest_dataset_schema()

    assert schema
    assert len(schema) >= 5

    formatted = format_schema(schema)

    assert "TABLE:" in formatted
    assert "product_name" in formatted
    assert "revenue" in formatted
    assert "quantity" in formatted