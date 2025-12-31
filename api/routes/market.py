from datetime import datetime
from typing import Optional, List

from fastapi import APIRouter, HTTPException, Request, Response
from pydantic import BaseModel
from email.utils import formatdate

from database import get_market_history, get_market_summary

router = APIRouter(prefix="/market", tags=["market"])


class MarketHistoryResponse(BaseModel):
    points: List[List[float]]
    source: str
    start_date: Optional[str] = None
    end_date: Optional[str] = None
    points_count: int


class ChangePct(BaseModel):
    one_month: Optional[float] = None
    six_months: Optional[float] = None
    one_year: Optional[float] = None

    class Config:
        populate_by_name = True


class MarketSummaryResponse(BaseModel):
    price: int
    min_usd: Optional[int] = None
    max_usd: Optional[int] = None
    listings: Optional[int] = None
    change_pct: dict
    last_updated: str


def get_cache_headers(watch_id: str, max_age: int = 3600) -> dict:
    now = datetime.utcnow()
    bucket = int(now.timestamp()) // max_age
    etag = f'W/"market-{watch_id}-{bucket}"'
    last_modified = formatdate(now.timestamp(), usegmt=True)
    return {
        "Cache-Control": f"public, max-age={max_age}",
        "ETag": etag,
        "Last-Modified": last_modified,
    }


@router.get("/history/{watch_id}", response_model=MarketHistoryResponse)
async def market_history(watch_id: str, request: Request, response: Response):
    try:
        data = get_market_history(watch_id, downsample=True)
    except FileNotFoundError:
        raise HTTPException(status_code=503, detail="Market data service unavailable")

    if not data:
        raise HTTPException(status_code=404, detail=f"No market data for '{watch_id}'")

    headers = get_cache_headers(watch_id)
    etag = headers.get("ETag")

    if request.headers.get("if-none-match") == etag:
        return Response(status_code=304, headers=headers)

    response.headers.update(headers)

    return MarketHistoryResponse(
        points=data["points"],
        source=data["source"],
        start_date=data.get("start_date"),
        end_date=data.get("end_date"),
        points_count=data["points_count"],
    )


@router.get("/summary/{watch_id}", response_model=MarketSummaryResponse)
async def market_summary(watch_id: str, request: Request, response: Response):
    try:
        data = get_market_summary(watch_id)
    except FileNotFoundError:
        raise HTTPException(status_code=503, detail="Market data service unavailable")

    if not data:
        raise HTTPException(status_code=404, detail=f"No market data for '{watch_id}'")

    headers = get_cache_headers(watch_id)
    etag = headers.get("ETag")

    if request.headers.get("if-none-match") == etag:
        return Response(status_code=304, headers=headers)

    response.headers.update(headers)

    return MarketSummaryResponse(
        price=data["price"],
        min_usd=data.get("min_usd"),
        max_usd=data.get("max_usd"),
        listings=data.get("listings"),
        change_pct=data["change_pct"],
        last_updated=data["last_updated"],
    )
