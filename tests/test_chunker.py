from backend.rag.chunker import (
    chunk_text,
    normalize_text,
)


def test_normalize_text():
    text = """
        Hello world.

        This is DataPilot.
    """

    result = normalize_text(text)

    assert result == (
        "Hello world.\n"
        "This is DataPilot."
    )


def test_chunk_text():
    text = "A" * 1000

    chunks = chunk_text(
        text,
        chunk_size=300,
        chunk_overlap=50,
    )

    assert len(chunks) > 1

    assert chunks[0].chunk_index == 0
    assert chunks[1].chunk_index == 1

    assert len(chunks[0].text) <= 300


def test_chunk_overlap():
    text = "0123456789" * 100

    chunks = chunk_text(
        text,
        chunk_size=100,
        chunk_overlap=20,
    )

    assert len(chunks) >= 2

    assert chunks[0].text[-20:] == (
        chunks[1].text[:20]
    )


def test_empty_text():
    chunks = chunk_text("")

    assert chunks == []


def test_invalid_chunk_size():
    try:
        chunk_text(
            "hello",
            chunk_size=0,
        )
        assert False
    except ValueError:
        assert True


def test_invalid_overlap():
    try:
        chunk_text(
            "hello",
            chunk_size=100,
            chunk_overlap=100,
        )
        assert False
    except ValueError:
        assert True