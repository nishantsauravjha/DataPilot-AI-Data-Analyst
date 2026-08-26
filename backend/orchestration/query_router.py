from __future__ import annotations

from enum import Enum


class QueryMode(str, Enum):
    STRUCTURED = "structured"
    RAG = "rag"
    HYBRID = "hybrid"


# Words strongly associated with tabular/database analysis.
STRUCTURED_TERMS = {
    "sum",
    "total",
    "average",
    "avg",
    "mean",
    "median",
    "count",
    "how many",
    "maximum",
    "max",
    "minimum",
    "min",
    "highest",
    "lowest",
    "top",
    "bottom",
    "rank",
    "ranking",
    "revenue",
    "sales",
    "quantity",
    "profit",
    "price",
    "compare",
    "comparison",
    "trend",
    "growth",
    "percentage",
    "percent",
    "group",
    "region",
    "product",
    "month",
    "year",
    "quarter",
}


# Words commonly associated with document/knowledge questions.
RAG_TERMS = {
    "according to",
    "document",
    "documents",
    "pdf",
    "report",
    "reports",
    "policy",
    "policies",
    "definition",
    "define",
    "explain",
    "meaning",
    "describe",
    "mentioned",
    "mentions",
    "stated",
    "states",
    "what does the report",
    "what does the document",
    "summarize",
    "summary",
    "guideline",
    "guidelines",
    "procedure",
    "procedures",
    "requirement",
    "requirements",
}


def route_query(question: str) -> QueryMode:
    """
    Determine which DataPilot pipeline should process a question.

    The router is intentionally deterministic.

    It does not call an LLM because routing should be:
        - fast
        - predictable
        - inexpensive
        - testable

    Hybrid is selected when the question contains meaningful
    signals for both structured and document-oriented reasoning.
    """

    if not isinstance(question, str):
        raise TypeError("Question must be a string.")

    question = question.strip().lower()

    if not question:
        raise ValueError("Question cannot be empty.")

    structured_score = _score(
        question,
        STRUCTURED_TERMS,
    )

    rag_score = _score(
        question,
        RAG_TERMS,
    )

    # --------------------------------------------------------
    # Strong document language + no meaningful tabular signal
    # --------------------------------------------------------

    if rag_score >= 2 and structured_score == 0:
        return QueryMode.RAG

    # --------------------------------------------------------
    # Strong signals from both worlds
    # --------------------------------------------------------

    if (
        structured_score >= 1
        and rag_score >= 1
    ):
        return QueryMode.HYBRID

    # --------------------------------------------------------
    # Explicit document-oriented language
    # --------------------------------------------------------

    if rag_score > structured_score and rag_score >= 1:
        return QueryMode.RAG

    # --------------------------------------------------------
    # Default to structured analysis
    #
    # DataPilot's primary use case is natural-language
    # analysis of uploaded structured datasets.
    # --------------------------------------------------------

    return QueryMode.STRUCTURED


def _score(
    question: str,
    terms: set[str],
) -> int:
    """
    Score a question against a collection of semantic keywords.

    Multi-word phrases are supported.
    """

    score = 0

    for term in terms:
        if term in question:
            score += 1

    return score