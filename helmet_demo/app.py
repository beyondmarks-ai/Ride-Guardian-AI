from __future__ import annotations

import io
from pathlib import Path

from fastapi import FastAPI, File, HTTPException, UploadFile
from fastapi.responses import FileResponse
from PIL import Image, UnidentifiedImageError

from vision import verify_helmet


BASE_DIR = Path(__file__).resolve().parent
app = FastAPI(title="RideGuardian Azure Vision Helmet Check", version="2.0")


@app.get("/")
def index() -> FileResponse:
    return FileResponse(BASE_DIR / "static" / "index.html")


@app.get("/health")
def health() -> dict[str, str]:
    return {
        "status": "ok",
        "mode": "azure-vision-only",
        "model": "guardian-vision-accurate (GPT-4.1)",
    }


@app.post("/verify-vision")
async def verify_with_vision(frame: UploadFile = File(...)) -> dict[str, object]:
    if frame.content_type not in {"image/jpeg", "image/png", "image/webp"}:
        raise HTTPException(status_code=415, detail="A JPEG, PNG, or WebP frame is required")
    raw = await frame.read()
    if not raw or len(raw) > 5_000_000:
        raise HTTPException(status_code=400, detail="Frame must be between 1 byte and 5 MB")
    try:
        image = Image.open(io.BytesIO(raw)).convert("RGB")
        result = verify_helmet(image)
    except UnidentifiedImageError as exc:
        raise HTTPException(status_code=400, detail="Invalid image") from exc
    except Exception as exc:
        raise HTTPException(status_code=502, detail=f"Azure Vision failed: {exc}") from exc

    helmet_present = bool(result.get("helmet_present"))
    properly_worn = bool(result.get("properly_worn"))
    status = "helmet" if helmet_present and properly_worn else "no_helmet"
    confidence = max(0.0, min(1.0, float(result.get("confidence", 0.0))))
    return {
        "status": status,
        "confidence": round(confidence, 4),
        "helmet_present": helmet_present,
        "properly_worn": properly_worn,
        "helmet_type": str(result.get("helmet_type", "unknown")),
        "reason": str(result.get("reason", "No explanation returned.")),
        "source": "azure-gpt-4.1",
    }
