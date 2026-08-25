from pathlib import Path

import pandas as pd


SUPPORTED_EXTENSIONS = {".xlsx", ".xls"}


def load_excel(file_path: str | Path) -> pd.DataFrame:
    """
    Load the first worksheet of an Excel file.
    """
    path = Path(file_path)

    if not path.exists():
        raise FileNotFoundError(f"File not found: {path}")

    if path.suffix.lower() not in SUPPORTED_EXTENSIONS:
        raise ValueError(f"Unsupported file type: {path.suffix}")

    try:
        return pd.read_excel(path)
    except Exception as exc:
        raise ValueError(f"Failed to read Excel file: {path.name}") from exc