from __future__ import annotations

from dataclasses import dataclass
from typing import Any


@dataclass(frozen=True)
class TextChunk:
    """
    A chunk of source text with provenance metadata.
    """

    chunk_index: int
    text: str
    page_number: int | None = None
    source_name: str | None = None
    metadata: dict[str, Any] | None = None


def normalize_text(text: str) -> str:
    """
    Normalize extracted PDF text without destroying
    meaningful whitespace.
    """

    if not text:
        return ""

    lines = [
        line.strip()
        for line in text.splitlines()
    ]

    lines = [
        line
        for line in lines
        if line
    ]

    return "\n".join(lines)


def chunk_text(
    text: str,
    *,
    chunk_size: int = 800,
    chunk_overlap: int = 120,
) -> list[TextChunk]:
    """
    Split text into overlapping chunks.

    chunk_size and chunk_overlap are measured in characters.

    This is intentionally deterministic so the same document
    produces the same chunks.
    """

    if chunk_size <= 0:
        raise ValueError(
            "chunk_size must be greater than zero."
        )

    if chunk_overlap < 0:
        raise ValueError(
            "chunk_overlap cannot be negative."
        )

    if chunk_overlap >= chunk_size:
        raise ValueError(
            "chunk_overlap must be smaller than chunk_size."
        )

    normalized = normalize_text(text)

    if not normalized:
        return []

    chunks: list[TextChunk] = []

    start = 0
    chunk_index = 0

    text_length = len(normalized)

    while start < text_length:
        end = min(
            start + chunk_size,
            text_length,
        )

        chunk = normalized[start:end].strip()

        if chunk:
            chunks.append(
                TextChunk(
                    chunk_index=chunk_index,
                    text=chunk,
                )
            )

            chunk_index += 1

        if end >= text_length:
            break

        start = end - chunk_overlap

    return chunks