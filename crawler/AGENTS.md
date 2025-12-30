# Crawler Agents Runbook

## Scope
This repo handles crawling for three sources only:
- WatchCharts: catalog base (brands, models, specs, photos, retail price)
- Chrono24: market price (listing-based median)
- TheWatchAPI: historical price series

Anything outside of these sources is considered legacy and should not be reintroduced.

## Standard pipeline order
1) WatchCharts (base catalog)
2) Chrono24 (market price)
3) TheWatchAPI (price history)
4) Transform to API bundle
5) Deploy API (Railway)

## Output files
- Base: `output_watchcharts/{brand_slug}.json`
- Chrono24 market price: `output_watchcharts/{brand_slug}_chrono24.json`
- TheWatchAPI history: `output_watchcharts/{brand_slug}_thewatchapi.json`
- API bundle: `api/data/catalog_bundle.json`

## Commands (manual)
- WatchCharts crawl (Bright Data required):
  - `python3 -m watchcollection_crawler.pipelines.watchcharts --entry-url "https://watchcharts.com/watches?filters=..." --brand "Rolex" --brand-slug rolex --backend brightdata`
- Chrono24 market price (FlareSolverr):
  - `python3 -m watchcollection_crawler.pipelines.chrono24_market --brand rolex --listings 40 --min-listings 6`
- TheWatchAPI history:
  - `python3 -m watchcollection_crawler.pipelines.thewatchapi_history --brand rolex`
- Transform bundle:
  - `python3 -m watchcollection_crawler.pipelines.transform`
- Deploy API:
  - `cd ../api && railway up`

## New brand flow
1) Start with the brand URL from WatchCharts.
2) Run WatchCharts crawl using that URL.
3) Run Chrono24 market price enrichment on the new output.
4) Run TheWatchAPI history (uses the Chrono24 output if present).
5) Transform + deploy.

## Environment essentials
- WatchCharts: `BRIGHTDATA_API_KEY`, `BRIGHTDATA_WEB_ACCESS_ZONE`
- Chrono24: `FLARESOLVERR_URL` (run `./scripts/start_flaresolverr.sh`)
- TheWatchAPI: `THEWATCHAPI_API_KEY`
- Optional env file: `WATCHCHARTS_ENV_FILE`

## Notes
- For performance, use Bright Data for WatchCharts and FlareSolverr for Chrono24.
- Use small `--limit` when testing to avoid long runs.
- Prefer running the TUI (monorepo `/tui`) for orchestration and logs.
