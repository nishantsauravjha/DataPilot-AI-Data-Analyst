from types import SimpleNamespace

from backend.rag.retriever import (
    RAGRetriever,
)


class FakeEmbedder:

    def embed_text(self, text):
        return [0.1, 0.2, 0.3]


class FakeVectorStore:

    def search(
        self,
        query_vector,
        *,
        top_k,
        document_id=None,
    ):
        return [
            SimpleNamespace(
                id="1",
                score=0.90,
                payload={
                    "chunk_id": "1",
                    "document_id": "doc1",
                    "page_id": "page1",
                    "page_number": 1,
                    "source_name": "report.pdf",
                    "text": (
                        "This is the important "
                        "main finding."
                    ),
                },
            ),
            SimpleNamespace(
                id="2",
                score=0.80,
                payload={
                    "chunk_id": "2",
                    "document_id": "doc1",
                    "page_id": "page1",
                    "page_number": 1,
                    "source_name": "report.pdf",
                    "text": (
                        "This is the important "
                        "main finding."
                    ),
                },
            ),
            SimpleNamespace(
                id="3",
                score=0.10,
                payload={
                    "chunk_id": "3",
                    "document_id": "doc1",
                    "page_id": "page2",
                    "page_number": 2,
                    "source_name": "report.pdf",
                    "text": "Weak result.",
                },
            ),
        ]


def test_retrieval_filters_and_deduplicates():

    retriever = RAGRetriever(
        embedder=FakeEmbedder(),
        vector_store=FakeVectorStore(),
        min_score=0.20,
    )

    results = retriever.retrieve(
        "What are the findings?",
        top_k=5,
    )

    assert len(results) == 1
    assert results[0].chunk_id == "1"
    assert results[0].score == 0.90