import os
import time
import base64
from typing import Optional

from fastapi import APIRouter, HTTPException, Depends, UploadFile, File, Request
from pydantic import BaseModel

from auth import require_pro_user
from middleware import CircuitBreaker, get_logger

router = APIRouter(prefix="/ai", tags=["ai"])

logger = get_logger()
ai_circuit_breaker = CircuitBreaker(failure_threshold=5, recovery_timeout=60)

ANTHROPIC_API_KEY = os.getenv("ANTHROPIC_API_KEY")


class IdentifyRequest(BaseModel):
    image_url: Optional[str] = None


class IdentifyResponse(BaseModel):
    brand: Optional[str] = None
    model_reference: Optional[str] = None
    display_name: Optional[str] = None
    confidence: float
    details: Optional[dict] = None


async def call_anthropic_vision(image_data: bytes, media_type: str = "image/jpeg") -> dict:
    import httpx

    if not ANTHROPIC_API_KEY:
        raise HTTPException(status_code=500, detail="AI provider not configured")

    b64_image = base64.b64encode(image_data).decode("utf-8")

    async with httpx.AsyncClient(timeout=60.0) as client:
        response = await client.post(
            "https://api.anthropic.com/v1/messages",
            headers={
                "x-api-key": ANTHROPIC_API_KEY,
                "anthropic-version": "2023-06-01",
                "content-type": "application/json",
            },
            json={
                "model": "claude-sonnet-4-20250514",
                "max_tokens": 1024,
                "messages": [
                    {
                        "role": "user",
                        "content": [
                            {
                                "type": "image",
                                "source": {
                                    "type": "base64",
                                    "media_type": media_type,
                                    "data": b64_image,
                                },
                            },
                            {
                                "type": "text",
                                "text": """Identify this watch. Return JSON with:
{
  "brand": "Brand name",
  "model_reference": "Reference number if visible",
  "display_name": "Model name",
  "confidence": 0.0-1.0,
  "details": {
    "dial_color": "...",
    "case_material": "...",
    "bezel": "...",
    "year_estimate": "..."
  }
}
Only return the JSON, no other text.""",
                            },
                        ],
                    }
                ],
            },
        )

        if response.status_code != 200:
            raise Exception(f"Anthropic API error: {response.status_code}")

        data = response.json()
        text = data.get("content", [{}])[0].get("text", "{}")

        import json
        try:
            return json.loads(text)
        except json.JSONDecodeError:
            return {"confidence": 0.0, "details": {"raw_response": text}}


@router.post("/identify", response_model=IdentifyResponse)
async def identify_watch(
    request: Request,
    body: Optional[IdentifyRequest] = None,
    image: Optional[UploadFile] = File(None),
    user: dict = Depends(require_pro_user),
):
    start_time = time.time()
    status = "success"
    tokens_used = 0

    try:
        image_data: bytes
        media_type = "image/jpeg"

        if image:
            image_data = await image.read()
            media_type = image.content_type or "image/jpeg"
        elif body and body.image_url:
            import httpx
            async with httpx.AsyncClient() as client:
                resp = await client.get(body.image_url)
                if resp.status_code != 200:
                    raise HTTPException(status_code=400, detail="Failed to fetch image URL")
                image_data = resp.content
                media_type = resp.headers.get("content-type", "image/jpeg")
        else:
            raise HTTPException(status_code=400, detail="Provide image file or image_url")

        result = await ai_circuit_breaker.call(
            call_anthropic_vision, image_data, media_type
        )

        tokens_used = 1000

        return IdentifyResponse(
            brand=result.get("brand"),
            model_reference=result.get("model_reference"),
            display_name=result.get("display_name"),
            confidence=result.get("confidence", 0.0),
            details=result.get("details"),
        )

    except HTTPException:
        status = "error"
        raise
    except Exception as e:
        status = "error"
        logger.error(f"AI identify error: {e}")
        raise HTTPException(status_code=500, detail="AI identification failed")
    finally:
        latency_ms = int((time.time() - start_time) * 1000)
        logger.info(
            "ai_identify_request",
            extra={
                "user_id": user["id"],
                "latency_ms": latency_ms,
                "status": status,
                "tokens_used": tokens_used,
            },
        )
