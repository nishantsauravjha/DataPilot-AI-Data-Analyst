from __future__ import annotations

import re
from datetime import date, datetime
from decimal import Decimal
from typing import Any

import pandas as pd

from backend.analysis.analyzer import analyze_dataframe
from backend.analysis.synthesizer import synthesize_answer
from backend.orchestration.query_router import (
    QueryMode,
    route_query,
)
from backend.rag.retriever import RAGRetriever
from backend.services.query_service import (
    execute_dataset_query,
    get_latest_schema_context,
)
from backend.sql.generator import generate_sql
from backend.visualization.chart_selector import select_chart


# ============================================================
# RAG configuration
# ============================================================

# Minimum vector similarity required for a chunk to become
# usable evidence.
RAG_SIMILARITY_THRESHOLD = 0.20

# Maximum number of final chunks considered by the pipeline.
RAG_TOP_K = 5

# Maximum number of unique source/page groups sent to the LLM.
RAG_MAX_CONTEXTS = 4

# Chunks with >= this Jaccard similarity are considered
# near-duplicates.
RAG_TEXT_OVERLAP_THRESHOLD = 0.80


class QueryOrchestrator:
    """
    Central orchestration layer for DataPilot.

    Structured pipeline:

        Question
            ↓
        Router
            ↓
        Schema retrieval
            ↓
        SQL generation
            ↓
        SQL validation/execution
            ↓
        Pandas analysis
            ↓
        Visualization
            ↓
        Final synthesis

    RAG pipeline:

        Question
            ↓
        Router
            ↓
        Vector retrieval
            ↓
        Similarity threshold
            ↓
        Exact chunk deduplication
            ↓
        Near-duplicate removal
            ↓
        Source/page compression
            ↓
        Top-K evidence
            ↓
        Context construction
            ↓
        Final synthesis

    Hybrid pipeline:

        Question
            ↓
        Router
            ↓
        ┌──────────────────────┐
        │                      │
        SQL path            RAG path
        │                      │
        └──────────┬───────────┘
                   ↓
             Final synthesis
    """

    def __init__(
        self,
        rag_retriever: RAGRetriever | None = None,
    ) -> None:

        self.rag_retriever = (
            rag_retriever
            if rag_retriever is not None
            else RAGRetriever()
        )

    # ========================================================
    # PUBLIC API
    # ========================================================

    def query(
        self,
        question: str,
    ) -> dict[str, Any]:
        """
        Route and execute a DataPilot question.
        """

        question = self._validate_question(
            question
        )

        mode = route_query(
            question
        )

        if mode == QueryMode.STRUCTURED:
            return self._run_structured(
                question
            )

        if mode == QueryMode.RAG:
            return self._run_rag(
                question
            )

        if mode == QueryMode.HYBRID:
            return self._run_hybrid(
                question
            )

        raise RuntimeError(
            f"Unsupported query mode: {mode}"
        )

    # ========================================================
    # STRUCTURED PIPELINE
    # ========================================================

    def _run_structured(
        self,
        question: str,
    ) -> dict[str, Any]:
        """
        Execute the structured Text-to-SQL pipeline.
        """

        schema = get_latest_schema_context()

        if not schema:
            raise LookupError(
                "No active structured dataset is available. "
                "Upload a CSV or Excel file first."
            )

        # ----------------------------------------------------
        # 1. Generate SQL
        # ----------------------------------------------------

        generated = generate_sql(
            question=question,
            schema=schema,
        )

        sql = generated["sql"]

        # ----------------------------------------------------
        # 2. Execute SQL
        # ----------------------------------------------------

        execution = execute_dataset_query(
            sql
        )

        # ----------------------------------------------------
        # 3. Convert result to DataFrame
        # ----------------------------------------------------

        dataframe = self._extract_dataframe(
            execution
        )

        # ----------------------------------------------------
        # 4. Deterministic analysis
        # ----------------------------------------------------

        analysis = analyze_dataframe(
            dataframe
        )

        # ----------------------------------------------------
        # 5. Visualization
        # ----------------------------------------------------

        visualization = self._select_visualization(
            dataframe
        )

        # ----------------------------------------------------
        # 6. JSON safety
        # ----------------------------------------------------

        safe_execution = (
            self._json_safe_execution(
                execution
            )
        )

        safe_analysis = self._json_safe(
            analysis
        )

        safe_visualization = self._json_safe(
            visualization
        )

        # ----------------------------------------------------
        # 7. Final synthesis
        # ----------------------------------------------------

        synthesis = synthesize_answer(
            question=question,
            sql=sql,
            result=safe_execution,
            analysis=safe_analysis,
            visualization=safe_visualization,
        )

        # ----------------------------------------------------
        # 8. Response
        # ----------------------------------------------------

        return {
            "success": True,
            "mode": QueryMode.STRUCTURED.value,
            "question": question,
            "answer": synthesis["answer"],
            "key_points": synthesis["key_points"],
            "confidence": self._combine_confidence(
                generated.get(
                    "confidence",
                    0.0,
                ),
                synthesis.get(
                    "confidence",
                    0.0,
                ),
            ),
            "sql": sql,
            "sql_explanation": generated.get(
                "explanation"
            ),
            "result": safe_execution,
            "analysis": safe_analysis,
            "visualization": safe_visualization,
            "citations": [],
        }

    # ========================================================
    # RAG PIPELINE
    # ========================================================

    def _run_rag(
        self,
        question: str,
    ) -> dict[str, Any]:
        """
        Execute the Phase-3 RAG pipeline.

        Retrieval and final evidence normalization happen before
        context construction so that context and citations always
        describe the exact same evidence.
        """

        # ----------------------------------------------------
        # 1. Retrieve candidate evidence
        # ----------------------------------------------------

        retrieved_chunks = (
            self._retrieve_rag_chunks(
                question
            )
        )

        # ----------------------------------------------------
        # 2. No relevant evidence
        # ----------------------------------------------------

        if not retrieved_chunks:
            return self._empty_rag_response(
                question
            )

        # ----------------------------------------------------
        # 3. Compress evidence by source/page
        # ----------------------------------------------------

        chunks = self._compress_rag_chunks(
            retrieved_chunks
        )

        if not chunks:
            return self._empty_rag_response(
                question
            )

        # ----------------------------------------------------
        # 4. Build final context
        # ----------------------------------------------------

        context = self._build_rag_context(
            chunks
        )

        # ----------------------------------------------------
        # 5. Build citations from exact final evidence
        # ----------------------------------------------------

        citations = self._build_rag_citations(
            chunks
        )

        # ----------------------------------------------------
        # 6. Normalized retrieval result
        # ----------------------------------------------------

        rag_rows = [
            {
                "source": getattr(
                    chunk,
                    "source_name",
                    None,
                ),
                "page": getattr(
                    chunk,
                    "page_number",
                    None,
                ),
                "score": getattr(
                    chunk,
                    "score",
                    None,
                ),
                "text": getattr(
                    chunk,
                    "text",
                    "",
                ),
            }
            for chunk in chunks
        ]

        rag_result = {
            "row_count": len(chunks),
            "retrieval_type": (
                "semantic_document_retrieval"
            ),
            "rows": rag_rows,
            "document_context": context,
        }

        source_count = len(
            {
                getattr(
                    chunk,
                    "source_name",
                    None,
                )
                for chunk in chunks
                if getattr(
                    chunk,
                    "source_name",
                    None,
                )
            }
        )

        page_count = len(
            {
                (
                    getattr(
                        chunk,
                        "source_name",
                        None,
                    ),
                    getattr(
                        chunk,
                        "page_number",
                        None,
                    ),
                )
                for chunk in chunks
            }
        )

        retrieval_confidence = (
            self._retrieval_confidence(
                chunks
            )
        )

        rag_analysis = {
            "row_count": len(chunks),
            "retrieval_type": (
                "semantic_document_retrieval"
            ),
            "source_count": source_count,
            "page_count": page_count,
            "retrieval_confidence": (
                retrieval_confidence
            ),
        }

        # ----------------------------------------------------
        # 7. Final synthesis
        # ----------------------------------------------------

        synthesis = synthesize_answer(
            question=question,
            sql=None,
            result=rag_result,
            analysis=rag_analysis,
            visualization=None,
        )

        synthesis_confidence = (
            self._clamp_confidence(
                synthesis.get(
                    "confidence",
                    0.0,
                )
            )
        )

        confidence = self._combine_confidence(
            retrieval_confidence,
            synthesis_confidence,
        )

        # ----------------------------------------------------
        # 8. Response
        # ----------------------------------------------------

        return {
            "success": True,
            "mode": QueryMode.RAG.value,
            "question": question,
            "answer": synthesis["answer"],
            "key_points": synthesis["key_points"],
            "confidence": confidence,
            "sql": None,
            "sql_explanation": None,
            "result": self._json_safe(
                rag_result
            ),
            "analysis": self._json_safe(
                rag_analysis
            ),
            "visualization": None,
            "citations": self._json_safe(
                citations
            ),
            "document_context": context,
        }

    # ========================================================
    # HYBRID PIPELINE
    # ========================================================

    def _run_hybrid(
        self,
        question: str,
    ) -> dict[str, Any]:
        """
        Execute structured SQL and RAG evidence pipelines,
        then synthesize both into one response.
        """

        # ====================================================
        # STRUCTURED SIDE
        # ====================================================

        schema = get_latest_schema_context()

        if not schema:
            raise LookupError(
                "No active structured dataset is available."
            )

        generated = generate_sql(
            question=question,
            schema=schema,
        )

        sql = generated["sql"]

        execution = execute_dataset_query(
            sql
        )

        dataframe = self._extract_dataframe(
            execution
        )

        analysis = analyze_dataframe(
            dataframe
        )

        visualization = self._select_visualization(
            dataframe
        )

        safe_execution = (
            self._json_safe_execution(
                execution
            )
        )

        safe_analysis = self._json_safe(
            analysis
        )

        safe_visualization = self._json_safe(
            visualization
        )

        # ====================================================
        # RAG SIDE
        # ====================================================

        retrieved_chunks = (
            self._retrieve_rag_chunks(
                question
            )
        )

        chunks = self._compress_rag_chunks(
            retrieved_chunks
        )

        rag_context = self._build_rag_context(
            chunks
        )

        citations = self._build_rag_citations(
            chunks
        )

        # ====================================================
        # COMBINED RESULT
        # ====================================================

        combined_result = {
            **safe_execution,
            "document_context": rag_context,
            "document_retrieval_count": len(
                chunks
            ),
        }

        combined_analysis = {
            **safe_analysis,
            "document_retrieval_count": len(
                chunks
            ),
            "retrieval_type": (
                "hybrid_structured_and_semantic"
            ),
            "retrieval_confidence": (
                self._retrieval_confidence(
                    chunks
                )
            ),
        }

        # ====================================================
        # FINAL SYNTHESIS
        # ====================================================

        synthesis = synthesize_answer(
            question=question,
            sql=sql,
            result=combined_result,
            analysis=combined_analysis,
            visualization=safe_visualization,
        )

        # ====================================================
        # HYBRID CONFIDENCE
        # ====================================================

        sql_confidence = (
            generated.get(
                "confidence",
                0.0,
            )
        )

        synthesis_confidence = (
            synthesis.get(
                "confidence",
                0.0,
            )
        )

        if chunks:

            retrieval_confidence = (
                self._retrieval_confidence(
                    chunks
                )
            )

            confidence = min(
                self._clamp_confidence(
                    sql_confidence
                ),
                self._clamp_confidence(
                    synthesis_confidence
                ),
                retrieval_confidence,
            )

        else:

            # SQL can still answer the structured
            # portion if RAG finds no evidence.
            confidence = self._combine_confidence(
                sql_confidence,
                synthesis_confidence,
            )

        # ====================================================
        # RESPONSE
        # ====================================================

        return {
            "success": True,
            "mode": QueryMode.HYBRID.value,
            "question": question,
            "answer": synthesis["answer"],
            "key_points": synthesis["key_points"],
            "confidence": self._clamp_confidence(
                confidence
            ),
            "sql": sql,
            "sql_explanation": generated.get(
                "explanation"
            ),
            "result": safe_execution,
            "analysis": safe_analysis,
            "visualization": safe_visualization,
            "citations": self._json_safe(
                citations
            ),
            "document_context": rag_context,
        }

    # ========================================================
    # RAG RETRIEVAL PIPELINE
    # ========================================================

    def _retrieve_rag_chunks(
        self,
        question: str,
    ) -> list[Any]:
        """
        Retrieve the final candidate evidence.

        Primary retrieval is delegated to RAGRetriever.

        The orchestrator performs final safety normalization:

            Vector search
                ↓
            Similarity threshold
                ↓
            Exact chunk deduplication
                ↓
            Relevance sorting
                ↓
            Top-K
        """

        # ----------------------------------------------------
        # Retriever compatibility
        #
        # Current RAGRetriever implementations may or may not
        # expose a top_k argument. Keep the orchestrator
        # compatible with both forms.
        # ----------------------------------------------------

        try:
            chunks = self.rag_retriever.retrieve(
                question,
                top_k=RAG_TOP_K,
            )
        except TypeError:
            chunks = self.rag_retriever.retrieve(
                question
            )

        if not chunks:
            return []

        normalized: list[Any] = []

        seen_chunk_ids: set[str] = set()

        for chunk in chunks:

            # ------------------------------------------------
            # Ignore chunks without usable text.
            # ------------------------------------------------

            chunk_text = (
                getattr(
                    chunk,
                    "text",
                    None,
                )
                or ""
            ).strip()

            if not chunk_text:
                continue

            # ------------------------------------------------
            # Parse similarity score.
            # ------------------------------------------------

            try:
                score = float(
                    getattr(
                        chunk,
                        "score",
                        0.0,
                    )
                )
            except (
                TypeError,
                ValueError,
            ):
                continue

            # ------------------------------------------------
            # Similarity threshold.
            # ------------------------------------------------

            if score < RAG_SIMILARITY_THRESHOLD:
                continue

            # ------------------------------------------------
            # Exact chunk-ID deduplication.
            # ------------------------------------------------

            chunk_id = getattr(
                chunk,
                "chunk_id",
                None,
            )

            if chunk_id is not None:

                chunk_id_str = str(
                    chunk_id
                )

                if chunk_id_str in seen_chunk_ids:
                    continue

                seen_chunk_ids.add(
                    chunk_id_str
                )

            normalized.append(
                chunk
            )

        # ----------------------------------------------------
        # Highest relevance first.
        # ----------------------------------------------------

        normalized.sort(
            key=lambda chunk: float(
                getattr(
                    chunk,
                    "score",
                    0.0,
                )
            ),
            reverse=True,
        )

        return normalized[:RAG_TOP_K]

    # ========================================================
    # RAG DEDUPLICATION
    # ========================================================

    @classmethod
    def _deduplicate_chunks(
        cls,
        chunks: list[Any],
    ) -> list[Any]:
        """
        Remove exact and near-duplicate chunks.

        Near duplicates are compared using token-set Jaccard
        similarity.
        """

        selected: list[Any] = []

        seen_chunk_ids: set[str] = set()

        normalized_existing: list[str] = []

        for chunk in chunks:

            chunk_id = getattr(
                chunk,
                "chunk_id",
                None,
            )

            if chunk_id is not None:

                chunk_id_str = str(
                    chunk_id
                )

                if chunk_id_str in seen_chunk_ids:
                    continue

                seen_chunk_ids.add(
                    chunk_id_str
                )

            text = (
                getattr(
                    chunk,
                    "text",
                    None,
                )
                or ""
            ).strip()

            if not text:
                continue

            normalized = cls._normalize_text(
                text
            )

            if not normalized:
                continue

            duplicate = False

            for existing_normalized in normalized_existing:

                similarity = cls._text_similarity(
                    normalized,
                    existing_normalized,
                )

                if (
                    similarity
                    >= RAG_TEXT_OVERLAP_THRESHOLD
                ):
                    duplicate = True
                    break

            if duplicate:
                continue

            selected.append(
                chunk
            )

            normalized_existing.append(
                normalized
            )

        return selected

    # ========================================================
    # RAG PAGE COMPRESSION
    # ========================================================

    @classmethod
    def _compress_rag_chunks(
        cls,
        chunks: list[Any],
    ) -> list[Any]:
        """
        Merge useful chunks belonging to the same source/page.

        This prevents multiple chunks from the same page from
        becoming separate evidence blocks.

        Example:

            Page 5 chunk A
            Page 5 chunk B
            Page 3 chunk A
            Page 5 chunk C

        becomes:

            Page 5
            Page 3

        while preserving the strongest relevance score.
        """

        if not chunks:
            return []

        # ----------------------------------------------------
        # First remove exact / near duplicates.
        # ----------------------------------------------------

        deduplicated = cls._deduplicate_chunks(
            chunks
        )

        if not deduplicated:
            return []

        # ----------------------------------------------------
        # Group by source + page.
        # ----------------------------------------------------

        groups: dict[
            tuple[str | None, int | None],
            list[Any],
        ] = {}

        for chunk in deduplicated:

            source = getattr(
                chunk,
                "source_name",
                None,
            )

            page = getattr(
                chunk,
                "page_number",
                None,
            )

            key = (
                source,
                page,
            )

            groups.setdefault(
                key,
                [],
            ).append(
                chunk
            )

        compressed: list[Any] = []

        # ----------------------------------------------------
        # Process each source/page group.
        # ----------------------------------------------------

        for (
            source,
            page,
        ), group in groups.items():

            group.sort(
                key=lambda chunk: float(
                    getattr(
                        chunk,
                        "score",
                        0.0,
                    )
                ),
                reverse=True,
            )

            representative = group[0]

            text_blocks: list[str] = []

            seen_text: set[str] = set()

            for chunk in group:

                text = (
                    getattr(
                        chunk,
                        "text",
                        None,
                    )
                    or ""
                ).strip()

                if not text:
                    continue

                normalized = cls._normalize_text(
                    text
                )

                if not normalized:
                    continue

                # Exact normalized-text duplicate.
                if normalized in seen_text:
                    continue

                seen_text.add(
                    normalized
                )

                text_blocks.append(
                    text
                )

            if not text_blocks:
                continue

            # ------------------------------------------------
            # Single chunk:
            # preserve original object.
            # ------------------------------------------------

            if len(text_blocks) == 1:

                compressed.append(
                    representative
                )

                continue

            # ------------------------------------------------
            # Multiple chunks:
            # create a lightweight compressed object.
            # ------------------------------------------------

            class CompressedChunk:
                """
                Lightweight evidence object used internally
                by the orchestrator.
                """

            merged = CompressedChunk()

            merged.chunk_id = getattr(
                representative,
                "chunk_id",
                None,
            )

            merged.document_id = getattr(
                representative,
                "document_id",
                None,
            )

            merged.page_id = getattr(
                representative,
                "page_id",
                None,
            )

            merged.source_name = source

            merged.page_number = page

            merged.score = max(
                float(
                    getattr(
                        chunk,
                        "score",
                        0.0,
                    )
                )
                for chunk in group
            )

            merged.text = "\n\n".join(
                text_blocks
            )

            representative_metadata = (
                getattr(
                    representative,
                    "metadata",
                    {},
                )
                or {}
            )

            merged.metadata = {
                **representative_metadata,
                "compressed": True,
                "source_chunk_count": len(
                    group
                ),
            }

            compressed.append(
                merged
            )

        # ----------------------------------------------------
        # Strongest pages first.
        # ----------------------------------------------------

        compressed.sort(
            key=lambda chunk: float(
                getattr(
                    chunk,
                    "score",
                    0.0,
                )
            ),
            reverse=True,
        )

        # ----------------------------------------------------
        # Maximum page/context count.
        # ----------------------------------------------------

        return compressed[
            :RAG_MAX_CONTEXTS
        ]

    # ========================================================
    # SOURCE / PAGE DIVERSITY
    # ========================================================

    @staticmethod
    def _apply_source_page_diversity(
        chunks: list[Any],
    ) -> list[Any]:
        """
        Prefer evidence from different pages/sources.

        This method is retained for compatibility with existing
        tests/callers. Page compression is now the preferred
        production path.
        """

        if not chunks:
            return []

        selected: list[Any] = []

        seen_pages: set[
            tuple[str | None, int | None]
        ] = set()

        # ----------------------------------------------------
        # First pass: unique source/page groups.
        # ----------------------------------------------------

        for chunk in chunks:

            source = getattr(
                chunk,
                "source_name",
                None,
            )

            page = getattr(
                chunk,
                "page_number",
                None,
            )

            key = (
                source,
                page,
            )

            if key in seen_pages:
                continue

            seen_pages.add(
                key
            )

            selected.append(
                chunk
            )

            if len(selected) >= RAG_MAX_CONTEXTS:
                break

        # ----------------------------------------------------
        # Second pass:
        # fill remaining slots only if necessary.
        # ----------------------------------------------------

        if len(selected) < RAG_TOP_K:

            for chunk in chunks:

                if chunk in selected:
                    continue

                selected.append(
                    chunk
                )

                if len(selected) >= RAG_TOP_K:
                    break

        return selected

    # ========================================================
    # TEXT NORMALIZATION
    # ========================================================

    @staticmethod
    def _normalize_text(
        value: str,
    ) -> str:
        """
        Normalize text for duplicate detection.
        """

        value = value.lower()

        value = re.sub(
            r"\s+",
            " ",
            value,
        )

        value = re.sub(
            r"[^\w\s]",
            "",
            value,
        )

        return value.strip()

    # ========================================================
    # TEXT SIMILARITY
    # ========================================================

    @staticmethod
    def _text_similarity(
        first: str,
        second: str,
    ) -> float:
        """
        Calculate token-set Jaccard similarity.
        """

        if not first or not second:
            return 0.0

        if first == second:
            return 1.0

        first_words = set(
            first.split()
        )

        second_words = set(
            second.split()
        )

        if not first_words or not second_words:
            return 0.0

        intersection = len(
            first_words
            & second_words
        )

        union = len(
            first_words
            | second_words
        )

        if union == 0:
            return 0.0

        return (
            intersection
            / union
        )

    # ========================================================
    # RAG CITATIONS
    # ========================================================

    @staticmethod
    def _build_rag_citations(
        chunks: list[Any],
    ) -> list[dict[str, Any]]:
        """
        Build one citation per unique source/page.

        Multiple chunks from the same page are represented
        by a single citation using the strongest score.
        """

        if not chunks:
            return []

        grouped: dict[
            tuple[str | None, int | None],
            Any,
        ] = {}

        for chunk in chunks:

            source = getattr(
                chunk,
                "source_name",
                None,
            )

            page = getattr(
                chunk,
                "page_number",
                None,
            )

            key = (
                source,
                page,
            )

            current = grouped.get(
                key
            )

            if current is None:

                grouped[key] = chunk

                continue

            try:
                current_score = float(
                    getattr(
                        current,
                        "score",
                        0.0,
                    )
                    or 0.0
                )
            except (
                TypeError,
                ValueError,
            ):
                current_score = 0.0

            try:
                new_score = float(
                    getattr(
                        chunk,
                        "score",
                        0.0,
                    )
                    or 0.0
                )
            except (
                TypeError,
                ValueError,
            ):
                new_score = 0.0

            if new_score > current_score:
                grouped[key] = chunk

        citations = [
            QueryOrchestrator._chunk_citation(
                chunk
            )
            for chunk in grouped.values()
        ]

        citations.sort(
            key=lambda citation: float(
                citation.get(
                    "score",
                    0.0,
                )
                or 0.0
            ),
            reverse=True,
        )

        return citations

    # ========================================================
    # EMPTY RAG RESPONSE
    # ========================================================

    @staticmethod
    def _empty_rag_response(
        question: str,
    ) -> dict[str, Any]:
        """
        Return a successful but low-confidence RAG response
        when no sufficiently relevant evidence exists.
        """

        return {
            "success": True,
            "mode": QueryMode.RAG.value,
            "question": question,
            "answer": (
                "I couldn't find sufficiently relevant "
                "information in the uploaded documents "
                "to answer that question reliably."
            ),
            "key_points": [],
            "confidence": 0.0,
            "sql": None,
            "sql_explanation": None,
            "result": {
                "row_count": 0,
                "retrieval_type": (
                    "semantic_document_retrieval"
                ),
                "rows": [],
                "document_context": "",
            },
            "analysis": {
                "row_count": 0,
                "retrieval_type": (
                    "semantic_document_retrieval"
                ),
                "source_count": 0,
                "page_count": 0,
                "retrieval_confidence": 0.0,
            },
            "visualization": None,
            "citations": [],
            "document_context": "",
        }

    # ========================================================
    # QUESTION VALIDATION
    # ========================================================

    @staticmethod
    def _validate_question(
        question: str,
    ) -> str:
        """
        Validate and normalize an incoming question.
        """

        if not isinstance(
            question,
            str,
        ):
            raise TypeError(
                "Question must be a string."
            )

        question = question.strip()

        if not question:
            raise ValueError(
                "Question cannot be empty."
            )

        if len(question) > 4000:
            raise ValueError(
                "Question is too long. "
                "Maximum length is 4000 characters."
            )

        return question

    # ========================================================
    # DATAFRAME EXTRACTION
    # ========================================================

    @staticmethod
    def _extract_dataframe(
        execution: Any,
    ) -> pd.DataFrame:
        """
        Extract a DataFrame from a query execution result.
        """

        if isinstance(
            execution,
            pd.DataFrame,
        ):
            return execution

        if isinstance(
            execution,
            dict,
        ):

            dataframe = execution.get(
                "dataframe"
            )

            if isinstance(
                dataframe,
                pd.DataFrame,
            ):
                return dataframe

            rows = execution.get(
                "rows"
            )

            if isinstance(
                rows,
                list,
            ):
                return pd.DataFrame(
                    rows
                )

        raise TypeError(
            "Unable to extract a pandas DataFrame "
            "from query execution result."
        )

    # ========================================================
    # VISUALIZATION
    # ========================================================

    @staticmethod
    def _select_visualization(
        dataframe: pd.DataFrame,
    ) -> dict[str, Any] | None:
        """
        Select a visualization deterministically.
        """

        if dataframe.empty:
            return None

        try:

            result = select_chart(
                dataframe
            )

            if result is None:
                return None

            if isinstance(
                result,
                dict,
            ):
                return result

            if hasattr(
                result,
                "model_dump",
            ):
                return result.model_dump()

            if hasattr(
                result,
                "__dict__",
            ):
                return dict(
                    result.__dict__
                )

            return {
                "type": str(
                    result
                )
            }

        except Exception:
            # Visualization must never cause an otherwise
            # valid analytical query to fail.
            return None

    # ========================================================
    # RAG CONTEXT
    # ========================================================

    @staticmethod
    def _build_rag_context(
        chunks: list[Any],
    ) -> str:
        """
        Build the exact context passed to the synthesis layer.

        Every context block corresponds to one final source/page
        evidence group.
        """

        if not chunks:
            return ""

        sections: list[str] = []

        for index, chunk in enumerate(
            chunks,
            start=1,
        ):

            source = (
                getattr(
                    chunk,
                    "source_name",
                    None,
                )
                or "Unknown source"
            )

            page = getattr(
                chunk,
                "page_number",
                None,
            )

            try:
                score = float(
                    getattr(
                        chunk,
                        "score",
                        0.0,
                    )
                )
            except (
                TypeError,
                ValueError,
            ):
                score = 0.0

            text = (
                getattr(
                    chunk,
                    "text",
                    None,
                )
                or ""
            ).strip()

            if not text:
                continue

            sections.append(
                (
                    f"[Context {index}]\n"
                    f"Source: {source}\n"
                    f"Page: "
                    f"{page if page is not None else 'Unknown'}\n"
                    f"Relevance: {score:.4f}\n"
                    f"Text:\n{text}"
                )
            )

        return "\n\n".join(
            sections
        )

    # ========================================================
    # CHUNK CITATION
    # ========================================================

    @staticmethod
    def _chunk_citation(
        chunk: Any,
    ) -> dict[str, Any]:
        """
        Convert a chunk into a JSON-safe citation payload.
        """

        return {
            "chunk_id": QueryOrchestrator._json_safe(
                getattr(
                    chunk,
                    "chunk_id",
                    None,
                )
            ),
            "document_id": QueryOrchestrator._json_safe(
                getattr(
                    chunk,
                    "document_id",
                    None,
                )
            ),
            "page_id": QueryOrchestrator._json_safe(
                getattr(
                    chunk,
                    "page_id",
                    None,
                )
            ),
            "source": getattr(
                chunk,
                "source_name",
                None,
            ),
            "page": getattr(
                chunk,
                "page_number",
                None,
            ),
            "score": QueryOrchestrator._json_safe(
                getattr(
                    chunk,
                    "score",
                    None,
                )
            ),
        }

    # ========================================================
    # RETRIEVAL CONFIDENCE
    # ========================================================

    @staticmethod
    def _retrieval_confidence(
        chunks: list[Any],
    ) -> float:
        """
        Calculate confidence from the final source/page evidence.

        Factors:

        - strongest similarity
        - average top similarity
        - margin above retrieval threshold
        - page diversity
        - source diversity

        The calculation is deliberately conservative.
        """

        if not chunks:
            return 0.0

        scores: list[float] = []

        sources: set[str] = set()

        pages: set[
            tuple[str | None, int | None]
        ] = set()

        for chunk in chunks:

            try:
                score = float(
                    getattr(
                        chunk,
                        "score",
                        0.0,
                    )
                )
            except (
                TypeError,
                ValueError,
            ):
                continue

            score = max(
                0.0,
                min(
                    1.0,
                    score,
                ),
            )

            scores.append(
                score
            )

            source = getattr(
                chunk,
                "source_name",
                None,
            )

            page = getattr(
                chunk,
                "page_number",
                None,
            )

            if source:
                sources.add(
                    str(source)
                )

            pages.add(
                (
                    source,
                    page,
                )
            )

        if not scores:
            return 0.0

        scores.sort(
            reverse=True
        )

        best = scores[0]

        top_scores = scores[
            :min(
                3,
                len(scores),
            )
        ]

        average_score = (
            sum(top_scores)
            / len(top_scores)
        )

        # Normalize how far the strongest score is above
        # the configured threshold.
        threshold_margin = max(
            0.0,
            min(
                1.0,
                (
                    best
                    - RAG_SIMILARITY_THRESHOLD
                )
                / max(
                    1e-9,
                    1.0
                    - RAG_SIMILARITY_THRESHOLD,
                ),
            ),
        )

        # Diversity contributes to confidence but cannot
        # compensate for weak similarity.
        page_diversity = min(
            1.0,
            len(pages) / 3,
        )

        source_diversity = min(
            1.0,
            len(sources) / 2,
        )

        diversity = (
            0.6 * page_diversity
            + 0.4 * source_diversity
        )

        confidence = (
            0.35 * best
            + 0.25 * average_score
            + 0.25 * threshold_margin
            + 0.15 * diversity
        )

        return round(
            max(
                0.0,
                min(
                    1.0,
                    confidence,
                ),
            ),
            4,
        )

    # ========================================================
    # CONFIDENCE
    # ========================================================

    @staticmethod
    def _clamp_confidence(
        value: float,
    ) -> float:
        """
        Clamp confidence to [0, 1].
        """

        try:
            value = float(
                value
            )
        except (
            TypeError,
            ValueError,
        ):
            return 0.0

        return round(
            max(
                0.0,
                min(
                    1.0,
                    value,
                ),
            ),
            4,
        )

    @classmethod
    def _combine_confidence(
        cls,
        first: float,
        second: float,
    ) -> float:
        """
        Conservative confidence combination.

        The final confidence cannot exceed the weakest
        component.
        """

        first = cls._clamp_confidence(
            first
        )

        second = cls._clamp_confidence(
            second
        )

        return round(
            min(
                first,
                second,
            ),
            4,
        )

    # ========================================================
    # JSON SAFETY
    # ========================================================

    @classmethod
    def _json_safe(
        cls,
        value: Any,
    ) -> Any:
        """
        Recursively convert database/Pandas values into
        JSON-compatible Python values.
        """

        if value is None:
            return None

        if isinstance(
            value,
            Decimal,
        ):
            return float(
                value
            )

        if isinstance(
            value,
            datetime,
        ):
            return value.isoformat()

        if isinstance(
            value,
            date,
        ):
            return value.isoformat()

        if isinstance(
            value,
            pd.Timestamp,
        ):
            return value.isoformat()

        if isinstance(
            value,
            pd.DataFrame,
        ):

            return [
                {
                    str(key): cls._json_safe(
                        item
                    )
                    for key, item in row.items()
                }
                for row in value.to_dict(
                    orient="records"
                )
            ]

        if hasattr(
            value,
            "model_dump",
        ):

            return cls._json_safe(
                value.model_dump()
            )

        if isinstance(
            value,
            dict,
        ):

            return {
                str(key): cls._json_safe(
                    item
                )
                for key, item in value.items()
            }

        if isinstance(
            value,
            (list, tuple),
        ):

            return [
                cls._json_safe(
                    item
                )
                for item in value
            ]

        if hasattr(
            value,
            "item",
        ):

            try:
                return cls._json_safe(
                    value.item()
                )
            except Exception:
                pass

        # Avoid blindly serializing arbitrary objects
        # such as database connections.
        if hasattr(
            value,
            "__dict__",
        ) and not isinstance(
            value,
            (
                str,
                int,
                float,
                bool,
            ),
        ):

            return {
                str(key): cls._json_safe(
                    item
                )
                for key, item in value.__dict__.items()
            }

        return value

    # ========================================================
    # EXECUTION RESULT SAFETY
    # ========================================================

    @classmethod
    def _json_safe_execution(
        cls,
        execution: Any,
    ) -> dict[str, Any]:
        """
        Convert SQL execution results into a stable,
        JSON-compatible result object.
        """

        if isinstance(
            execution,
            pd.DataFrame,
        ):

            dataframe = execution

            rows = dataframe.to_dict(
                orient="records"
            )

            return {
                "columns": [
                    str(column)
                    for column in dataframe.columns
                ],
                "rows": [
                    cls._json_safe(
                        row
                    )
                    for row in rows
                ],
                "row_count": len(
                    dataframe
                ),
            }

        if not isinstance(
            execution,
            dict,
        ):

            return {
                "columns": [],
                "rows": [],
                "row_count": 0,
            }

        result = {
            str(key): cls._json_safe(
                value
            )
            for key, value in execution.items()
            if key != "dataframe"
        }

        dataframe = execution.get(
            "dataframe"
        )

        if isinstance(
            dataframe,
            pd.DataFrame,
        ):

            result["columns"] = [
                str(column)
                for column in dataframe.columns
            ]

            result["rows"] = [
                cls._json_safe(
                    row
                )
                for row in dataframe.to_dict(
                    orient="records"
                )
            ]

            result["row_count"] = len(
                dataframe
            )

        elif isinstance(
            result.get(
                "rows"
            ),
            list,
        ):

            result["rows"] = [
                cls._json_safe(
                    row
                )
                for row in result["rows"]
            ]

            result.setdefault(
                "columns",
                [],
            )

            result.setdefault(
                "row_count",
                len(
                    result["rows"]
                ),
            )

        else:

            result.setdefault(
                "columns",
                [],
            )

            result.setdefault(
                "rows",
                [],
            )

            result.setdefault(
                "row_count",
                0,
            )

        return result