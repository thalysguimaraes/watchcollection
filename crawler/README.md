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
  - `python3 -m watchcollection_crawler.pipelines.watchcharts --entry-url "https://watchcharts.com/watches?filters=..." --brand "Rolex" --brand-slug rolex --backend brightdata`
- Download WatchCharts images (optional, R2 upload supported):
  - `python3 -m watchcollection_crawler.pipelines.images --brand rolex`
- Chrono24 market price enrichment:
  - `python3 -m watchcollection_crawler.pipelines.chrono24_market --brand rolex --listings 40 --min-listings 6`
- Transform WatchCharts output into API bundle:
  - `python3 -m watchcollection_crawler.pipelines.transform`
  - `python3 -m watchcollection_crawler.pipelines.transform --brand-slug rolex`

## Paths and env vars
Defaults are relative to repo root, but can be overridden:
- `WATCHCOLLECTION_OUTPUT_DIR`
- `WATCHCHARTS_OUTPUT_DIR`
- `WATCHCHARTS_IMAGES_DIR`
- `WATCHCOLLECTION_API_DATA_DIR`
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
