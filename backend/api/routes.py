from __future__ import annotations

import logging
import time
from pathlib import Path
from typing import Any
from uuid import uuid4

from fastapi import APIRouter, File, HTTPException, Request, UploadFile, status
from pydantic import BaseModel, ConfigDict, Field, field_validator

from backend.orchestration.query_orchestrator import QueryOrchestrator
from backend.services.ingestion_service import ingest_dataset


# ============================================================
# Logging
# ============================================================

logger = logging.getLogger(__name__)


# ============================================================
# Router
# ============================================================

router = APIRouter(
    prefix="/api/v1",
    tags=["DataPilot"],
)


query_orchestrator = QueryOrchestrator()


# ============================================================
# Configuration
# ============================================================

UPLOAD_DIR = Path("data/uploads")
UPLOAD_DIR.mkdir(
    parents=True,
    exist_ok=True,
)

ALLOWED_EXTENSIONS = {
    ".csv",
    ".xlsx",
    ".xls",
}

# Protect the API from accidentally receiving huge uploads.
MAX_UPLOAD_SIZE = 50 * 1024 * 1024  # 50 MB


# ============================================================
# Request Models
# ============================================================


class QueryRequest(BaseModel):
    """
    Request body for natural-language data queries.
    """

    model_config = ConfigDict(
        extra="forbid",
    )

    question: str = Field(
        ...,
        min_length=1,
        max_length=5000,
        description="Natural-language question about the uploaded data or documents.",
        examples=[
            "Which product generated the highest revenue?"
        ],
    )

    @field_validator("question")
    @classmethod
    def validate_question(
        cls,
        value: str,
    ) -> str:
        value = value.strip()

        if not value:
            raise ValueError(
                "Question cannot be empty."
            )

        return value


# ============================================================
# Response Models
# ============================================================


class QueryResponse(BaseModel):
    """
    Stable public API response contract.

    The orchestrator may internally produce additional
    information, but the API guarantees these fields.
    """

    model_config = ConfigDict(
        extra="allow",
    )

    success: bool = True
    mode: str
    question: str

    answer: str | None = None
    key_points: list[str] = Field(
        default_factory=list,
    )

    confidence: float | None = None

    sql: str | None = None
    sql_explanation: str | None = None

    result: dict[str, Any] | None = None
    analysis: dict[str, Any] | None = None
    visualization: dict[str, Any] | None = None

    citations: list[dict[str, Any]] = Field(
        default_factory=list,
    )

    request_id: str | None = None
    latency_ms: float | None = None


class UploadResponse(BaseModel):
    """
    Stable dataset upload response.
    """

    success: bool = True
    message: str
    data: dict[str, Any]


class ErrorResponse(BaseModel):
    """
    Standard API error structure.

    FastAPI will still return its normal HTTP status code.
    """

    success: bool = False
    error: str
    request_id: str


# ============================================================
# Helpers
# ============================================================


def _request_id() -> str:
    """
    Generate a short unique request identifier.
    """

    return uuid4().hex[:16]


def _normalize_query_response(
    result: dict[str, Any],
    *,
    question: str,
    request_id: str,
    latency_ms: float,
) -> dict[str, Any]:
    """
    Normalize the orchestrator output into the public API contract.

    This protects the API from small internal response changes.
    """

    if not isinstance(result, dict):
        raise RuntimeError(
            "Query orchestrator returned an invalid response."
        )

    normalized = {
        "success": bool(
            result.get("success", True)
        ),
        "mode": result.get(
            "mode",
            "unknown",
        ),
        "question": result.get(
            "question",
            question,
        ),
        "answer": result.get("answer"),
        "key_points": result.get(
            "key_points",
            [],
        ),
        "confidence": result.get(
            "confidence"
        ),
        "sql": result.get("sql"),
        "sql_explanation": result.get(
            "sql_explanation"
        ),
        "result": result.get("result"),
        "analysis": result.get("analysis"),
        "visualization": result.get(
            "visualization"
        ),
        "citations": result.get(
            "citations",
            [],
        ),
        "request_id": request_id,
        "latency_ms": round(
            latency_ms,
            2,
        ),
    }

    return normalized


def _safe_error_message(
    exc: Exception,
) -> str:
    """
    Convert internal exceptions into user-safe messages.

    We deliberately avoid returning database credentials,
    SQL internals, stack traces, or provider-specific details.
    """

    if isinstance(exc, LookupError):
        return str(exc) or "Requested resource was not found."

    if isinstance(exc, ValueError):
        return str(exc) or "Invalid request."

    return "An internal error occurred while processing the request."


# ============================================================
# Dataset Upload
# ============================================================


@router.post(
    "/datasets/upload",
    response_model=UploadResponse,
    status_code=status.HTTP_200_OK,
    summary="Upload a structured dataset",
    description=(
        "Upload a CSV or Excel dataset and ingest it into "
        "DataPilot's structured-data pipeline."
    ),
)
async def upload_dataset(
    request: Request,
    file: UploadFile = File(...),
):
    """
    Dataset ingestion pipeline:

        Upload
          ↓
        Validate
          ↓
        Store temporarily
          ↓
        Pandas
          ↓
        Profile
          ↓
        PostgreSQL
          ↓
        Metadata
    """

    request_id = _request_id()
    started_at = time.perf_counter()

    original_filename = (
        file.filename or ""
    ).strip()

    if not original_filename:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail={
                "success": False,
                "error": "Filename is required.",
                "request_id": request_id,
            },
        )

    extension = Path(
        original_filename
    ).suffix.lower()

    if extension not in ALLOWED_EXTENSIONS:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail={
                "success": False,
                "error": (
                    "Unsupported file type. "
                    "Upload CSV, XLSX, or XLS."
                ),
                "request_id": request_id,
            },
        )

    # Never trust the original filename for the temporary path.
    safe_filename = (
        f"{uuid4().hex}"
        f"{extension}"
    )

    file_path = (
        UPLOAD_DIR /
        safe_filename
    )

    logger.info(
        "Dataset upload started "
        "request_id=%s filename=%s extension=%s",
        request_id,
        original_filename,
        extension,
    )

    try:
        contents = await file.read()

        if not contents:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail={
                    "success": False,
                    "error": "Uploaded file is empty.",
                    "request_id": request_id,
                },
            )

        if len(contents) > MAX_UPLOAD_SIZE:
            raise HTTPException(
                status_code=status.HTTP_413_REQUEST_ENTITY_TOO_LARGE,
                detail={
                    "success": False,
                    "error": (
                        "Uploaded file is too large. "
                        "Maximum allowed size is 50 MB."
                    ),
                    "request_id": request_id,
                },
            )

        file_path.write_bytes(
            contents
        )

        result = ingest_dataset(
            file_path
        )

        latency_ms = (
            time.perf_counter()
            - started_at
        ) * 1000

        logger.info(
            "Dataset upload completed "
            "request_id=%s filename=%s "
            "size_bytes=%s latency_ms=%.2f",
            request_id,
            original_filename,
            len(contents),
            latency_ms,
        )

        return {
            "success": True,
            "message": (
                "Dataset ingested successfully."
            ),
            "data": result,
        }

    except HTTPException:
        raise

    except FileNotFoundError as exc:
        logger.exception(
            "Dataset ingestion file error "
            "request_id=%s",
            request_id,
        )

        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail={
                "success": False,
                "error": "Uploaded file could not be processed.",
                "request_id": request_id,
            },
        ) from exc

    except ValueError as exc:
        logger.warning(
            "Dataset validation failed "
            "request_id=%s error=%s",
            request_id,
            exc,
        )

        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail={
                "success": False,
                "error": str(exc),
                "request_id": request_id,
            },
        ) from exc

    except Exception as exc:
        logger.exception(
            "Dataset ingestion failed "
            "request_id=%s",
            request_id,
        )

        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail={
                "success": False,
                "error": (
                    "Dataset ingestion failed. "
                    "Please try again."
                ),
                "request_id": request_id,
            },
        ) from exc

    finally:
        if file_path.exists():
            try:
                file_path.unlink()
            except OSError:
                logger.warning(
                    "Unable to remove temporary upload "
                    "request_id=%s path=%s",
                    request_id,
                    file_path,
                )

        await file.close()


# ============================================================
# Natural Language Query
# ============================================================


@router.post(
    "/query",
    response_model=QueryResponse,
    status_code=status.HTTP_200_OK,
    summary="Ask DataPilot a question",
    description=(
        "Ask a natural-language question about uploaded "
        "structured or unstructured data."
    ),
)
def query_dataset(
    request: QueryRequest,
    http_request: Request,
):
    """
    Unified DataPilot query endpoint.

    Pipeline:

        Question
            ↓
        Router
            ↓
        Structured / RAG / Hybrid
            ↓
        Processing
            ↓
        Stable API Response
    """

    request_id = _request_id()
    started_at = time.perf_counter()

    question = request.question.strip()

    logger.info(
        "Query started "
        "request_id=%s method=%s path=%s question=%s",
        request_id,
        http_request.method,
        http_request.url.path,
        question[:300],
    )

    try:
        result = query_orchestrator.query(
            question
        )

        latency_ms = (
            time.perf_counter()
            - started_at
        ) * 1000

        response = _normalize_query_response(
            result,
            question=question,
            request_id=request_id,
            latency_ms=latency_ms,
        )

        logger.info(
            "Query completed "
            "request_id=%s mode=%s latency_ms=%.2f",
            request_id,
            response["mode"],
            latency_ms,
        )

        return response

    except LookupError as exc:
        latency_ms = (
            time.perf_counter()
            - started_at
        ) * 1000

        logger.warning(
            "Query resource not found "
            "request_id=%s latency_ms=%.2f error=%s",
            request_id,
            latency_ms,
            exc,
        )

        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail={
                "success": False,
                "error": _safe_error_message(exc),
                "request_id": request_id,
            },
        ) from exc

    except ValueError as exc:
        latency_ms = (
            time.perf_counter()
            - started_at
        ) * 1000

        logger.warning(
            "Query validation failed "
            "request_id=%s latency_ms=%.2f error=%s",
            request_id,
            latency_ms,
            exc,
        )

        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail={
                "success": False,
                "error": _safe_error_message(exc),
                "request_id": request_id,
            },
        ) from exc

    except Exception as exc:
        latency_ms = (
            time.perf_counter()
            - started_at
        ) * 1000

        logger.exception(
            "Query failed "
            "request_id=%s latency_ms=%.2f",
            request_id,
            latency_ms,
        )

        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail={
                "success": False,
                "error": (
                    "Query processing failed. "
                    "Please try again."
                ),
                "request_id": request_id,
            },
        ) from exc