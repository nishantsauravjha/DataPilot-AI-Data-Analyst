from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path

import pymupdf


@dataclass(frozen=True)
class PDFPage:
    page_number: int
    text: str


def load_pdf_pages(file_path: str | Path) -> list[PDFPage]:
    """
    Extract text page-by-page from a PDF.

    Page numbers are 1-based to match the knowledge schema.
    """

    path = Path(file_path)

    if not path.exists():
        raise FileNotFoundError(
            f"PDF file not found: {path}"
        )

    if path.suffix.lower() != ".pdf":
        raise ValueError(
            "Expected a PDF file."
        )

    pages: list[PDFPage] = []

    with pymupdf.open(path) as document:

        for index, page in enumerate(document):

            text = page.get_text("text") or ""

            pages.append(
                PDFPage(
                    page_number=index + 1,
                    text=text,
                )
            )

    return pages