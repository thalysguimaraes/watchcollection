# Watch Catalog API

FastAPI server for watch collection catalog data with market analytics, authentication, and AI-powered watch identification.

## Table of Contents

- [Quick Start](#quick-start)
- [Environment Variables](#environment-variables)
- [API Endpoints](#api-endpoints)
- [Authentication](#authentication)
- [Database Setup](#database-setup)
- [Architecture](#architecture)
- [Development](#development)

---

## Quick Start

```bash
cd api
pip install -r requirements.txt

# Run migrations (creates user/usage_log tables)
alembic upgrade head

# Start server
uvicorn main:app --reload --port 8000
```

The API will be available at `http://localhost:8000`. Swagger docs at `/docs`.

---

## Environment Variables

| Variable | Required | Default | Description |
|----------|----------|---------|-------------|
| `JWT_SECRET` | **Production** | `dev-secret-change-in-prod` | Secret key for JWT signing. **Must change in production.** |
| `ADMIN_API_KEY` | Yes | - | API key for admin endpoints (`/stats/*`) |
| `ANTHROPIC_API_KEY` | For AI | - | Anthropic API key for `/ai/identify` endpoint |
| `DATABASE_URL` | No | `sqlite:///./data/api.sqlite` | SQLAlchemy database URL |
| `MARKETDATA_DB_PATH` | No | `../crawler/output/marketdata.sqlite` | Path to crawler's marketdata database |
| `DEBUG` | No | - | If set, magic link tokens are returned in response |

### Railway Deployment

Set these in Railway dashboard → Variables:
```
JWT_SECRET=<generate-secure-random-string>
ADMIN_API_KEY=<your-admin-key>
ANTHROPIC_API_KEY=<your-anthropic-key>
```

---

## API Endpoints

### Health & Status

| Endpoint | Method | Auth | Description |
|----------|--------|------|-------------|
| `GET /` | GET | - | Service status |
| `GET /health` | GET | - | Health check for load balancers |

### Catalog (Public)

| Endpoint | Method | Auth | Description |
|----------|--------|------|-------------|
| `GET /catalog` | GET | - | Full catalog with all brands and models. Supports ETag caching. |
| `GET /catalog/version` | GET | - | Current catalog version string |
| `GET /brands` | GET | - | List all brands (id, name, country, tier) |
| `GET /brands/{brand_id}` | GET | - | Single brand with all its models |
| `GET /brands/{brand_id}/models` | GET | - | List models for a brand |
| `GET /models/{reference}` | GET | - | Single model by reference number |
| `GET /search?q={query}&limit={n}` | GET | - | Full-text search across models |

**Caching:** `/catalog` and `/catalog/version` support conditional requests via `ETag` and `Last-Modified` headers.

### Market Data

| Endpoint | Method | Auth | Description |
|----------|--------|------|-------------|
| `GET /market/history/{watchId}` | GET | - | Price history time series |
| `GET /market/summary/{watchId}` | GET | - | Latest price with 1m/6m/1y deltas |

**History Response:**
```json
{
  "points": [[1704067200, 10800], [1704153600, 10950]],
  "source": "watchcharts_csv+chrono24",
  "start_date": "2024-01-01",
  "end_date": "2025-12-31",
  "points_count": 52
}
```

**Summary Response:**
```json
{
  "price": 11200,
  "min_usd": 9500,
  "max_usd": 13500,
  "listings": 42,
  "change_pct": {
    "1m": 2.5,
    "6m": -5.2,
    "1y": 8.1
  },
  "last_updated": "2025-12-31"
}
```

### Authentication

| Endpoint | Method | Auth | Description |
|----------|--------|------|-------------|
| `POST /auth/magic-link` | POST | - | Request magic link login |
| `GET /auth/verify?token={token}` | GET | - | Verify magic link, get JWT tokens |
| `POST /auth/refresh` | POST | - | Refresh access token |
| `GET /auth/entitlement` | GET | JWT | Get short-lived entitlement token |
| `POST /auth/verify-receipt` | POST | JWT | Verify subscription receipt |
| `GET /auth/me` | GET | JWT | Get current user info |

**Magic Link Flow:**
```bash
# 1. Request magic link
curl -X POST http://localhost:8000/auth/magic-link \
  -H "Content-Type: application/json" \
  -d '{"email": "user@example.com"}'

# 2. Verify token (from email link)
curl "http://localhost:8000/auth/verify?token=<magic-link-token>"

# Response:
{
  "access_token": "eyJ...",
  "refresh_token": "eyJ...",
  "token_type": "bearer",
  "expires_in": 3600
}
```

**Using JWT:**
```bash
curl http://localhost:8000/auth/me \
  -H "Authorization: Bearer <access_token>"
```

### Admin Endpoints

Require `X-Admin-Key` header matching `ADMIN_API_KEY` env var.

| Endpoint | Method | Auth | Description |
|----------|--------|------|-------------|
| `GET /stats/ingest-runs` | GET | Admin | Pipeline execution history |
| `GET /stats/coverage` | GET | Admin | Market data coverage stats |

**Ingest Runs:**
```bash
curl "http://localhost:8000/stats/ingest-runs?pipeline=chrono24&limit=10" \
  -H "X-Admin-Key: your-admin-key"
```

Response:
```json
{
  "runs": [
    {
      "run_id": 42,
      "pipeline": "chrono24_market",
      "started_at": "2025-12-31T10:00:00",
      "finished_at": "2025-12-31T10:15:00",
      "ok": true,
      "rows_in": 1000,
      "rows_out": 950,
      "errors": 5,
      "warnings": 10,
      "meta": {}
    }
  ],
  "total": 42
}
```

**Coverage Stats:**
```bash
curl "http://localhost:8000/stats/coverage?brand=rolex&min_points=10" \
  -H "X-Admin-Key: your-admin-key"
```

Response:
```json
{
  "coverage": [
    {
      "watchcharts_id": "rolex-submariner-116610ln",
      "brand_slug": "rolex",
      "reference": "116610LN",
      "start_date": "2024-01-01",
      "end_date": "2025-12-31",
      "points": 52,
      "sources": ["watchcharts_csv", "chrono24"]
    }
  ],
  "summary": {
    "total_watches": 1500,
    "with_10_plus_points": 1200,
    "coverage_pct": 80.0
  }
}
```

### AI Watch Identification (Pro Only)

Requires Pro subscription (entitlement = "pro").

| Endpoint | Method | Auth | Description |
|----------|--------|------|-------------|
| `POST /ai/identify` | POST | Pro JWT | Identify watch from image |

**Usage:**
```bash
# With image URL
curl -X POST http://localhost:8000/ai/identify \
  -H "Authorization: Bearer <pro-access-token>" \
  -H "Content-Type: application/json" \
  -d '{"image_url": "https://example.com/watch.jpg"}'

# With file upload
curl -X POST http://localhost:8000/ai/identify \
  -H "Authorization: Bearer <pro-access-token>" \
  -F "image=@watch.jpg"
```

Response:
```json
{
  "brand": "Rolex",
  "model_reference": "116610LN",
  "display_name": "Submariner Date",
  "confidence": 0.95,
  "details": {
    "dial_color": "black",
    "case_material": "steel",
    "bezel": "ceramic",
    "year_estimate": "2015-2020"
  }
}
```

**Error Responses:**
- `401` - Missing or invalid JWT
- `402` - Pro subscription required
- `429` - Rate limit exceeded (10 req/min)
- `503` - AI service unavailable (circuit breaker open)

---

## Authentication

### JWT Token Types

| Type | Expiry | Use Case |
|------|--------|----------|
| `access` | 60 min | API authentication |
| `refresh` | 7 days | Obtain new access token |
| `entitlement` | 1 hour | Short-lived Pro status proof |

### Token Claims

```json
{
  "sub": "user-uuid",
  "entitlement": "free|pro",
  "iat": 1704067200,
  "exp": 1704070800,
  "type": "access|refresh|entitlement"
}
```

### Entitlements

| Level | Access |
|-------|--------|
| `free` | Catalog, search, market data |
| `pro` | All free features + AI identification |

---

## Database Setup

### API Database (SQLAlchemy + Alembic)

Stores users and usage logs.

```bash
# Create tables
alembic upgrade head

# Create new migration after model changes
alembic revision --autogenerate -m "description"

# Rollback
alembic downgrade -1
```

**Tables:**
- `user` - User accounts (id, email, entitlement, apple_user_id)
- `usage_log` - AI endpoint usage tracking

### Market Data Database (SQLite)

Read-only access to crawler's `marketdata.sqlite`:
- `market_snapshot` - Price snapshots by watch/date/source
- `ingest_run` - Pipeline execution metadata

Configure path via `MARKETDATA_DB_PATH` env var.

---

## Architecture

```
api/
├── main.py              # FastAPI app, catalog store, core endpoints
├── auth.py              # JWT creation/verification helpers
├── database.py          # DB connections (ORM + marketdata SQLite)
│
├── middleware/
│   ├── rate_limit.py    # slowapi rate limiting (100/min default, 10/min AI)
│   ├── logging.py       # JSON structured logging to stdout
│   └── circuit_breaker.py # Protect against provider outages
│
├── routes/
│   ├── auth.py          # /auth/* endpoints
│   ├── market.py        # /market/* endpoints
│   ├── admin.py         # /stats/* endpoints
│   └── ai.py            # /ai/identify endpoint
│
├── models/
│   ├── user.py          # User SQLAlchemy model
│   └── usage.py         # UsageLog SQLAlchemy model
│
├── alembic/             # Database migrations
│   └── versions/
│
└── data/
    ├── api.sqlite       # User/usage database (auto-created)
    └── catalog_bundle.json  # Catalog data from crawler
```

### Request Flow

```
Request → Rate Limit → Request Tracking Middleware → Router → Handler
                              ↓
                        JSON Logging (stdout)
                              ↓
                        X-Request-ID Header
```

### Observability

Every request logs:
```json
{
  "timestamp": "2025-12-31T12:00:00Z",
  "level": "INFO",
  "message": "request_completed",
  "request_id": "uuid",
  "method": "GET",
  "path": "/catalog",
  "status": 200,
  "latency_ms": 45
}
```

---

## Development

### Local Setup

```bash
# Install dependencies
pip install -r requirements.txt

# Set dev environment
export DEBUG=1
export ADMIN_API_KEY=dev-admin-key
export ANTHROPIC_API_KEY=sk-ant-...  # Optional, for AI endpoint

# Run migrations
alembic upgrade head

# Start with auto-reload
uvicorn main:app --reload --port 8000
```

### Testing Endpoints

```bash
# Health check
curl http://localhost:8000/health

# Search
curl "http://localhost:8000/search?q=submariner&limit=5"

# Market data
curl http://localhost:8000/market/summary/rolex-submariner-116610ln

# Admin (requires ADMIN_API_KEY)
curl http://localhost:8000/stats/ingest-runs \
  -H "X-Admin-Key: dev-admin-key"
```

### Rate Limits

| Endpoint Pattern | Limit |
|------------------|-------|
| Default | 100/minute |
| `/search` | 30/minute |
| `/ai/*` | 10/minute |

Exceeded limits return `429 Too Many Requests` with `Retry-After` header.

### Dependencies

```
fastapi==0.115.6       # Web framework
uvicorn[standard]      # ASGI server
pydantic==2.10.4       # Data validation
sqlalchemy>=2.0        # ORM
alembic>=1.13          # Migrations
pyjwt>=2.8             # JWT tokens
slowapi>=0.1.9         # Rate limiting
python-json-logger>=2.0 # Structured logging
anthropic>=0.40.0      # AI provider
httpx>=0.27.0          # Async HTTP client
```

---

## Security

### Secrets Management

- **Never commit secrets** - Use environment variables
- **CI scanning** - Gitleaks runs on every push (`.github/workflows/secret-scan.yml`)
- **JWT rotation** - Change `JWT_SECRET` periodically in production

### Removed Endpoints

The `/config` endpoint that previously exposed `ANTHROPIC_API_KEY` has been removed (security fix).

### Rate Limiting

All endpoints are rate-limited to prevent abuse. AI endpoints have stricter limits.

### Circuit Breaker

AI provider calls are protected by a circuit breaker:
- Opens after 5 consecutive failures
- Recovers after 60 seconds
- Returns 503 when open
