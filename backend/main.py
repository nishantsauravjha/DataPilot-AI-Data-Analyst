from fastapi import FastAPI

from backend.api.routes import router
from backend.core.config import settings


app = FastAPI(
    title=settings.APP_NAME,
    version="0.1.0",
)

app.include_router(router)


@app.get("/health")
def health_check():
    return {
        "status": "ok",
        "service": settings.APP_NAME,
    }