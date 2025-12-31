import sqlite3
from contextlib import contextmanager
from datetime import datetime
from pathlib import Path
from typing import Generator, List, Optional

from .models import MarketSnapshot, IngestStats, SnapshotSource


def get_conn(db_path: Path) -> sqlite3.Connection:
    db_path.parent.mkdir(parents=True, exist_ok=True)
    conn = sqlite3.connect(str(db_path))
    conn.row_factory = sqlite3.Row
    return conn


def init_schema(conn: sqlite3.Connection) -> None:
    schema_path = Path(__file__).parent / "schema.sql"
    schema_sql = schema_path.read_text()
    conn.executescript(schema_sql)
    conn.commit()


@contextmanager
def get_db(db_path: Path) -> Generator[sqlite3.Connection, None, None]:
    conn = get_conn(db_path)
    try:
        init_schema(conn)
        yield conn
    finally:
        conn.close()


def start_ingest_run(
    conn: sqlite3.Connection,
    pipeline: str,
    meta_json: Optional[str] = None,
) -> int:
    cursor = conn.execute(
        """
        INSERT INTO ingest_run (pipeline, started_at, meta_json)
        VALUES (?, ?, ?)
        """,
        (pipeline, datetime.utcnow().isoformat(), meta_json),
    )
    conn.commit()
    return cursor.lastrowid


def finish_ingest_run(
    conn: sqlite3.Connection,
    run_id: int,
    stats: IngestStats,
    ok: bool = True,
) -> None:
    conn.execute(
        """
        UPDATE ingest_run
        SET finished_at = ?, ok = ?, rows_in = ?, rows_out = ?, errors = ?, warnings = ?
        WHERE run_id = ?
        """,
        (
            datetime.utcnow().isoformat(),
            1 if ok else 0,
            stats.rows_in,
            stats.rows_out,
            stats.errors,
            stats.warnings,
            run_id,
        ),
    )
    conn.commit()


def record_ingest_run(
    conn: sqlite3.Connection,
    pipeline: str,
    stats: IngestStats,
    ok: bool = True,
    meta_json: Optional[str] = None,
) -> int:
    run_id = start_ingest_run(conn, pipeline, meta_json)
    finish_ingest_run(conn, run_id, stats, ok)
    return run_id


def insert_snapshot(
    conn: sqlite3.Connection,
    snapshot: MarketSnapshot,
) -> bool:
    try:
        conn.execute(
            """
            INSERT INTO market_snapshot (
                watchcharts_id, brand_slug, reference, as_of_date,
                source, currency, median_usd, min_usd, max_usd,
                listings_count, raw_json
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """,
            snapshot.to_row(),
        )
        return True
    except sqlite3.IntegrityError:
        return False


def insert_snapshots_batch(
    conn: sqlite3.Connection,
    snapshots: List[MarketSnapshot],
) -> IngestStats:
    stats = IngestStats()
    for snapshot in snapshots:
        stats.rows_in += 1
        if insert_snapshot(conn, snapshot):
            stats.rows_out += 1
    conn.commit()
    return stats


def upsert_snapshot(
    conn: sqlite3.Connection,
    snapshot: MarketSnapshot,
) -> bool:
    conn.execute(
        """
        INSERT INTO market_snapshot (
            watchcharts_id, brand_slug, reference, as_of_date,
            source, currency, median_usd, min_usd, max_usd,
            listings_count, raw_json
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        ON CONFLICT (watchcharts_id, source, as_of_date)
        DO UPDATE SET
            median_usd = excluded.median_usd,
            min_usd = excluded.min_usd,
            max_usd = excluded.max_usd,
            listings_count = excluded.listings_count,
            raw_json = excluded.raw_json
        """,
        snapshot.to_row(),
    )
    conn.commit()
    return True


def get_latest_snapshot(
    conn: sqlite3.Connection,
    watchcharts_id: str,
    source: Optional[SnapshotSource] = None,
) -> Optional[MarketSnapshot]:
    if source:
        row = conn.execute(
            """
            SELECT id, watchcharts_id, brand_slug, reference, as_of_date,
                   source, currency, median_usd, min_usd, max_usd,
                   listings_count, raw_json, created_at
            FROM market_snapshot
            WHERE watchcharts_id = ? AND source = ?
            ORDER BY as_of_date DESC
            LIMIT 1
            """,
            (watchcharts_id, source.value),
        ).fetchone()
    else:
        row = conn.execute(
            """
            SELECT id, watchcharts_id, brand_slug, reference, as_of_date,
                   source, currency, median_usd, min_usd, max_usd,
                   listings_count, raw_json, created_at
            FROM market_snapshot
            WHERE watchcharts_id = ?
            ORDER BY as_of_date DESC
            LIMIT 1
            """,
            (watchcharts_id,),
        ).fetchone()
    return MarketSnapshot.from_row(tuple(row)) if row else None


def get_snapshot_count(
    conn: sqlite3.Connection,
    watchcharts_id: Optional[str] = None,
    source: Optional[SnapshotSource] = None,
) -> int:
    query = "SELECT COUNT(*) FROM market_snapshot WHERE 1=1"
    params: List = []
    if watchcharts_id:
        query += " AND watchcharts_id = ?"
        params.append(watchcharts_id)
    if source:
        query += " AND source = ?"
        params.append(source.value)
    row = conn.execute(query, params).fetchone()
    return row[0] if row else 0
