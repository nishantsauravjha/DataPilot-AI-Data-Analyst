from pathlib import Path

import pandas as pd


SUPPORTED_EXTENSIONS = {".csv"}


def load_csv(file_path: str | Path) -> pd.DataFrame:
    """
    Load a CSV file into a pandas DataFrame.
    """
    path = Path(file_path)

    if not path.exists():
        raise FileNotFoundError(f"File not found: {path}")

    if path.suffix.lower() not in SUPPORTED_EXTENSIONS:
        raise ValueError(f"Unsupported file type: {path.suffix}")

    try:
        return pd.read_csv(path)
    except Exception as exc:
        raise ValueError(f"Failed to read CSV file: {path.name}") from exc