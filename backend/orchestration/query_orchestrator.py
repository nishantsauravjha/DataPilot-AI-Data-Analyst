from __future__ import annotations

from typing import Any

from decimal import Decimal
from datetime import date, datetime

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


class QueryOrchestrator:
    """
    Central orchestration layer for DataPilot.

    Supported execution modes:

        STRUCTURED
            Question
                ↓
            Schema retrieval
                ↓
            LLM → SQL
                ↓
            SQL validation/execution
                ↓
            Pandas analysis
                ↓
            Visualization
                ↓
            Final synthesis

        RAG
            Question
                ↓
            Vector retrieval
                ↓
            Retrieved document chunks
                ↓
            Final synthesis

        HYBRID
            Question
                ↓
            ┌───────────────┬───────────────┐
            │               │               │
         SQL path        RAG path          │
            │               │               │
            └───────┬───────┘               │
                    ↓
               Final synthesis

    The orchestrator intentionally does not implement:

        - SQL generation internals
        - SQL validation
        - SQL execution
        - embedding generation
        - vector database operations
        - LLM prompt internals
        - chart generation internals

    Those responsibilities belong to dedicated modules.
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
        Route and execute a user question.
        """

        question = self._validate_question(question)

        mode = route_query(question)

        if mode == QueryMode.STRUCTURED:
            return self._run_structured(question)

        if mode == QueryMode.RAG:
            return self._run_rag(question)

        if mode == QueryMode.HYBRID:
            return self._run_hybrid(question)

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
        # 2. Execute validated read-only SQL
        # ----------------------------------------------------

        execution = execute_dataset_query(sql)

        # ----------------------------------------------------
        # 3. Convert result to DataFrame
        # ----------------------------------------------------

        dataframe = self._extract_dataframe(execution)

        # ----------------------------------------------------
        # 4. Deterministic analysis
        # ----------------------------------------------------

        analysis = analyze_dataframe(dataframe)

        # ----------------------------------------------------
        # 5. Visualization selection
        # ----------------------------------------------------

        visualization = self._select_visualization(
            dataframe
        )

        # ----------------------------------------------------
        # 6. Final answer synthesis
        # ----------------------------------------------------

        safe_execution = self._json_safe_execution(
            execution
        )

        safe_analysis = self._json_safe(
            analysis
        )

        safe_visualization = self._json_safe(
            visualization
        )

        synthesis = synthesize_answer(
            question=question,
            sql=sql,
            result=safe_execution,
            analysis=safe_analysis,
            visualization=safe_visualization,
        )

        # ----------------------------------------------------
        # 7. Unified API response
        # ----------------------------------------------------

        return {
            "success": True,
            "mode": QueryMode.STRUCTURED.value,
            "question": question,

            "answer": synthesis["answer"],
            "key_points": synthesis["key_points"],

            "confidence": self._combine_confidence(
                generated.get("confidence", 0.0),
                synthesis.get("confidence", 0.0),
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
        Execute the pure semantic/document RAG pipeline.

        Important contract:

            sql = None

        RAG does not generate or execute SQL.
        """

        chunks = self.rag_retriever.retrieve(question)

        if not chunks:
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
                    "retrieval_type": "semantic_document_retrieval",
                    "rows": [],
                },
                "analysis": {
                    "row_count": 0,
                    "retrieval_type": "semantic_document_retrieval",
                    "source_count": 0,
                },
                "visualization": None,
                "citations": [],
                "document_context": "",
            }

        # ----------------------------------------------------
        # No relevant documents
        # ----------------------------------------------------

        if not chunks:
            return {
                "success": True,
                "mode": QueryMode.RAG.value,
                "question": question,

                "answer": (
                    "I could not find relevant information "
                    "in the indexed documents."
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
                },

                "visualization": None,
                "citations": [],
                "document_context": "",
            }

        # ----------------------------------------------------
        # Build document context
        # ----------------------------------------------------

        context = self._build_rag_context(
            chunks
        )

        # ----------------------------------------------------
        # Build citations
        # ----------------------------------------------------

        citations = [
            self._chunk_citation(chunk)
            for chunk in chunks
        ]

        # ----------------------------------------------------
        # Build normalized RAG result
        # ----------------------------------------------------

        rag_rows = [
            {
                "source": chunk.source_name,
                "page": chunk.page_number,
                "score": chunk.score,
                "text": chunk.text,
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

        # ----------------------------------------------------
        # RAG analysis metadata
        # ----------------------------------------------------

        source_count = len(
            {
                chunk.source_name
                for chunk in chunks
                if chunk.source_name
            }
        )

        rag_analysis = {
            "row_count": len(chunks),
            "retrieval_type": (
                "semantic_document_retrieval"
            ),
            "source_count": source_count,
        }

        # ----------------------------------------------------
        # Final synthesis
        #
        # CRITICAL:
        #
        # Pure RAG passes sql=None.
        #
        # We must never pass an empty SQL string because
        # empty SQL is not meaningful for the semantic path.
        # ----------------------------------------------------

        synthesis = synthesize_answer(
            question=question,
            sql=None,
            result=rag_result,
            analysis=rag_analysis,
            visualization=None,
        )

        retrieval_confidence = self._retrieval_confidence(
            chunks
        )
        synthesis_confidence = float(
            synthesis.get(
                "confidence",
                0.0,
            )
        )
        confidence = round(
            min(
                retrieval_confidence,
                synthesis_confidence,
            ),
            4,
        )

        # ----------------------------------------------------
        # Final RAG response
        # ----------------------------------------------------

        return {
            "success": True,
            "mode": QueryMode.RAG.value,
            "question": question,

            "answer": synthesis["answer"],
            "key_points": synthesis["key_points"],

            "confidence": self._clamp_confidence(
                confidence
            ),

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
        Execute both structured and semantic retrieval.

        SQL results remain authoritative for numerical/
        tabular facts.

        Document context is supplied as supporting semantic
        evidence.
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

        safe_execution = self._json_safe_execution(
            execution
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

        chunks = self.rag_retriever.retrieve(
            question
        )

        rag_context = self._build_rag_context(
            chunks
        )

        citations = [
            self._chunk_citation(chunk)
            for chunk in chunks
        ]

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
        # FINAL RESPONSE
        # ====================================================

        return {
            "success": True,
            "mode": QueryMode.HYBRID.value,
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

            "citations": self._json_safe(
                citations
            ),

            "document_context": rag_context,
        }

    # ========================================================
    # VALIDATION
    # ========================================================
    
    @staticmethod
    def _retrieval_confidence(
        chunks: list[Any],
    ) -> float:

        if not chunks:
            return 0.0

        scores = [
            max(
                0.0,
                min(
                    1.0,
                    float(chunk.score),
                ),
            )
            for chunk in chunks
        ]

        # Weighted toward the strongest evidence.
        best = max(scores)

        if len(scores) == 1:
            return round(best, 4)

        average = sum(scores) / len(scores)

        confidence = (
            0.65 * best
            + 0.35 * average
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


    @staticmethod
    def _validate_question(
        question: str,
    ) -> str:
        """
        Validate and normalize the incoming question.
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
    # DATAFRAME NORMALIZATION
    # ========================================================

    @staticmethod
    def _extract_dataframe(
        execution: Any,
    ) -> pd.DataFrame:
        """
        Normalize execute_dataset_query() output
        into a pandas DataFrame.
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
        Visualization is best-effort.

        A chart failure must never make a valid SQL
        query fail.
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
                "type": str(result)
            }

        except Exception:
            return None

    # ========================================================
    # RAG CONTEXT
    # ========================================================

    @staticmethod
    def _build_rag_context(
        chunks: list[Any],
    ) -> str:
        """
        Convert retrieved chunks into deterministic,
        citation-friendly context for the LLM.
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

            page_number = getattr(
                chunk,
                "page_number",
                None,
            )

            page = (
                str(page_number)
                if page_number is not None
                else "Unknown"
            )

            score = getattr(
                chunk,
                "score",
                0.0,
            )

            text = (
                getattr(
                    chunk,
                    "text",
                    None,
                )
                or ""
            )

            sections.append(
                (
                    f"[Context {index}]\n"
                    f"Source: {source}\n"
                    f"Page: {page}\n"
                    f"Relevance: {float(score):.4f}\n"
                    f"Text:\n{text}"
                )
            )

        return "\n\n".join(
            sections
        )

    # ========================================================
    # CITATIONS
    # ========================================================

    @staticmethod
    def _chunk_citation(
        chunk: Any,
    ) -> dict[str, Any]:
        """
        Convert a retrieved RAG chunk into a stable
        citation object.
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
    # CONFIDENCE
    # ========================================================

    @staticmethod
    def _clamp_confidence(
        value: float,
    ) -> float:
        """
        Ensure confidence is always in [0, 1].
        """

        try:
            value = float(value)
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

        The final confidence cannot exceed the weaker
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

        if value is None:
            return None

        if isinstance(value, Decimal):
            return float(value)

        if isinstance(value, datetime):
            return value.isoformat()

        if isinstance(value, date):
            return value.isoformat()

        if isinstance(value, pd.Timestamp):
            return value.isoformat()

        if isinstance(value, pd.DataFrame):
            return [
                {
                    str(key): cls._json_safe(item)
                    for key, item in row.items()
                }
                for row in value.to_dict(
                    orient="records"
                )
            ]

        if hasattr(value, "model_dump"):
            return cls._json_safe(
                value.model_dump()
            )

        if isinstance(value, dict):
            return {
                str(key): cls._json_safe(item)
                for key, item in value.items()
            }

        if isinstance(value, (list, tuple)):
            return [
                cls._json_safe(item)
                for item in value
            ]

        if hasattr(value, "item"):
            try:
                return cls._json_safe(
                    value.item()
                )
            except Exception:
                pass

        if hasattr(value, "__dict__") and not isinstance(
            value,
            (
                str,
                int,
                float,
                bool,
            ),
        ):
            return {
                str(key): cls._json_safe(item)
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
        if isinstance(execution, pd.DataFrame):
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
                    cls._json_safe(row)
                    for row in rows
                ],
                "row_count": len(dataframe),
            }

        if not isinstance(execution, dict):
            return {
                "rows": [],
                "row_count": 0,
            }

        result = {
            str(key): cls._json_safe(value)
            for key, value in execution.items()
            if key != "dataframe"
        }

        dataframe = execution.get(
            "dataframe"
        )

        if isinstance(dataframe, pd.DataFrame):
            result["columns"] = [
                str(column)
                for column in dataframe.columns
            ]

            result["rows"] = [
                cls._json_safe(row)
                for row in dataframe.to_dict(
                    orient="records"
                )
            ]

            result["row_count"] = len(
                dataframe
            )

        elif isinstance(
            result.get("rows"),
            list,
        ):
            result["rows"] = [
                cls._json_safe(row)
                for row in result["rows"]
            ]

            result.setdefault(
                "row_count",
                len(result["rows"]),
            )

        return result