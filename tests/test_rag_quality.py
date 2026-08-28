from backend.rag.retriever import (
    RAGRetriever,
    RetrievedChunk,
)


def make_chunk(
    chunk_id: str,
    text: str,
    score: float,
    page: int,
    document_id: str = "doc-1",
) -> RetrievedChunk:

    return RetrievedChunk(
        chunk_id=chunk_id,
        document_id=document_id,
        page_id=f"page-{page}",
        text=text,
        score=score,
        page_number=page,
        source_name="report.pdf",
        metadata={},
    )


def test_similarity_threshold():

    retriever = RAGRetriever(
        min_score=0.50
    )

    chunks = [
        make_chunk(
            "1",
            "Relevant information",
            0.80,
            1,
        ),
        make_chunk(
            "2",
            "Weak information",
            0.30,
            2,
        ),
    ]

    filtered = retriever._apply_similarity_threshold(
        chunks
    )

    assert len(filtered) == 1
    assert filtered[0].chunk_id == "1"


def test_exact_duplicate_is_removed():

    chunks = [
        make_chunk(
            "1",
            "This is the same content.",
            0.90,
            1,
        ),
        make_chunk(
            "2",
            "This is the same content.",
            0.85,
            2,
        ),
    ]

    result = RAGRetriever._remove_exact_duplicates(
        chunks
    )

    assert len(result) == 1
    assert result[0].chunk_id == "1"


def test_diversity_prefers_different_pages():

    chunks = [
        make_chunk(
            "1",
            "Revenue increased significantly in Q1.",
            0.95,
            1,
        ),
        make_chunk(
            "2",
            "Revenue increased significantly in Q1.",
            0.94,
            1,
        ),
        make_chunk(
            "3",
            "Customer retention improved during Q2.",
            0.90,
            2,
        ),
    ]

    result = RAGRetriever._select_diverse_chunks(
        chunks,
        limit=2,
    )

    assert len(result) == 2
    assert result[0].page_number == 1
    assert result[1].page_number == 2


def test_overlap_detection():

    first = make_chunk(
        "1",
        "Revenue increased significantly during the first quarter of the year.",
        0.90,
        1,
    )

    second = make_chunk(
        "2",
        "Revenue increased significantly during the first quarter of the year because of strong sales.",
        0.85,
        1,
    )

    similarity = RAGRetriever._text_overlap_ratio(
        first.text,
        second.text,
    )

    assert similarity >= 0.80


def test_no_relevant_chunks():

    retriever = RAGRetriever(
        min_score=0.90
    )

    chunks = [
        make_chunk(
            "1",
            "Weak result",
            0.40,
            1,
        )
    ]

    result = retriever._apply_similarity_threshold(
        chunks
    )

    assert result == []