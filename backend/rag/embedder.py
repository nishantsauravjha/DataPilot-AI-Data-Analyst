from __future__ import annotations

from openai import OpenAI

from backend.core.config import settings


class EmbeddingService:
    """
    Generates embeddings using OpenAI.
    """

    def __init__(
        self,
        client: OpenAI | None = None,
    ) -> None:

        self.client = client or OpenAI(
            api_key=settings.OPENAI_API_KEY
        )

        self.model = settings.EMBEDDING_MODEL

    def embed_text(
        self,
        text: str,
    ) -> list[float]:

        if not text.strip():
            raise ValueError(
                "Cannot embed empty text."
            )

        response = self.client.embeddings.create(
            model=self.model,
            input=text,
        )

        return response.data[0].embedding

    def embed_documents(
        self,
        texts: list[str],
    ) -> list[list[float]]:

        if not texts:
            return []

        if any(
            not text.strip()
            for text in texts
        ):
            raise ValueError(
                "Cannot embed empty documents."
            )

        response = self.client.embeddings.create(
            model=self.model,
            input=texts,
        )

        embeddings = sorted(
            response.data,
            key=lambda item: item.index,
        )

        return [
            item.embedding
            for item in embeddings
        ]