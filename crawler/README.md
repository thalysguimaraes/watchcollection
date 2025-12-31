# Watchcollection Crawler

## Architecture (2025-12)
- WatchCharts: catalog base (brands, models, specs, photos, retail price)
- Chrono24: market price (listing-based median with outlier removal)

## Structure
- `watchcollection_crawler/`: package code
- `watchcollection_crawler/pipelines/`: runnable CLIs
- `watchcollection_crawler/sources/`: site-specific parsing helpers
- `watchcollection_crawler/core/`: shared clients and paths
- `scripts/`: operational shell helpers

## Common commands
- WatchCharts crawl (catalog base):
  - `python3 -m watchcollection_crawler.pipelines.watchcharts --entry-url "https://watchcharts.com/watches?filters=..." --brand "Rolex" --brand-slug rolex`
  - Uses curl-impersonate by default. BrightData available as fallback via `--backend brightdata`.
- Download WatchCharts images (optional, R2 upload supported):
  - `python3 -m watchcollection_crawler.pipelines.images --brand rolex`
- Chrono24 market price enrichment:
  - `python3 -m watchcollection_crawler.pipelines.chrono24_market --brand rolex --listings 40 --min-listings 6`
  - Writes snapshots to marketdata DB by default (use `--no-write-db` to disable)
  - Override snapshot date: `--as-of-date 2024-01-15`
  - Override DB path: `--db-path ./custom.sqlite`
- Transform WatchCharts output into API bundle:
  - `python3 -m watchcollection_crawler.pipelines.transform`
  - `python3 -m watchcollection_crawler.pipelines.transform --brand-slug rolex`
  - Override DB path: `--marketdata-db ./custom.sqlite`

## Transform Field Precedence

Transform uses **field-level merge** (not file-level selection):

| Field | Precedence (first available wins) |
|-------|-----------------------------------|
| `market_price` | DB (chrono24 snapshot) → `_chrono24.json` → base `.json` |
| `market_price_history` | DB only (watchcharts_csv + chrono24 combined) |
| All other fields | Base `.json` only |

- Base file `<slug>.json` is always loaded (catalog source of truth)
- Chrono24 enrichment `<slug>_chrono24.json` is optional (used only for `market_price` fallback)
- Output is deterministic given (catalog JSON + marketdata DB)

## Backfill Import

Import WatchCharts CSV price history exports into the marketdata database:

```bash
# Import all CSVs from directory
python3 -m watchcollection_crawler.pipelines.watchcharts_csv_import --csv-dir ./csv-backfill

# Dry run (validate without inserting)
python3 -m watchcollection_crawler.pipelines.watchcharts_csv_import --csv-dir ./csv-backfill --dry-run

# Verbose output with per-row status
python3 -m watchcollection_crawler.pipelines.watchcharts_csv_import --csv-dir ./csv-backfill --verbose

# Limit to first N files (for testing)
python3 -m watchcollection_crawler.pipelines.watchcharts_csv_import --csv-dir ./csv-backfill --limit 3
```

**CSV format expected:**
- Filename: `<Brand Name> YYYY-MM-DD.csv` or `<Brand Name> YYYY-MM-DD (N).csv`
- Columns: `Reference Number,Market Price (USD),Market Volatility`
- Reference format: `<Brand> <Reference>` (e.g., "Rolex 16570")

**Behavior:**
- Re-importing same CSV won't duplicate (UNIQUE constraint on watchcharts_id + source + date)
- Unmatched references logged as warnings, import continues
- Emits run report with inserted/skipped counts

## Backfill Queue Generator

Generate a CSV of watches needing price history backfill:

```bash
# Generate queue for all brands (watches missing any history)
python3 -m watchcollection_crawler.pipelines.marketdata_backfill_queue --output ./backfill_queue.csv

# Filter to watches with fewer than 10 snapshots
python3 -m watchcollection_crawler.pipelines.marketdata_backfill_queue --output ./queue.csv --min-points 10

# Filter to watches with history starting after a date
python3 -m watchcollection_crawler.pipelines.marketdata_backfill_queue --output ./queue.csv --after-date 2024-01-01

# Filter to specific brand
python3 -m watchcollection_crawler.pipelines.marketdata_backfill_queue --output ./queue.csv --brand rolex
```

**CSV output columns:**
- `watchcharts_id`: UUID for matching with downloaded CSVs
- `brand_slug`, `reference`, `full_name`: Model identification
- `watchcharts_url`: URL for manual download from WatchCharts
- `snapshot_count`: Current DB coverage
- `earliest_date`, `latest_date`: Date range of existing snapshots

## Paths and env vars
Defaults are relative to repo root, but can be overridden:
- `WATCHCOLLECTION_OUTPUT_DIR`
- `WATCHCHARTS_OUTPUT_DIR`
- `WATCHCHARTS_IMAGES_DIR`
- `WATCHCOLLECTION_API_DATA_DIR`
- `MARKETDATA_DB_PATH` (SQLite market data database)
- `WATCHCHARTS_ENV_FILE` (optional env file path)
- Bright Data (WatchCharts):
  - `BRIGHTDATA_API_KEY`
  - `BRIGHTDATA_WEB_ACCESS_ZONE`
  - `BRIGHTDATA_ENDPOINT` (default: https://api.brightdata.com/request)
  - `BRIGHTDATA_FORMAT` (default: raw)
- Images (R2 uploads, optional):
  - `R2_PUBLIC_URL`
  - `R2_ENDPOINT`
  - `R2_ACCESS_KEY_ID`
  - `R2_SECRET_ACCESS_KEY`
  - `R2_BUCKET`
