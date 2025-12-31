# API revamp — PR-by-PR plan

Mapped to the backlog you pasted (Epics A–G). Each PR is sized to review cleanly and aligns with the existing FastAPI single-file service in `api/main.py`. Where new modules are referenced, create them under `api/` to keep the app lightweight.

---

## Implementation Status

| PR | Status | Files |
|----|--------|-------|
| PR 1 | ✅ Done | `main.py`, `.github/workflows/secret-scan.yml`, `.gitleaks.toml` |
| PR 2 | ✅ Done | `auth.py`, `routes/auth.py` |
| PR 3 | ✅ Done | `auth.py`, `routes/auth.py` |
| PR 4 | ✅ Done | `database.py`, `routes/market.py` |
| PR 5 | ✅ Done | `database.py`, `routes/market.py` |
| PR 6 | ✅ Done | `database.py`, `routes/admin.py` |
| PR 7 | ✅ Done | `database.py`, `routes/admin.py` |
| PR 8 | ✅ Done | `database.py`, `models/`, `alembic/` |
| PR 9 | ✅ Done | `routes/ai.py` |
| PR 10 | ✅ Done | `middleware/` |

---

## PR 1 — Purge secret-leaking endpoints & add basic secret scanning ✅

**Goal:** No response ever contains vendor API keys; prevent regressions.

**Changes**
- Remove any `/config` or debug endpoints that return provider keys from `main.py` (and delete stale helper functions if present).
- Rotate exposed keys and move remaining secrets to environment variables only; document in `README`/`Procfile` what must be set at deploy.
- Add a lightweight secret scan to CI (e.g., `detect-secrets` or `gitleaks`) with a baseline checked into repo.

**Acceptance criteria**
- Grep for `sk-`, `api_key`, `anthropic`, `openai` in responses returns nothing.
- CI fails if a new credential-looking string is added.

---

## PR 2 — Authentication foundation (user identity) ✅

**Goal:** Every request is attributable to a user so entitlements and rate limits can be enforced.

**Changes**
- Introduce `/auth/login` and `/auth/callback` for Sign in with Apple *or* `/auth/magic-link` flow; issue a signed session/JWT containing `user_id` and expiry.
- Add `auth.py` with token verification helpers; inject a FastAPI dependency to populate `request.state.user`.
- Add user store (SQLite/Postgres via PR8 ORM) with minimal `users` table.

**Acceptance criteria**
- Protected routes reject missing/expired tokens with 401.
- Token refresh path exists (short-lived access, longer-lived refresh or session cookie).

---

## PR 3 — Subscription verification + entitlement token ✅

**Goal:** Server can prove a user is Pro and issue a short-lived entitlement token for client/API use.

**Changes**
- Add receipt verification service: either native StoreKit server-side validation or RevenueCat webhook → update `user.entitlement` to `free|pro`.
- Create `/auth/entitlement` that returns a signed JWT (claims: `sub`, `entitlement`, `iat`, `exp`) used by the Swift app and AI endpoints.
- Add background job or webhook handler to handle expirations/grace periods.

**Acceptance criteria**
- Spoofed/old receipts are rejected; Pro status toggles correctly after expiry.
- Entitlement JWT expires quickly (<1h) and is required for Pro-only routes.

---

## PR 4 — `GET /market/history/{watchId}` endpoint ✅

**Goal:** Serve time-series data on demand with caching and coverage metadata.

**Changes**
- Add route returning `{points: [[ts, price]], source, start_date, end_date, points_count}`.
- Wire to the crawler `marketdata` SQLite/Postgres tables; respect `If-None-Match`/`If-Modified-Since` and emit ETag/Last-Modified headers.
- Downsample (e.g., weekly) in handler or via DB view to keep payload small.

**Acceptance criteria**
- Cold request <1s, warm <300ms; conditional GET returns 304 when unchanged.
- Coverage metadata reflects actual DB rows.

---

## PR 5 — `GET /market/summary/{watchId}` endpoint ✅

**Goal:** Fast card-level price summary for the app.

**Changes**
- Precompute or query latest snapshot + deltas (1m/6m/1y) from series; store in DB view/materialized table.
- Response: `{price, change_pct: {1m,6m,1y}, last_updated}`.
- Share caching headers and auth requirements with PR4.

**Acceptance criteria**
- Summary matches the history series for the same watch.
- Latency comparable to PR4 cached path.

---

## PR 6 — Admin `/stats/ingest-runs` endpoint ✅

**Goal:** Surface pipeline health without digging in logs.

**Changes**
- Persist ingest runs in DB (`ingest_run` table already exists in crawler); expose latest runs filtered by pipeline/date, including counts/errors/meta.
- Add optional `?pipeline=chrono24&limit=50` filtering.
- Protect with admin auth (reuse middleware from PR2).

**Acceptance criteria**
- One call shows latest runs with counts and error messages.
- Unauthorized callers get 403.

---

## PR 7 — Admin `/stats/coverage` endpoint ✅

**Goal:** Quantify history coverage for dashboards.

**Changes**
- Query coverage aggregates per brand/watch: `{watchcharts_id, brand_slug, start_date, end_date, points, gaps}`.
- Add aggregation summary (percent with >N points, etc.).

**Acceptance criteria**
- Output is JSON-ready for charts; filters by brand/date range.
- Numbers reconcile with the underlying `market_snapshot` table.

---

## PR 8 — Introduce ORM + migrations ✅

**Goal:** Make schema changes reproducible across dev/staging/prod.

**Changes**
- Add SQLAlchemy models for `user`, `market_snapshot`, `ingest_run`, `usage_log`, etc.
- Add Alembic migrations and a `make migrate`/`python -m alembic upgrade head` path; document local setup.
- Update existing handlers (PR4–PR7) to use the ORM session.

**Acceptance criteria**
- Fresh checkout can run `alembic upgrade head` and start the API.
- Migrations are committed; no drift between code and DB.

---

## PR 9 — `POST /ai/identify` (Pro-only) with usage logging ✅

**Goal:** Server-side AI image identification that enforces entitlements and tracks cost.

**Changes**
- Endpoint accepts image upload or URL; validates entitlement JWT from PR3.
- Server-side call to provider (OpenAI/Anthropic/etc.); redact keys from responses.
- Insert usage record (`user_id`, `watch_id?`, `tokens/credits`, `provider`, `latency`, `status`) into `usage_log` table.
- Apply per-user rate limit and provider circuit breaker (reuse PR10 middleware).

**Acceptance criteria**
- Free users receive 402/403; Pro succeeds.
- Every call is logged with user_id and cost metadata; keys never leave the server.

---

## PR 10 — Rate limiting, circuit breaker, and structured tracing ✅

**Goal:** Protect paid endpoints and improve debuggability.

**Changes**
- Add rate-limit middleware (fastapi-limiter or custom) keyed by `user_id` + IP; stricter buckets for AI endpoints.
- Add simple circuit breaker around provider SDK calls with fallback responses.
- Add request/response logging with request ID, user_id (if present), latency, and error taxonomy; emit JSON to stdout for Railway.
- Propagate request IDs via response headers and log correlation.

**Acceptance criteria**
- Exceeding limits returns 429 with retry hints.
- Logs show request_id + user_id for every call; traces can be correlated across services.
