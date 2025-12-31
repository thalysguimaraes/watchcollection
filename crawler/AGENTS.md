# Crawler Agents Runbook

## Scope
This repo handles crawling for two sources only:
- WatchCharts: catalog base (brands, models, specs, photos, retail price)
- Chrono24: market price (listing-based median)

Anything outside of these sources is considered legacy and should not be reintroduced.

## Standard pipeline order
1) WatchCharts (base catalog)
2) Chrono24 (market price)
3) Transform to API bundle
4) Deploy API (Railway)

## Output files
- Base catalog: `output_watchcharts/{brand_slug}.json` (source of truth)
- Chrono24 enrichment: `output_watchcharts/{brand_slug}_chrono24.json` (optional, for `market_price` fallback only)
- Market data DB: `output/marketdata.sqlite` (canonical `market_price` + `market_price_history`)
- API bundle: `api/data/catalog_bundle.json`

## Transform field precedence
- `market_price`: DB → `_chrono24.json` → base `.json`
- `market_price_history`: DB only
- All other fields: base `.json` only

## Commands (manual)
- WatchCharts crawl (Bright Data required):
  - `python3 -m watchcollection_crawler.pipelines.watchcharts --entry-url "https://watchcharts.com/watches?filters=..." --brand "Rolex" --brand-slug rolex --backend brightdata`
- Chrono24 market price (writes to DB by default):
  - `python3 -m watchcollection_crawler.pipelines.chrono24_market --brand rolex --listings 40 --min-listings 6`
  - Use `--no-write-db` to skip DB writes, `--as-of-date YYYY-MM-DD` to override date
- Transform bundle:
  - `python3 -m watchcollection_crawler.pipelines.transform`
- Deploy API:
  - `cd ../api && railway up`

## New brand flow
1) Start with the brand URL from WatchCharts.
2) Run WatchCharts crawl using that URL.
3) Run Chrono24 market price enrichment on the new output.
4) Transform + deploy.

## Environment essentials
- WatchCharts: `BRIGHTDATA_API_KEY`, `BRIGHTDATA_WEB_ACCESS_ZONE`
- Optional env file: `WATCHCHARTS_ENV_FILE`

## Notes
- For performance, use Bright Data for WatchCharts.
- Use small `--limit` when testing to avoid long runs.
- Prefer running the TUI (monorepo `/tui`) for orchestration and logs.
