# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Watch collection management system with three components:
- **swift-app/**: iOS app (SwiftUI + GRDB) for managing personal watch collections
- **api/**: FastAPI catalog server deployed on Railway
- **crawler/**: Python data pipelines for watch catalog data aggregation

## Commands

### Swift App
```bash
# Build
xcodebuild -project swift-app/watchcollection.xcodeproj -scheme watchcollection -configuration Debug build

# Run tests
xcodebuild -project swift-app/watchcollection.xcodeproj -scheme watchcollection test
```

### API Server
```bash
cd api
pip install -r requirements.txt
uvicorn main:app --reload --port 8000
```

### Crawler
```bash
cd crawler
python -m venv venv && source venv/bin/activate
pip install -r requirements.txt

# Catalog crawl
python -m watchcollection_crawler.pipelines.catalog --phase 1 --models 50

# WatchCharts crawl
python -m watchcollection_crawler.pipelines.watchcharts --entry-url "URL" --brand "Brand"

# Download images
python -m watchcollection_crawler.pipelines.images --brand rolex

# Transform to API format
python -m watchcollection_crawler.pipelines.transform --brand-slug rolex

# Merge catalogs
python -m watchcollection_crawler.pipelines.merge

# Enrich prices
python -m watchcollection_crawler.pipelines.price_enricher

# FlareSolverr (Cloudflare bypass)
./scripts/start_flaresolverr.sh
```

## Architecture

### Data Flow
```
Crawler → api/data/catalog_bundle.json → API Server → iOS App SQLite
```

### iOS App (swift-app/)
- **DatabaseManager**: GRDB singleton with SQLite migrations (v1-v3), FTS4 search
- **CatalogImporter**: Fetches catalog from API with ETag caching, imports to local DB
- **Models**: Brand, WatchModel, CollectionItem, WatchPhoto, PriceRecord
- **Navigation**: Tab-based (Collection, Catalog, Settings) via AppState

Database location: `~/Library/Application Support/watchcollection.sqlite`

### API Server (api/)
- **CatalogStore**: Thread-safe in-memory cache from `data/catalog_bundle.json`
- Auto-reloads on file change, supports ETag/Last-Modified conditional requests
- Endpoints: `/catalog`, `/brands`, `/brands/{id}/models`, `/models/{ref}`, `/search`

### Crawler (crawler/)
- **pipelines/**: CLI modules (catalog, watchcharts, photos, images, transform, merge, cleanup, price_enricher)
- **sources/**: Site-specific parsers (chrono24)
- **core/**: Shared clients (flaresolverr, paths)
- Output dirs configurable via env vars: `WATCHCOLLECTION_OUTPUT_DIR`, `WATCHCHARTS_OUTPUT_DIR`, `WATCHCHARTS_IMAGES_DIR`, `WATCHCOLLECTION_API_DATA_DIR`

### Key Data Models
API returns snake_case JSON; iOS DTOs (CatalogDTOs.swift) convert to camelCase WatchModel objects. Market price data includes min/max/median USD values with listing counts.
