# Swift app revamp — PR-by-PR plan

Derived from the Swift app backlog (Epics A–E). Each PR is scoped to be reviewable in Xcode, keeps StoreKit 2 work isolated from catalog/DB work, and aligns with the existing service layers in `swift-app/watchcollection/Services/`.

---

## PR 1 — StoreKit 2 subscriptions & entitlement cache

**Goal:** App can determine Free vs Pro and persist locally (offline tolerant).

**Changes**
- Define monthly/yearly products in code (`Product.Subscription`).
- Implement purchase + restore flows via StoreKit 2; surface state via `EntitlementStore` (new) backed by secure storage (Keychain or SQLite table in `DatabaseManager`).
- Handle expiration, billing retry, and grace periods; refresh on app launch and foreground.

**Acceptance criteria**
- Purchasing updates UI immediately; restore works after reinstall.
- Entitlement survives app restart and short offline windows using last-known state + expiry.

---

## PR 2 — Gate AI features behind Pro

**Goal:** AI UI and network calls are blocked for Free users.

**Changes**
- Add feature flag helper (`Feature.aiEnabled`) keyed off entitlement.
- Wrap AI flows (camera upload, identification) with paywall screens; CTA to subscribe.
- Include entitlement token in AI requests once API issues it (see API PR3); handle 402/403 gracefully.

**Acceptance criteria**
- Free user cannot trigger AI calls; Pro user path unchanged.
- UI shows clear upgrade path; network layer refuses to send AI calls without token.

---

## PR 3 — Catalog import pruning and integrity

**Goal:** Local DB mirrors server truth after each import.

**Changes**
- Add catalog version marker per bundle; store in DB.
- On import: mark all existing models `seen_in_import=false`, upsert new/updated with `seen_in_import=true`, then delete/archive remaining false.
- Keep work in a single transaction; add hashing/size checks for bundle before apply.

**Acceptance criteria**
- Models removed server-side disappear locally after import.
- Interrupted import does not corrupt DB; either old or new state remains valid.

---

## PR 4 — Background refresh + resilient downloads

**Goal:** Reliable bundle updates without breaking state.

**Changes**
- Add background fetch/refresh task; use retry with backoff.
- Validate bundle integrity (hash/length) before applying; on failure keep existing DB.
- Support partial failure: keep old bundle if new fails; surface non-blocking error to user.

**Acceptance criteria**
- Interrupted or bad download leaves app usable with previous catalog.
- Retries follow exponential backoff and cap.

---

## PR 5 — DB/query performance (collection + wishlist)

**Goal:** Remove N+1s and keep UI smooth with large collections.

**Changes**
- Replace per-item lookups with joined queries; add indexes (brand_id, watch_id, reference).
- Profile collection/wishlist screens; batch fetch related rows.

**Acceptance criteria**
- Collection query is O(1) round-trips; smooth scroll at 200+ items in simulator profiling.

---

## PR 6 — Search/FTS tuning

**Goal:** Faster, better-ranked search.

**Changes**
- Revisit FTS tokenization for references with hyphens/spaces.
- Add simple ranking/normalization; cache common queries in memory.

**Acceptance criteria**
- Typical queries return in <150ms locally; ranking handles hyphen variants.

---

## PR 7 — Market data on-demand

**Goal:** Avoid bundling large history; fetch per-watch.

**Changes**
- Integrate new API endpoints: `GET /market/history/{id}` and `/market/summary/{id}`.
- Add local cache table for history with ETag/updated_at; invalidate on 304/412.

**Acceptance criteria**
- Bundle stays small; watch detail loads history when opened; cache respected.

---

## PR 8 — History quality messaging

**Goal:** Honest UX when data is sparse.

**Changes**
- Detect coverage (days/points) from cached series; flag sparse series.
- Display “limited history available” state; avoid misleading line joins over big gaps.

**Acceptance criteria**
- Sparse histories show a dedicated message and non-misleading chart.

---

## PR 9 — Observability: crashes + structured logs

**Goal:** Production debugging.

**Changes**
- Integrate Crashlytics/Sentry; include build version/commit.
- Add structured logging categories (sync, db, ui, networking) piped to OSLog; redact PII.

**Acceptance criteria**
- Crashes appear in dashboard with stack + build metadata.
- Logs are searchable by category; no secrets emitted.

---

## PR 10 — Importer + migration tests

**Goal:** Guard against silent data corruption.

**Changes**
- Add unit tests for catalog importer parsing and DB writes (golden files for sample bundle).
- Add migration tests covering upgrade paths; run in CI.

**Acceptance criteria**
- CI runs importer + migration tests on PRs; failures block merges.

