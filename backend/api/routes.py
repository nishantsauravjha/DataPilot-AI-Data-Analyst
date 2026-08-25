from pathlib import Path
from uuid import uuid4

from fastapi import APIRouter, File, HTTPException, UploadFile
from pydantic import BaseModel

from backend.services.ingestion_service import ingest_dataset
from backend.services.query_service import (
    execute_dataset_query,
    get_latest_schema_context,
)
from backend.sql.generator import generate_sql


router = APIRouter(
    prefix="/api/v1",
    tags=["datasets"],
)


UPLOAD_DIR = Path("data/uploads")
UPLOAD_DIR.mkdir(
    parents=True,
    exist_ok=True,
)


# ============================================================
# Request Models
# ============================================================


class QueryRequest(BaseModel):
    question: str


# ============================================================
# Dataset Upload
# ============================================================


@router.post("/datasets/upload")
async def upload_dataset(
    file: UploadFile = File(...),
):
    """
    Upload and ingest a CSV or Excel dataset.

    Pipeline:
        Upload
        -> File validation
        -> Pandas
        -> Profiling
        -> PostgreSQL physical table
        -> Structured metadata
    """

    allowed_extensions = {
        ".csv",
        ".xlsx",
        ".xls",
    }

    extension = Path(
        file.filename or ""
    ).suffix.lower()

    if extension not in allowed_extensions:
        raise HTTPException(
            status_code=400,
            detail=(
                "Unsupported file type. "
                "Upload CSV or Excel."
            ),
        )

    filename = (
        f"{uuid4().hex}_"
        f"{file.filename}"
    )

    file_path = UPLOAD_DIR / filename

    try:
        contents = await file.read()

        if not contents:
            raise HTTPException(
                status_code=400,
                detail="Uploaded file is empty.",
            )

        file_path.write_bytes(contents)

        result = ingest_dataset(file_path)

        return {
            "success": True,
            "message": "Dataset ingested successfully.",
            "data": result,
        }

    except HTTPException:
        raise

    except Exception as exc:
        raise HTTPException(
            status_code=500,
            detail=f"Dataset ingestion failed: {exc}",
        ) from exc

    finally:
        if file_path.exists():
            file_path.unlink()


# ============================================================
# Natural Language Query
# ============================================================


@router.post("/query")
def query_dataset(
    request: QueryRequest,
):
    """
    Convert a natural-language question into SQL,
    validate it, execute it, and return the result.

    Pipeline:
        Question
        -> Schema Retrieval
        -> LLM SQL Generation
        -> SQL Validation
        -> PostgreSQL
        -> Result
    """

    question = request.question.strip()

    if not question:
        raise HTTPException(
            status_code=400,
            detail="Question cannot be empty.",
        )

    try:
        # ----------------------------------------------------
        # 1. Retrieve database schema
        # ----------------------------------------------------

        schema = get_latest_schema_context()

        if not schema:
            raise HTTPException(
                status_code=404,
                detail=(
                    "No active dataset is available. "
                    "Upload a CSV or Excel file first."
                ),
            )

        # ----------------------------------------------------
        # 2. Generate SQL using the LLM
        # ----------------------------------------------------

        generated = generate_sql(
            question=question,
            schema=schema,
        )

        # ----------------------------------------------------
        # 3. Execute validated SQL
        #
        # execute_dataset_query() internally uses
        # execute_query(), which calls validate_sql().
        # ----------------------------------------------------

        result = execute_dataset_query(
            generated["sql"]
        )

        # ----------------------------------------------------
        # 4. Return complete response
        # ----------------------------------------------------

        return {
            "success": True,
            "question": question,
            "sql": generated["sql"],
            "explanation": generated["explanation"],
            "confidence": generated["confidence"],
            "result": result,
        }

    except HTTPException:
        raise

    except Exception as exc:
        raise HTTPException(
            status_code=500,
            detail=f"Query execution failed: {exc}",
        ) from exc