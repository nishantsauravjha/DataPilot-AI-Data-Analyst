from __future__ import annotations

from pathlib import Path

import pandas as pd

from backend.ingestion.csv_loader import load_csv
from backend.ingestion.excel_loader import load_excel
from backend.ingestion.profiler import profile_dataframe
from backend.services.metadata_service import (
    create_data_source,
    create_dataset,
    create_dataset_columns,
    create_dataset_table,
)
from backend.services.schema_service import (
    create_physical_table,
    insert_dataframe,
)


SUPPORTED_EXTENSIONS = {
    ".csv": "CSV",
    ".xlsx": "EXCEL",
    ".xls": "EXCEL",
}


def load_dataframe(file_path: str | Path) -> pd.DataFrame:
    path = Path(file_path)

    extension = path.suffix.lower()

    if extension == ".csv":
        return load_csv(path)

    if extension in {".xlsx", ".xls"}:
        return load_excel(path)

    raise ValueError(
        f"Unsupported file type: {extension}. "
        f"Supported types: CSV, XLSX, XLS."
    )


def ingest_dataset(
    file_path: str | Path,
    description: str | None = None,
) -> dict:
    """
    Complete CSV/Excel ingestion pipeline.
    """

    path = Path(file_path)

    if not path.exists():
        raise FileNotFoundError(
            f"File not found: {path}"
        )

    source_type = SUPPORTED_EXTENSIONS.get(
        path.suffix.lower()
    )

    if source_type is None:
        raise ValueError(
            f"Unsupported file type: {path.suffix}"
        )

    # --------------------------------------------------
    # 1. Load
    # --------------------------------------------------

    df = load_dataframe(path)

    if df.empty:
        raise ValueError(
            "The uploaded dataset contains no rows."
        )

    # --------------------------------------------------
    # 2. Profile
    # --------------------------------------------------

    profiles = profile_dataframe(df)

    # --------------------------------------------------
    # 3. Create physical PostgreSQL table
    # --------------------------------------------------

    dataset_name = path.stem

    physical_table, sanitized_columns = (
        create_physical_table(
            df,
            dataset_name,
        )
    )

    # --------------------------------------------------
    # 4. Insert data
    # --------------------------------------------------

    row_count = insert_dataframe(
        df,
        physical_table,
        sanitized_columns,
    )

    # --------------------------------------------------
    # 5. Register source
    # --------------------------------------------------

    source_id = create_data_source(
        source_name=path.name,
        source_type=source_type,
        connection_identifier=str(path.resolve()),
        description=description,
    )

    # --------------------------------------------------
    # 6. Register dataset
    # --------------------------------------------------

    dataset_id = create_dataset(
        source_id=source_id,
        dataset_name=dataset_name,
        display_name=dataset_name.replace(
            "_",
            " ",
        ).title(),
        database_name="datapilot",
        database_schema="uploaded_data",
        database_engine=source_type.lower(),
        description=description,
    )

    # --------------------------------------------------
    # 7. Register table
    # --------------------------------------------------

    table_id = create_dataset_table(
        dataset_id=dataset_id,
        table_name=physical_table,
        table_schema="uploaded_data",
    )

    # --------------------------------------------------
    # 8. Register columns
    # --------------------------------------------------

    column_ids = create_dataset_columns(
        table_id=table_id,
        column_profiles=[
            {
                **profile,
                "column_name": sanitized_name,
            }
            for profile, sanitized_name in zip(
                profiles,
                sanitized_columns,
            )
        ],
    )

    return {
        "source_id": str(source_id),
        "dataset_id": str(dataset_id),
        "table_id": str(table_id),
        "column_ids": [
            str(column_id)
            for column_id in column_ids
        ],
        "dataset_name": dataset_name,
        "table_name": physical_table,
        "schema": "uploaded_data",
        "source_type": source_type,
        "rows": row_count,
        "columns": len(df.columns),
        "column_names": sanitized_columns,
    }