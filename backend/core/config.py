from pathlib import Path
from urllib.parse import quote_plus

from dotenv import load_dotenv
from pydantic_settings import BaseSettings, SettingsConfigDict


# ============================================================
# Project paths
# ============================================================

BASE_DIR = Path(__file__).resolve().parents[2]

ENV_FILE = BASE_DIR / ".env"


# ============================================================
# Load environment variables
# ============================================================

load_dotenv(ENV_FILE)


# ============================================================
# Application Settings
# ============================================================


class Settings(BaseSettings):

    # --------------------------------------------------------
    # Application
    # --------------------------------------------------------

    APP_NAME: str = "DataPilot"
    APP_ENV: str = "development"
    DEBUG: bool = True

    API_HOST: str = "127.0.0.1"
    API_PORT: int = 8000

    # --------------------------------------------------------
    # PostgreSQL
    # --------------------------------------------------------

    POSTGRES_HOST: str = "127.0.0.1"
    POSTGRES_PORT: int = 5433
    POSTGRES_DB: str = "datapilot"
    POSTGRES_USER: str = "datapilot"
    POSTGRES_PASSWORD: str

    # --------------------------------------------------------
    # OpenAI
    # --------------------------------------------------------

    OPENAI_API_KEY: str
    OPENAI_MODEL: str = "gpt-5-mini"

    # --------------------------------------------------------
    # RAG
    # --------------------------------------------------------

    EMBEDDING_MODEL: str = "text-embedding-3-small"
    RAG_TOP_K: int = 5
    CHUNK_SIZE: int = 800
    CHUNK_OVERLAP: int = 120

    # --------------------------------------------------------
    # Existing database connection compatibility
    # --------------------------------------------------------

    @property
    def database_url(self) -> str:
        """
        Build the SQLAlchemy PostgreSQL connection URL
        from the existing POSTGRES_* environment variables.
        """

        username = quote_plus(self.POSTGRES_USER)
        password = quote_plus(self.POSTGRES_PASSWORD)
        host = self.POSTGRES_HOST
        port = self.POSTGRES_PORT
        database = self.POSTGRES_DB

        return (
            f"postgresql+psycopg://"
            f"{username}:{password}"
            f"@{host}:{port}/{database}"
        )

    # --------------------------------------------------------
    # Pydantic configuration
    # --------------------------------------------------------

    model_config = SettingsConfigDict(
        env_file=str(ENV_FILE),
        env_file_encoding="utf-8",
        extra="ignore",
    )


# ============================================================
# Global settings instance
# ============================================================

settings = Settings()