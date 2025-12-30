# Watchcollection TUI

## Run
- `npm install`
- `npm run dev`

## Key bindings
- Arrow keys: select brand
- `w`: run WatchCharts for selected brand
- `c`: run Chrono24 market price for selected brand
- `t`: run TheWatchAPI history for selected brand
- `a`: add brand (WatchCharts URL, then slug)
- `g`: build catalog + deploy (Railway)
- `r`: refresh list
- `q` or `Esc`: quit

## Notes
- Uses `crawler/output_watchcharts` for status detection.
- Requires Bright Data for WatchCharts and FlareSolverr for Chrono24.
- Deploy uses `railway up` from `api/`.
- TUI will prefer `crawler/venv/bin/python` or `crawler/.venv/bin/python`. Override via `TUI_PYTHON_BIN`.
- Deploy service defaults to `watch-api`. Override via `TUI_RAILWAY_SERVICE`.
