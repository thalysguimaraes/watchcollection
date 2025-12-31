PRAGMA journal_mode = WAL;
PRAGMA foreign_keys = ON;

CREATE TABLE IF NOT EXISTS market_snapshot (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    watchcharts_id TEXT NOT NULL,
    brand_slug TEXT NOT NULL,
    reference TEXT NOT NULL,
    as_of_date TEXT NOT NULL,
    source TEXT NOT NULL,
    currency TEXT NOT NULL DEFAULT 'USD',
    median_usd INTEGER,
    min_usd INTEGER,
    max_usd INTEGER,
    listings_count INTEGER,
    raw_json TEXT,
    created_at TEXT NOT NULL DEFAULT (datetime('now')),
    CONSTRAINT uq_snapshot UNIQUE (watchcharts_id, source, as_of_date)
);

CREATE INDEX IF NOT EXISTS idx_snapshot_watchcharts_id ON market_snapshot(watchcharts_id);
CREATE INDEX IF NOT EXISTS idx_snapshot_brand_slug ON market_snapshot(brand_slug);
CREATE INDEX IF NOT EXISTS idx_snapshot_as_of_date ON market_snapshot(as_of_date);
CREATE INDEX IF NOT EXISTS idx_snapshot_source ON market_snapshot(source);

CREATE TABLE IF NOT EXISTS ingest_run (
    run_id INTEGER PRIMARY KEY AUTOINCREMENT,
    pipeline TEXT NOT NULL,
    started_at TEXT NOT NULL,
    finished_at TEXT,
    ok INTEGER NOT NULL DEFAULT 0,
    rows_in INTEGER DEFAULT 0,
    rows_out INTEGER DEFAULT 0,
    errors INTEGER DEFAULT 0,
    warnings INTEGER DEFAULT 0,
    meta_json TEXT
);

CREATE INDEX IF NOT EXISTS idx_ingest_pipeline ON ingest_run(pipeline);
CREATE INDEX IF NOT EXISTS idx_ingest_started_at ON ingest_run(started_at);
