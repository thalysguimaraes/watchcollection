# Recker POC: Anti-Blocking Stack Evaluation

Proof of concept comparing [recker](https://github.com/forattini-dev/recker) against the current anti-blocking stack (FlareSolverr, Bright Data, AntiCaptcha).

## Quick Start

```bash
# Install dependencies
npm install

# Setup curl-impersonate (required for Cloudflare bypass)
npm run setup

# Run full benchmark
npm run benchmark

# Or test individual sites
npm run test:watchcharts
npm run test:chrono24
```

## Compare with Current Stack

After running the recker benchmark, compare with the current Python stack:

```bash
cd ..
python -m poc_recker.compare_current_stack
```

## Test Results

Results are saved to:
- `results/report.json` - Recker test results
- `results/current_stack_report.json` - Current stack comparison

## What's Being Tested

### Target Sites
| Site | Protection | Expected Recker Result |
|------|------------|----------------------|
| WatchCharts | Cloudflare Turnstile (CAPTCHA) | FAIL - No CAPTCHA solving |
| Chrono24 | Cloudflare Managed | MAYBE - curl-impersonate may bypass |

### Test Methods
1. **Direct request** - Baseline HTTP request
2. **Chrome preset** - With Chrome user-agent and headers
3. **With retry** - Multiple attempts with exponential backoff

## Recker vs Current Stack

| Feature | Recker | FlareSolverr | Bright Data |
|---------|--------|--------------|-------------|
| Cost | Free | Free (Docker) | ~$0.01/req |
| TLS Fingerprint | curl-impersonate | Real browser | Residential IPs |
| CAPTCHA Solving | No | No | Via AntiCaptcha |
| Proxy Rotation | No | No | Yes |
| Speed | Fast (~100ms) | Slow (~5-10s) | Medium (~1-2s) |
| Setup | npm install | Docker | API key |

## Expected Outcomes

1. **WatchCharts**: Recker will FAIL (Turnstile requires CAPTCHA solving)
2. **Chrono24**: Recker MAY succeed (curl-impersonate handles TLS fingerprinting)

## Decision Matrix

| Outcome | Recommendation |
|---------|----------------|
| Both pass | Replace entire stack with recker |
| Chrono24 only | Replace FlareSolverr for Chrono24, keep Bright Data for WatchCharts |
| Both fail | Keep current stack - recker unsuitable for these targets |

---

## Actual Test Results (2025-12-30)

### Phase 1: Recker WITHOUT curl-impersonate - FAILED

| Site | Method | Status | Time | Result |
|------|--------|--------|------|--------|
| WatchCharts | direct | 403 | 1305ms | BLOCKED |
| WatchCharts | +chrome | 403 | 1163ms | BLOCKED |
| Chrono24 | direct | 403 | 1252ms | BLOCKED |
| Chrono24 | +chrome | 403 | 1134ms | BLOCKED |
| httpbin.org | direct | 200 | 1708ms | SUCCESS |

**Issue**: `npx recker setup` fails on macOS: "Auto-install not yet supported on macOS"

### Phase 2: curl-impersonate via Docker - SUCCESS!

```bash
# Test command
docker run --rm lwthiker/curl-impersonate:0.6-chrome \
  curl_chrome116 -s "https://watchcharts.com/watches"
```

| Site | Status | Time | Result |
|------|--------|------|--------|
| WatchCharts /watches | 200 | 889ms | **SUCCESS** |
| WatchCharts / | 200 | 850ms | **SUCCESS** |
| Chrono24 /rolex/index.htm | 200 | 1361ms | **SUCCESS** |
| Chrono24 /search?query=rolex | 200 | 387ms | **SUCCESS** |

**Key Finding**: curl-impersonate bypasses Cloudflare on **BOTH sites** - including WatchCharts which we thought required Turnstile CAPTCHA solving!

### Why It Works

The TLS fingerprint from curl-impersonate matches Chrome exactly, so Cloudflare doesn't present a challenge. The "Turnstile CAPTCHA" is only shown when Cloudflare detects a suspicious TLS fingerprint.

### Recommendation: PARTIAL REPLACEMENT POSSIBLE

| Option | Description | Cost |
|--------|-------------|------|
| **curl-impersonate Docker** | Replace FlareSolverr & potentially Bright Data | $0 |
| Keep current stack | Known working, but slower and costly | ~$12/1000 req |

### Implementation Path

```bash
# Quick test any URL
docker run --rm lwthiker/curl-impersonate:0.6-chrome \
  curl_chrome116 -sL "https://watchcharts.com/watches"
```

### Phase 3: Scale Testing (20 requests per site)

| Site | Delay | Success Rate | Issues |
|------|-------|--------------|--------|
| WatchCharts | 1s | 65% | 429 rate limiting after ~7 requests |
| Chrono24 | 1s | 80% | Occasional 403s |
| WatchCharts | 3s | **100%** | No rate limiting |
| Chrono24 | 3s | **100%** | No issues |

**Key Finding**: 2-4s random delay between requests achieves 100% success rate.

---

## Python Integration

The `CurlImpersonateClient` provides a drop-in replacement for FlareSolverr:

```python
from watchcollection_crawler.core import CurlImpersonateClient, AsyncCurlImpersonateClient

# Sync client
client = CurlImpersonateClient()
html = client.get("https://watchcharts.com/watches")
soup = client.get_soup("https://www.chrono24.com/rolex/index.htm")

# Async client with built-in rate limiting (2-4s random delay per domain)
async_client = AsyncCurlImpersonateClient(
    min_delay=2.0,
    max_delay=4.0,
    max_concurrent=10,
)
results = await async_client.get_many([url1, url2, url3])
```

### Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `CURL_IMPERSONATE_IMAGE` | `lwthiker/curl-impersonate:0.6-chrome` | Docker image |
| `CURL_IMPERSONATE_BINARY` | `curl_chrome116` | curl binary to use |
| `CURL_IMPERSONATE_TIMEOUT` | `30` | Request timeout (seconds) |
| `CURL_IMPERSONATE_MIN_DELAY` | `2.0` | Min delay between requests |
| `CURL_IMPERSONATE_MAX_DELAY` | `4.0` | Max delay between requests |

---

## Final Recommendation: REPLACE STACK

| Component | Current | Replacement | Savings |
|-----------|---------|-------------|---------|
| Chrono24 | FlareSolverr (5-10s/req) | curl-impersonate (~1s/req) | 5-10x faster |
| WatchCharts | Bright Data ($0.01/req) | curl-impersonate ($0/req) | **$12/1000 req** |

### Migration Path

1. **Chrono24**: Replace FlareSolverr with `CurlImpersonateClient` immediately
2. **WatchCharts**: Replace Bright Data for catalog scraping (rate-limited to 2-4s delay)
3. **High Volume**: Keep Bright Data as fallback for burst traffic requiring IP rotation

### Cost Analysis (per 1000 requests)

| Stack | Cost | Speed |
|-------|------|-------|
| Current (Bright Data + FlareSolverr) | ~$12 | Mixed |
| curl-impersonate (rate-limited) | **$0** | ~3s/req avg |

---

## Technical Notes

### macOS arm64 Installation Issue

Native curl-impersonate binary for macOS arm64 doesn't exist:
- x86_64 binary requires x86 Homebrew libraries
- Docker workaround works via Rosetta 2 emulation
- For production: run on Linux where recker + curl-impersonate works natively

### Why curl-impersonate Works

Cloudflare's bot detection relies heavily on TLS fingerprinting. Standard HTTP clients (requests, httpx, aiohttp) have TLS fingerprints that differ from browsers. curl-impersonate compiles libcurl with BoringSSL (Chrome's TLS library) and mimics Chrome's exact TLS handshake, making requests indistinguishable from a real browser.

### Rate Limiting Strategy

Both sites implement rate limiting:
- **WatchCharts**: Returns 429 after sustained traffic
- **Chrono24**: Returns 403 for suspected automation

Solution: Random 2-4s delay between requests to same domain (built into `AsyncCurlImpersonateClient`)
