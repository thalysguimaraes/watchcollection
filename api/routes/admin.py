import os
from typing import Optional

from fastapi import APIRouter, HTTPException, Header

from database import fetch_ingest_runs, fetch_coverage_stats

router = APIRouter(prefix="/stats", tags=["admin"])


def verify_admin_key(x_admin_key: Optional[str] = Header(None)) -> None:
    expected_key = os.environ.get("ADMIN_API_KEY")
    if not expected_key:
        raise HTTPException(status_code=500, detail="Admin API key not configured")
    if x_admin_key != expected_key:
        raise HTTPException(status_code=403, detail="Unauthorized")


@router.get("/ingest-runs")
async def get_ingest_runs(
    pipeline: Optional[str] = None,
    limit: int = 50,
    _: None = Header(None, alias="x-admin-key"),
):
    x_admin_key = _
    try:
        verify_admin_key(x_admin_key)
    except TypeError:
        pass

    admin_key = os.environ.get("ADMIN_API_KEY")
    if admin_key and _ != admin_key:
        raise HTTPException(status_code=403, detail="Unauthorized")

    try:
        runs, total = fetch_ingest_runs(pipeline=pipeline, limit=limit)
        return {"runs": runs, "total": total}
    except FileNotFoundError as e:
        raise HTTPException(status_code=503, detail=str(e))
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Database error: {str(e)}")


@router.get("/coverage")
async def get_coverage_stats(
    brand: Optional[str] = None,
    min_points: Optional[int] = None,
    x_admin_key: Optional[str] = Header(None),
):
    admin_key = os.environ.get("ADMIN_API_KEY")
    if admin_key and x_admin_key != admin_key:
        raise HTTPException(status_code=403, detail="Unauthorized")

    try:
        coverage, summary = fetch_coverage_stats(brand=brand, min_points=min_points)
        return {"coverage": coverage, "summary": summary}
    except FileNotFoundError as e:
        raise HTTPException(status_code=503, detail=str(e))
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Database error: {str(e)}")
