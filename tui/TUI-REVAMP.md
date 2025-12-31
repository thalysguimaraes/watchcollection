# TUI revamp — PR-by-PR plan

Based on the TUI backlog you provided (Epics A–D). Plans assume the runner API/CLI will be exposed as `watchcollection run` with JSON output and that the ingest DB is populated by the crawler’s `marketdata` pipelines.

---

## PR 1 — Single runner command integration

**Goal:** TUI shells out only to `watchcollection run --pipeline <name> --brand <brand> --mode <full|partial>` and consumes structured JSON.

**Changes**
- Replace per-phase script calls with one runner invocation; parse JSON status/progress from stdout.
- Remove filename assumptions from UI state; base status solely on runner responses.
- Add failure surface: show message + last error block from JSON.

**Acceptance criteria**
- Adding a new pipeline requires no TUI code change beyond listing it.
- TUI remains stable when pipeline internals/file names change.

---

## PR 2 — Real ingest status from DB

**Goal:** Show actual ingest runs, not file guesses.

**Changes**
- Add data source to read `ingest_run` table (sqlite path from env); poll or refresh on demand.
- Display per-brand last run: status, counts, failures, duration; add “view errors” drill-down.

**Acceptance criteria**
- After restart, TUI shows correct latest run info without re-running pipelines.
- Operator can pinpoint failure cause from the drill-down pane.

---

## PR 3 — Config surface + preflight checks

**Goal:** Centralize config and block runs when prerequisites are missing.

**Changes**
- Load single config file (YAML/TOML) + env overrides; render snapshot in a side panel (paths, sources enabled, limits).
- Add “Preflight” action that checks: DB connectivity, write perms, required binaries, source toggles; show actionable failures.

**Acceptance criteria**
- Operator can see current config values in UI before running.
- Missing prerequisites block the run with clear guidance.

---

## PR 4 — Run presets

**Goal:** 1–2 click common operations.

**Changes**
- Add preset definitions (e.g., Update catalog, Import watchcharts CSV, Run daily snapshots) with optional parameters (brands, concurrency).
- UI list of presets; pressing one triggers runner with prefilled args, editable before launch.

**Acceptance criteria**
- Operator can start standard runs quickly and consistently.

---

## PR 5 — Log viewer improvements

**Goal:** Debug from within TUI.

**Changes**
- Stream/tail logs for active run; add filters (warnings/errors); allow copying error blocks.
- Persist last N lines per run for post-mortem view.

**Acceptance criteria**
- Operator can locate an error within 60 seconds using filter/copy.

---

## PR 6 — UI polish for coverage/config

**Goal:** Better situational awareness.

**Changes**
- Add coverage summary sourced from `market_snapshot` (counts, last dates) per brand.
- Show active config badge (env name) and warnings for missing secrets/paths.

**Acceptance criteria**
- Coverage numbers match DB; config warnings highlight missing secrets before runs.

