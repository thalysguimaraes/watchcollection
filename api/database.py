import os
import sqlite3
from contextlib import contextmanager
from pathlib import Path
from typing import Generator, Optional, List, Dict, Any
import json

from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker, declarative_base, Session

DATABASE_URL = os.getenv("DATABASE_URL", "sqlite:///./data/api.sqlite")

engine = create_engine(
    DATABASE_URL,
    connect_args={"check_same_thread": False} if DATABASE_URL.startswith("sqlite") else {},
)

SessionLocal = sessionmaker(autocommit=False, autoflush=False, bind=engine)

Base = declarative_base()


def get_db() -> Generator[Session, None, None]:
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()


def get_marketdata_db_path() -> Path:
    env_path = os.getenv("MARKETDATA_DB_PATH")
    if env_path:
        return Path(env_path)
    return Path(__file__).parent.parent / "crawler" / "output" / "marketdata.sqlite"


@contextmanager
def get_marketdata_conn() -> Generator[sqlite3.Connection, None, None]:
    db_path = get_marketdata_db_path()
    if not db_path.exists():
        raise FileNotFoundError(f"marketdata.sqlite not found at {db_path}")

    conn = sqlite3.connect(str(db_path))
    conn.row_factory = sqlite3.Row
    try:
        yield conn
    finally:
        conn.close()


def fetch_ingest_runs(
    pipeline: Optional[str] = None,
    limit: int = 50,
) -> tuple[List[Dict[str, Any]], int]:
    with get_marketdata_conn() as conn:
        count_query = "SELECT COUNT(*) FROM ingest_run WHERE 1=1"
        query = """
            SELECT run_id, pipeline, started_at, finished_at, ok,
                   rows_in, rows_out, errors, warnings, meta_json
            FROM ingest_run
            WHERE 1=1
        """
        params: List[Any] = []

        if pipeline:
            count_query += " AND pipeline = ?"
            query += " AND pipeline = ?"
            params.append(pipeline)

        total = conn.execute(count_query, params).fetchone()[0]

        query += " ORDER BY started_at DESC LIMIT ?"
        params.append(limit)

        rows = conn.execute(query, params).fetchall()

        runs = []
        for row in rows:
            meta = None
            if row["meta_json"]:
                try:
                    meta = json.loads(row["meta_json"])
                except (json.JSONDecodeError, TypeError):
                    meta = row["meta_json"]

            runs.append({
                "run_id": row["run_id"],
                "pipeline": row["pipeline"],
                "started_at": row["started_at"],
                "finished_at": row["finished_at"],
                "ok": bool(row["ok"]) if row["ok"] is not None else None,
                "rows_in": row["rows_in"] or 0,
                "rows_out": row["rows_out"] or 0,
                "errors": row["errors"] or 0,
                "warnings": row["warnings"] or 0,
                "meta": meta,
            })

        return runs, total


def fetch_coverage_stats(
    brand: Optional[str] = None,
    min_points: Optional[int] = None,
) -> tuple[List[Dict[str, Any]], Dict[str, Any]]:
    with get_marketdata_conn() as conn:
        query = """
            SELECT
                watchcharts_id,
                brand_slug,
                reference,
                MIN(as_of_date) as start_date,
                MAX(as_of_date) as end_date,
                COUNT(*) as points,
                GROUP_CONCAT(DISTINCT source) as sources
            FROM market_snapshot
            WHERE 1=1
        """
        params: List[Any] = []

        if brand:
            query += " AND brand_slug = ?"
            params.append(brand)

        query += " GROUP BY watchcharts_id, brand_slug, reference"

        if min_points:
            query += " HAVING COUNT(*) >= ?"
            params.append(min_points)

        query += " ORDER BY brand_slug, reference"

        rows = conn.execute(query, params).fetchall()

        coverage = []
        for row in rows:
            sources = row["sources"].split(",") if row["sources"] else []
            coverage.append({
                "watchcharts_id": row["watchcharts_id"],
                "brand_slug": row["brand_slug"],
                "reference": row["reference"],
                "start_date": row["start_date"],
                "end_date": row["end_date"],
                "points": row["points"],
                "sources": sources,
            })

        total_watches = len(coverage)
        with_10_plus = sum(1 for c in coverage if c["points"] >= 10)
        coverage_pct = (with_10_plus / total_watches * 100) if total_watches > 0 else 0.0

        summary = {
            "total_watches": total_watches,
            "with_10_plus_points": with_10_plus,
            "coverage_pct": round(coverage_pct, 1),
        }

        return coverage, summary


def get_market_history(watch_id: str, downsample: bool = True) -> Dict[str, Any]:
    with get_marketdata_conn() as conn:
        query = """
            SELECT as_of_date, median_usd, source
            FROM market_snapshot
            WHERE watchcharts_id = ?
              AND median_usd IS NOT NULL
            ORDER BY as_of_date ASC
        """
        rows = conn.execute(query, (watch_id,)).fetchall()

        if not rows:
            return {}

        from datetime import datetime

        points = []
        sources = set()
        for row in rows:
            date_str = row["as_of_date"]
            try:
                dt = datetime.fromisoformat(date_str.replace("Z", "+00:00"))
                ts = int(dt.timestamp())
            except (ValueError, AttributeError):
                continue
            points.append([ts, row["median_usd"]])
            sources.add(row["source"])

        if downsample and len(points) > 52:
            weekly = {}
            for ts, price in points:
                week_key = ts // (7 * 24 * 3600)
                weekly[week_key] = [ts, price]
            points = list(weekly.values())

        if not points:
            return {}

        return {
            "points": points,
            "source": "+".join(sorted(sources)),
            "start_date": datetime.fromtimestamp(points[0][0]).date().isoformat(),
            "end_date": datetime.fromtimestamp(points[-1][0]).date().isoformat(),
            "points_count": len(points),
        }


def get_market_summary(watch_id: str) -> Dict[str, Any]:
    with get_marketdata_conn() as conn:
        query = """
            SELECT as_of_date, median_usd, min_usd, max_usd, listings_count, source
            FROM market_snapshot
            WHERE watchcharts_id = ?
              AND median_usd IS NOT NULL
            ORDER BY as_of_date DESC
            LIMIT 1
        """
        row = conn.execute(query, (watch_id,)).fetchone()

        if not row:
            return {}

        current_price = row["median_usd"]

        from datetime import datetime, timedelta

        now = datetime.utcnow()

        def get_price_at(days_ago: int) -> Optional[int]:
            target = (now - timedelta(days=days_ago)).date().isoformat()
            r = conn.execute(
                """
                SELECT median_usd FROM market_snapshot
                WHERE watchcharts_id = ?
                  AND as_of_date <= ?
                  AND median_usd IS NOT NULL
                ORDER BY as_of_date DESC
                LIMIT 1
                """,
                (watch_id, target),
            ).fetchone()
            return r[0] if r else None

        def calc_pct(old: Optional[int]) -> Optional[float]:
            if old is None or old == 0:
                return None
            return round(((current_price - old) / old) * 100, 2)

        return {
            "price": current_price,
            "min_usd": row["min_usd"],
            "max_usd": row["max_usd"],
            "listings": row["listings_count"],
            "change_pct": {
                "1m": calc_pct(get_price_at(30)),
                "6m": calc_pct(get_price_at(180)),
                "1y": calc_pct(get_price_at(365)),
            },
            "last_updated": row["as_of_date"],
        }
