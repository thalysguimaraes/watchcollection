from dataclasses import dataclass
from datetime import date
from sqlite3 import Connection
from typing import List, Optional, Tuple

from .models import SnapshotSource


@dataclass
class HistoryPoint:
    timestamp: int
    price: float
    source: SnapshotSource


def get_all_snapshots(
    conn: Connection,
    watchcharts_id: str,
    sources: Optional[List[SnapshotSource]] = None,
) -> List[Tuple[date, int, SnapshotSource]]:
    if sources:
        placeholders = ",".join("?" for _ in sources)
        query = f"""
            SELECT as_of_date, median_usd, source
            FROM market_snapshot
            WHERE watchcharts_id = ?
              AND source IN ({placeholders})
              AND median_usd IS NOT NULL
            ORDER BY as_of_date ASC
        """
        params = [watchcharts_id] + [s.value for s in sources]
    else:
        query = """
            SELECT as_of_date, median_usd, source
            FROM market_snapshot
            WHERE watchcharts_id = ?
              AND median_usd IS NOT NULL
            ORDER BY as_of_date ASC
        """
        params = [watchcharts_id]

    rows = conn.execute(query, params).fetchall()
    return [
        (date.fromisoformat(r[0]), r[1], SnapshotSource(r[2]))
        for r in rows
    ]


def downsample_weekly(points: List[HistoryPoint]) -> List[HistoryPoint]:
    if not points:
        return []

    result = []
    current_week = None
    current_point = None

    for pt in points:
        pt_date = date.fromtimestamp(pt.timestamp)
        week_start = pt_date.isocalendar()[:2]

        if week_start != current_week:
            if current_point is not None:
                result.append(current_point)
            current_week = week_start
            current_point = pt
        else:
            current_point = pt

    if current_point is not None:
        result.append(current_point)

    return result


def get_history_points(
    conn: Connection,
    watchcharts_id: str,
    prefer_sources: Optional[List[SnapshotSource]] = None,
    downsample: Optional[str] = None,
) -> List[List]:
    if prefer_sources is None:
        prefer_sources = [SnapshotSource.WATCHCHARTS_CSV, SnapshotSource.CHRONO24]

    snapshots = get_all_snapshots(conn, watchcharts_id, prefer_sources)
    if not snapshots:
        return []

    seen_dates = set()
    points = []

    source_priority = {s: i for i, s in enumerate(prefer_sources)}

    date_to_best = {}
    for as_of_date, median_usd, source in snapshots:
        priority = source_priority.get(source, len(prefer_sources))
        if as_of_date not in date_to_best:
            date_to_best[as_of_date] = (median_usd, source, priority)
        else:
            _, _, existing_priority = date_to_best[as_of_date]
            if priority < existing_priority:
                date_to_best[as_of_date] = (median_usd, source, priority)

    for as_of_date in sorted(date_to_best.keys()):
        median_usd, source, _ = date_to_best[as_of_date]
        ts = int(date(as_of_date.year, as_of_date.month, as_of_date.day).strftime("%s"))
        points.append(HistoryPoint(timestamp=ts, price=float(median_usd), source=source))

    if downsample == "weekly":
        points = downsample_weekly(points)

    return [[pt.timestamp, pt.price] for pt in points]


def get_combined_source_label(
    conn: Connection,
    watchcharts_id: str,
) -> str:
    query = """
        SELECT DISTINCT source FROM market_snapshot
        WHERE watchcharts_id = ?
        ORDER BY source
    """
    rows = conn.execute(query, (watchcharts_id,)).fetchall()
    sources = [r[0] for r in rows]
    if not sources:
        return "unknown"
    return "+".join(sources)


def get_latest_price(
    conn: Connection,
    watchcharts_id: str,
    prefer_sources: Optional[List[SnapshotSource]] = None,
) -> Optional[dict]:
    if prefer_sources is None:
        prefer_sources = [SnapshotSource.CHRONO24, SnapshotSource.WATCHCHARTS_CSV]

    for source in prefer_sources:
        row = conn.execute(
            """
            SELECT median_usd, min_usd, max_usd, listings_count, as_of_date
            FROM market_snapshot
            WHERE watchcharts_id = ? AND source = ? AND median_usd IS NOT NULL
            ORDER BY as_of_date DESC
            LIMIT 1
            """,
            (watchcharts_id, source.value),
        ).fetchone()
        if row:
            return {
                "median_usd": row[0],
                "min_usd": row[1],
                "max_usd": row[2],
                "listings": row[3],
                "updated_at": row[4],
                "source": source.value,
            }
    return None
