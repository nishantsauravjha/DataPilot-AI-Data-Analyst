from backend.orchestration.query_router import (
    QueryMode,
    route_query,
)


def test_structured_query():
    assert (
        route_query(
            "Which product generated the highest revenue?"
        )
        == QueryMode.STRUCTURED
    )


def test_rag_query():
    assert (
        route_query(
            "What does the report say about data security?"
        )
        == QueryMode.RAG
    )


def test_hybrid_query():
    assert (
        route_query(
            "According to the report, which product had the highest revenue?"
        )
        == QueryMode.HYBRID
    )


def test_default_structured_query():
    assert (
        route_query(
            "Show me the products."
        )
        == QueryMode.STRUCTURED
    )


def test_empty_question():
    try:
        route_query("")
        assert False
    except ValueError:
        assert True