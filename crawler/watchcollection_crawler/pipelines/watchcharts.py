#!/usr/bin/env python3
import argparse
import asyncio
import inspect
import json
import os
import re
import sys
import time
import uuid
from datetime import datetime
from dataclasses import dataclass
from typing import Any, List, Optional, Tuple
from urllib.parse import urlparse, urlencode, parse_qs, urlunparse, unquote

import httpx
from bs4 import BeautifulSoup, FeatureNotFound

# Fallback stubs: requirements no longer include Playwright/AntiCaptcha/FlareSolverr.
# The crawler uses curl-impersonate; these are placeholders to keep imports working.
class AntiCaptchaProxy:  # pragma: no cover - stub
    def __init__(self, *args, **kwargs) -> None:
        pass


class AntiCaptchaClient:  # pragma: no cover - stub
    def __init__(self, *args, **kwargs) -> None:
        pass

    def get_balance(self) -> float:
        return 0.0


class FlareSolverrClient:  # pragma: no cover - stub
    async def request(self, *args, **kwargs):
        raise RuntimeError("FlareSolverr is disabled in this build")


class PlaywrightStealthClient:  # pragma: no cover - stub
    async def get_page(self, *args, **kwargs):
        raise RuntimeError("Playwright is disabled in this build")

try:
    from curl_cffi.requests import AsyncSession as CurlAsyncSession
except Exception:
    CurlAsyncSession = None

try:
    import h2  # noqa: F401
except Exception:
    h2 = None

try:
    from dotenv import load_dotenv
except Exception:
    load_dotenv = None

from watchcollection_crawler.core.curl_impersonate import AsyncCurlImpersonateClient
from watchcollection_crawler.core.paths import WATCHCHARTS_OUTPUT_DIR
from watchcollection_crawler.schemas_watchcharts import (
    WatchChartsModelDTO,
    WatchChartsBrandCatalog,
    CaseSpecs,
    MovementSpecs,
)
from watchcollection_crawler.utils.strings import slugify
from watchcollection_crawler.reference_matcher import generate_aliases

sys.stdout.reconfigure(line_buffering=True)
sys.stderr.reconfigure(line_buffering=True)

DEFAULT_WATCHCHARTS_BASE = "https://watchcharts.com"
CHALLENGE_TEXT_MARKERS = ("just a moment", "attention required", "checking your browser")
HTML_PARSER = "lxml"
LISTING_PAGE_SIZE = 24
LISTING_TERMINAL_HTTP = {"http 400", "http 404", "http 410"}
LISTING_RETRIES = 2
LISTING_RETRY_DELAY = 2.0

DEFAULT_USER_AGENT = (
    "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) "
    "AppleWebKit/537.36 (KHTML, like Gecko) "
    "Chrome/122.0.0.0 Safari/537.36"
)
DEFAULT_HEADERS = {
    "User-Agent": DEFAULT_USER_AGENT,
    "Accept": "text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,*/*;q=0.8",
    "Accept-Language": "en-US,en;q=0.9",
    "Cache-Control": "no-cache",
    "Pragma": "no-cache",
    "Upgrade-Insecure-Requests": "1",
}

BRAND_FILTERS = {
    "rolex": "eyItMiI6WyIyNCJdfQ%3D%3D",
}

OUTPUT_DIR = WATCHCHARTS_OUTPUT_DIR

PRICE_RE = re.compile(r"\$?([\d,]+)")
MM_RE = re.compile(r"(\d+(?:\.\d+)?)\s*mm", re.IGNORECASE)
WATER_RES_RE = re.compile(r"(\d+)\s*[mM]")
HOURS_RE = re.compile(r"(\d+)\s*hours?", re.IGNORECASE)
BPH_RE = re.compile(r"(\d+)\s*bph", re.IGNORECASE)
INT_RE = re.compile(r"(\d+)")
WATCH_MODEL_ID_RE = re.compile(r"/watch_model/(\d+)-")
REFERENCE_URL_RE = re.compile(r"/watch_model/\d+-[^/]*-(?P<ref>[A-Za-z0-9-]+)(?:/|$)")
REF_IN_TITLE_RE = re.compile(r"Ref\.?\s*([A-Za-z0-9.-]+)", re.IGNORECASE)
RETAIL_PRICE_RE = re.compile(r"Retail Price\s*\$?([\d,]+)")
MARKET_PRICE_RE = re.compile(r"Market Price\s*\$?([\d,]+)")


def parse_csv(value: Optional[str]) -> List[str]:
    if not value:
        return []
    return [part.strip() for part in value.split(",") if part.strip()]


def parse_netscape_cookies(file_path: str) -> List[dict]:
    cookies = []
    with open(file_path, "r") as f:
        for line in f:
            line = line.strip()
            if not line or line.startswith("#"):
                continue
            parts = line.split("\t")
            if len(parts) < 7:
                continue
            domain, _, path, secure, expires, name, value = parts[:7]
            if domain.startswith("."):
                domain = domain[1:]
            cookies.append({
                "name": name,
                "value": value,
                "domain": domain,
                "path": path,
                "secure": secure.upper() == "TRUE",
            })
    return cookies


@dataclass(frozen=True)
class ProxySettings:
    url: str
    server: str
    username: Optional[str]
    password: Optional[str]
    proxy_type: str


def _normalize_proxy_type(raw: Optional[str]) -> str:
    value = (raw or "http").lower()
    if value in {"socks5h"}:
        return "socks5"
    if value in {"socks4a"}:
        return "socks4"
    if value in {"http", "https", "socks4", "socks5"}:
        return value
    return "http"


def parse_proxy_settings(proxy_url: Optional[str], proxy_type: Optional[str] = None) -> Optional[ProxySettings]:
    if not proxy_url:
        return None
    parsed = urlparse(proxy_url)
    if not parsed.scheme:
        proxy_url = f"http://{proxy_url}"
        parsed = urlparse(proxy_url)

    if not parsed.hostname or not parsed.port:
        raise ValueError("Proxy URL must include host:port")

    username = unquote(parsed.username) if parsed.username else None
    password = unquote(parsed.password) if parsed.password else None
    server = f"{parsed.scheme}://{parsed.hostname}:{parsed.port}"
    proxy_type = _normalize_proxy_type(proxy_type or parsed.scheme)

    return ProxySettings(
        url=proxy_url,
        server=server,
        username=username,
        password=password,
        proxy_type=proxy_type,
    )


def classify_failure(reason: str) -> str:
    lower = (reason or "").lower()
    if "cloudflare challenge" in lower:
        return "challenge"
    if "http 403" in lower or "http 429" in lower or "http 503" in lower:
        return "challenge"
    if "timeout" in lower:
        return "timeout"
    return "other"


def is_listing_terminal_error(exc: Exception) -> bool:
    message = str(exc).lower()
    return any(token in message for token in LISTING_TERMINAL_HTTP)


def is_challenge_error(exc: Exception) -> bool:
    return classify_failure(str(exc)) == "challenge"


class WatchChartsFetcher:
    def __init__(
        self,
        concurrency: int,
        timeout: float,
        retries: int,
        backend: str,
        impersonate: str,
        proxy_settings: Optional[ProxySettings] = None,
        session_cookies: Optional[List[dict]] = None,
    ) -> None:
        # Only support curl-impersonate, curl_cffi, or httpx (no Playwright/AntiCaptcha/BrightData).
        self.retries = max(0, retries)
        self._bootstrap_url: Optional[str] = None
        self._stale_clients: List[Any] = []

        self._proxy_settings = proxy_settings
        self._proxy_url = proxy_settings.url if proxy_settings else None

        backend_choice = (backend or "curl-impersonate").lower()
        if backend_choice == "auto":
            backend_choice = "curl" if CurlAsyncSession else "httpx"
        if backend_choice not in {"curl", "httpx", "curl-impersonate"}:
            raise RuntimeError(f"Unknown backend '{backend_choice}'")
        if backend_choice == "curl" and not CurlAsyncSession:
            raise RuntimeError("curl_cffi is not installed; use --backend httpx or --backend curl-impersonate")
        self._backend = backend_choice
        self._timeout = timeout

        impersonate_list = parse_csv(impersonate) or ["chrome120"]
        self._impersonate_list = impersonate_list
        self._impersonate_index = 0
        self._impersonate = impersonate_list[0]

        self._curl: Optional[Any] = None
        self._curl_impersonate: Optional[AsyncCurlImpersonateClient] = None
        self._httpx: Optional[httpx.AsyncClient] = None

        max_conn = max(10, concurrency * 2)
        max_keepalive = max(10, concurrency)
        limits = httpx.Limits(
            max_connections=max_conn,
            max_keepalive_connections=max_keepalive,
        )
        timeout_cfg = httpx.Timeout(timeout, connect=min(timeout, 10.0))

        if self._backend == "curl":
            self._curl = CurlAsyncSession(
                headers=DEFAULT_HEADERS.copy(),
                impersonate=self._impersonate,
                proxy=self._proxy_url,
            )
        elif self._backend == "curl-impersonate":
            self._curl_impersonate = AsyncCurlImpersonateClient(
                timeout=int(timeout),
                max_concurrent=concurrency,
                use_docker=True,
            )
        else:
            self._httpx = httpx.AsyncClient(
                headers=DEFAULT_HEADERS.copy(),
                timeout=timeout_cfg,
                limits=limits,
                follow_redirects=True,
                http2=bool(h2),
                proxy=self._proxy_url,
            )

        self._session_cookies = session_cookies or []
        if self._session_cookies:
            self._apply_session_cookies()

    def _apply_session_cookies(self) -> None:
        for cookie in self._session_cookies:
            name = cookie.get("name")
            value = cookie.get("value", "")
            domain = cookie.get("domain", "watchcharts.com")
            path = cookie.get("path", "/")
            if not name:
                continue
            if self._httpx:
                self._httpx.cookies.set(name, value, domain=domain, path=path)
            if self._curl:
                self._curl.cookies.set(name, value, domain=domain, path=path)

    def get_cookie_header(self) -> str:
        if not self._session_cookies:
            return ""
        parts = []
        for c in self._session_cookies:
            if c.get("name") and c.get("value"):
                parts.append(f"{c['name']}={c['value']}")
        return "; ".join(parts)

    async def start(self, bootstrap_url: str) -> None:
        self._bootstrap_url = bootstrap_url

        if self._backend == "curl-impersonate":
            print("Using curl-impersonate (Docker)")

        try:
            status_code, text = await self._get(bootstrap_url)
            if status_code < 400 and not is_challenge_html(text):
                print("Initial request succeeded without challenge")
                return
        except Exception as exc:
            print(f"Bootstrap request failed ({exc})")
        # If challenged, the crawl will retry per-request with backoff.

    async def close(self) -> None:
        if self._httpx:
            await self._httpx.aclose()
        if self._curl:
            close = getattr(self._curl, "aclose", None) or getattr(self._curl, "close", None)
            if close:
                result = close()
                if inspect.isawaitable(result):
                    await result
        for client in self._stale_clients:
            close = getattr(client, "aclose", None) or getattr(client, "close", None)
            if close:
                result = close()
                if inspect.isawaitable(result):
                    await result

    def _next_impersonate(self) -> Optional[str]:
        if len(self._impersonate_list) <= 1:
            return None
        self._impersonate_index = (self._impersonate_index + 1) % len(self._impersonate_list)
        return self._impersonate_list[self._impersonate_index]

    def _swap_curl_session(self, impersonate: str) -> None:
        if not CurlAsyncSession:
            return
        if self._curl:
            self._stale_clients.append(self._curl)
        self._curl = CurlAsyncSession(
            headers=DEFAULT_HEADERS.copy(),
            impersonate=impersonate,
            proxy=self._proxy_url,
        )
        self._impersonate = impersonate

    async def _get(self, url: str, session_id: Optional[str] = None) -> tuple[int, str]:
        if self._curl_impersonate:
            return await self._curl_impersonate.get_status(url)
        if self._curl:
            resp = await self._curl.get(
                url,
                timeout=self._timeout,
                allow_redirects=True,
            )
            return resp.status_code, resp.text
        if not self._httpx:
            raise RuntimeError("HTTP client not initialized")
        resp = await self._httpx.get(url)
        return resp.status_code, resp.text

    async def _get_with_headers(
        self,
        url: str,
        headers: Optional[dict],
        session_id: Optional[str] = None,
    ) -> tuple[int, str]:
        if not headers:
            return await self._get(url, session_id=session_id)
        if self._curl_impersonate:
            return await self._curl_impersonate.get_status(url, headers=headers)
        if self._curl:
            resp = await self._curl.get(
                url,
                headers=headers,
                timeout=self._timeout,
                allow_redirects=True,
            )
            return resp.status_code, resp.text
        if not self._httpx:
            raise RuntimeError("HTTP client not initialized")
        resp = await self._httpx.get(url, headers=headers)
        return resp.status_code, resp.text

    async def fetch(
        self,
        url: str,
        session_id: Optional[str] = None,
    ) -> str:
        last_error: Optional[Exception] = None

        for attempt in range(self.retries + 1):
            try:
                status_code, text = await self._get(url, session_id=session_id)
                if status_code < 400 and not is_challenge_html(text):
                    return text
                if is_challenge_html(text):
                    last_error = RuntimeError("Cloudflare challenge")
                else:
                    last_error = RuntimeError(f"HTTP {status_code}")
            except Exception as exc:
                last_error = exc

            if attempt < self.retries:
                await asyncio.sleep(0.5 * (2**attempt))

        raise RuntimeError(f"Failed after {self.retries + 1} attempts: {last_error}")

    async def fetch_with_headers(
        self,
        url: str,
        headers: Optional[dict] = None,
        session_id: Optional[str] = None,
    ) -> str:
        last_error: Optional[Exception] = None

        for attempt in range(self.retries + 1):
            try:
                status_code, text = await self._get_with_headers(url, headers, session_id=session_id)
                if status_code < 400 and not is_challenge_html(text):
                    return text
                if is_challenge_html(text):
                    last_error = RuntimeError("Cloudflare challenge")
                else:
                    last_error = RuntimeError(f"HTTP {status_code}")
            except Exception as exc:
                last_error = exc

            if attempt < self.retries:
                await asyncio.sleep(1.0 * (2**attempt))

        raise RuntimeError(f"Failed to fetch {url}: {last_error}")


def derive_brand_slug(brand_slug: Optional[str], brand_name: Optional[str], entry_url: str) -> str:
    if brand_slug:
        return brand_slug
    if brand_name:
        return slugify(brand_name)

    parsed = urlparse(entry_url)
    filters = parse_qs(parsed.query).get("filters", [])
    if filters:
        for slug, value in BRAND_FILTERS.items():
            if value in filters:
                return slug

    return "watchcharts"


def derive_brand_name(brand_name: Optional[str], brand_slug: str) -> str:
    if brand_name:
        return brand_name
    return brand_slug.replace("_", " ").title()


def get_base_url(entry_url: str, base_url: Optional[str] = None) -> str:
    if base_url:
        return base_url.rstrip("/")
    parsed = urlparse(entry_url)
    if parsed.scheme and parsed.netloc:
        return f"{parsed.scheme}://{parsed.netloc}"
    return DEFAULT_WATCHCHARTS_BASE


def normalize_entry_url(entry_url: str, base_url: str) -> str:
    parsed = urlparse(entry_url)
    if parsed.scheme and parsed.netloc:
        return entry_url
    if entry_url.startswith("/"):
        return f"{base_url}{entry_url}"
    return f"{base_url}/{entry_url.lstrip('/')}"


def build_listing_url(entry_url: str, page_num: int) -> str:
    parsed = urlparse(entry_url)
    query = parse_qs(parsed.query)
    if page_num > 1:
        query["page"] = [str(page_num)]
    else:
        query.pop("page", None)
    return urlunparse(parsed._replace(query=urlencode(query, doseq=True)))


def get_checkpoint_paths(brand_slug: str) -> tuple:
    safe_slug = brand_slug or "watchcharts"
    return (
        OUTPUT_DIR / f"{safe_slug}_checkpoint.json",
        OUTPUT_DIR / f"{safe_slug}_listings.json",
        OUTPUT_DIR / f"{safe_slug}_failed.json",
    )


def is_challenge_html(html: str) -> bool:
    if not html:
        return True
    lower = html.lower()
    return any(marker in lower for marker in CHALLENGE_TEXT_MARKERS)


def parse_price(text: Optional[str]) -> Optional[int]:
    if not text:
        return None
    cleaned = text.replace(",", "")
    match = PRICE_RE.search(cleaned)
    if match:
        try:
            return int(match.group(1).replace(",", ""))
        except ValueError:
            return None
    return None


def parse_mm(text: Optional[str]) -> Optional[float]:
    if not text:
        return None
    match = MM_RE.search(text)
    if match:
        return float(match.group(1))
    return None


def parse_water_resistance(text: Optional[str]) -> Optional[int]:
    if not text:
        return None
    match = WATER_RES_RE.search(text)
    return int(match.group(1)) if match else None


def parse_hours(text: Optional[str]) -> Optional[int]:
    if not text:
        return None
    match = HOURS_RE.search(text)
    return int(match.group(1)) if match else None


def parse_bph(text: Optional[str]) -> Optional[int]:
    if not text:
        return None
    match = BPH_RE.search(text)
    return int(match.group(1)) if match else None


def parse_int(text: Optional[str]) -> Optional[int]:
    if not text:
        return None
    match = INT_RE.search(text)
    return int(match.group(1)) if match else None


def safe_int(value: Optional[str], default: Optional[int] = None) -> Optional[int]:
    try:
        return int(value)
    except (TypeError, ValueError):
        return default


def derive_base_url_from_full_url(full_url: str, fallback: str) -> str:
    parsed = urlparse(full_url)
    if parsed.scheme and parsed.netloc:
        return f"{parsed.scheme}://{parsed.netloc}"
    return fallback



def default_detail_payload(full_url: str) -> dict:
    return {
        "full_name": "",
        "reference": extract_reference_from_url(full_url) or "",
        "collection": "",
        "is_current": None,
        "retail_price_usd": None,
        "market_price_usd": None,
        "image_url": None,
        "watchcharts_url": full_url,
        "case": None,
        "movement": None,
        "complications": [],
        "features": [],
        "style": None,
    }


def build_full_url(detail_url: str, base_url: str) -> str:
    if detail_url.startswith("http://") or detail_url.startswith("https://"):
        return detail_url
    if detail_url.startswith("/"):
        return f"{base_url}{detail_url}"
    return f"{base_url}/{detail_url.lstrip('/')}"


async def crawl_listing_page(
    entry_url: str,
    page_num: int,
    fetcher: WatchChartsFetcher,
    retries: int = LISTING_RETRIES,
    retry_delay: float = LISTING_RETRY_DELAY,
) -> List[dict]:
    url = build_listing_url(entry_url, page_num)
    attempts = max(0, retries) + 1
    last_exc: Optional[Exception] = None

    for attempt in range(attempts):
        if attempt == 0:
            print(f"Crawling listing: {url}")
        else:
            print(f"Crawling listing (retry {attempt}/{attempts - 1}): {url}")
        try:
            html = await fetcher.fetch(url)
            return parse_listing_html(html)
        except Exception as exc:
            last_exc = exc
            if is_listing_terminal_error(exc):
                raise
            if attempt < attempts - 1 and retry_delay > 0:
                await asyncio.sleep(retry_delay * (attempt + 1))

    if last_exc:
        raise last_exc
    raise RuntimeError(f"Failed to fetch listing page {page_num}")


async def crawl_all_listing_pages(
    entry_url: str,
    fetcher: WatchChartsFetcher,
    max_pages: int = 100,
    listing_retries: int = LISTING_RETRIES,
    listing_retry_delay: float = LISTING_RETRY_DELAY,
) -> List[dict]:
    all_watches = []
    page_num = 1

    while page_num <= max_pages:
        try:
            watches = await crawl_listing_page(
                entry_url,
                page_num=page_num,
                fetcher=fetcher,
                retries=listing_retries,
                retry_delay=listing_retry_delay,
            )
        except Exception as exc:
            if is_listing_terminal_error(exc):
                print(f"Listing page {page_num} returned terminal error ({exc}); stopping pagination")
                break
            raise

        if not watches:
            print(f"No more watches on page {page_num}, stopping pagination")
            break

        all_watches.extend(watches)
        print(f"Page {page_num}: {len(watches)} watches (total: {len(all_watches)})")

        if len(watches) < LISTING_PAGE_SIZE:
            print(f"Last page reached (fewer than {LISTING_PAGE_SIZE} results)")
            break

        page_num += 1

    return all_watches


async def fetch_detail(
    listing: dict,
    idx: int,
    total: int,
    base_url: str,
    brand_name: str,
    fetcher: WatchChartsFetcher,
    sem: asyncio.Semaphore,
    allow_fallback: bool,
    include_price_history: bool,
    price_history_region: Optional[int],
) -> tuple:
    async with sem:
        try:
            full_url = build_full_url(listing["detail_url"], base_url)
            html = await fetcher.fetch(full_url, allow_fallback=allow_fallback)
            soup = make_soup(html)
            detail = parse_detail_soup(soup, full_url)
            if include_price_history:
                try:
                    history = await fetch_price_history(
                        html=html,
                        soup=soup,
                        full_url=full_url,
                        watch_id=listing["watchcharts_id"],
                        base_url=base_url,
                        fetcher=fetcher,
                        region_id=price_history_region,
                    )
                    if history:
                        detail["market_price_history"] = history
                except Exception as exc:
                    print(f"[{listing['watchcharts_id']}] price history error: {exc}")

            if not detail.get("reference"):
                return "empty", idx, listing, None, "empty_reference"

            model = build_model_from_detail(listing, detail, brand_name)
            return "ok", idx, listing, model, None
        except Exception as exc:
            return "error", idx, listing, None, str(exc)


def save_checkpoint(
    checkpoint_file,
    listings_cache,
    failed_urls_file,
    models: List[WatchChartsModelDTO],
    listings: List[dict],
    processed_count: int,
    failed_urls: List[dict] = None,
) -> None:
    checkpoint = {
        "processed_count": processed_count,
        "models": [m.model_dump(mode="json") for m in models],
        "timestamp": datetime.now().isoformat(),
    }
    with open(checkpoint_file, "w") as f:
        json.dump(checkpoint, f, indent=2, default=str)

    with open(listings_cache, "w") as f:
        json.dump(listings, f, indent=2)

    if failed_urls is not None:
        with open(failed_urls_file, "w") as f:
            json.dump({"failed": failed_urls, "count": len(failed_urls)}, f, indent=2)


def load_checkpoint(checkpoint_file) -> tuple[List[WatchChartsModelDTO], int]:
    if not checkpoint_file.exists():
        return [], 0

    with open(checkpoint_file) as f:
        data = json.load(f)

    models = [WatchChartsModelDTO(**m) for m in data.get("models", [])]
    return models, data.get("processed_count", 0)


def load_listings_cache(listings_cache) -> List[dict]:
    if not listings_cache.exists():
        return []

    with open(listings_cache) as f:
        return json.load(f)


def load_failed_urls(failed_urls_file) -> List[dict]:
    if not failed_urls_file.exists():
        return []

    with open(failed_urls_file) as f:
        data = json.load(f)
        return data.get("failed", [])


def load_existing_models(output_file, checkpoint_file) -> List[WatchChartsModelDTO]:
    if checkpoint_file.exists():
        models, _ = load_checkpoint(checkpoint_file)
        if models:
            return models

    if output_file.exists():
        with open(output_file) as f:
            data = json.load(f)
        return [WatchChartsModelDTO(**m) for m in data.get("models", [])]

    return []


def build_model_from_detail(
    listing: dict,
    detail: dict,
    brand_name: str,
) -> WatchChartsModelDTO:
    detail_is_current = detail.get("is_current")
    if detail_is_current is None:
        detail_is_current = listing.get("is_current", True)

    case_data = detail.get("case")
    case_specs = None
    if case_data:
        case_specs = CaseSpecs(**case_data)
    elif listing.get("case_diameter_mm"):
        case_specs = CaseSpecs(diameter_mm=listing["case_diameter_mm"])

    movement_data = detail.get("movement")
    movement_specs = MovementSpecs(**movement_data) if movement_data else None

    reference = detail.get("reference") or ""
    brand_id = slugify(brand_name)
    aliases = generate_aliases(reference, brand_id) if reference else []

    return WatchChartsModelDTO(
        watchcharts_id=listing["watchcharts_id"],
        reference=reference,
        reference_aliases=aliases,
        full_name=detail.get("full_name") or listing.get("full_name") or "",
        brand=brand_name,
        collection=detail.get("collection") or listing.get("collection"),
        style=detail.get("style"),
        is_current=detail_is_current,
        case=case_specs,
        movement=movement_specs,
        complications=detail.get("complications", []),
        features=detail.get("features", []),
        market_price_usd=detail.get("market_price_usd") or listing.get("market_price_usd"),
        retail_price_usd=detail.get("retail_price_usd") or listing.get("retail_price_usd"),
        watchcharts_url=detail.get("watchcharts_url", ""),
        image_url=detail.get("image_url") or listing.get("image_url"),
        market_price_history=detail.get("market_price_history"),
    )


async def process_batch(
    batch_listings: List[dict],
    batch_start: int,
    total: int,
    base_url: str,
    brand_name: str,
    fetcher: WatchChartsFetcher,
    concurrency: int,
    existing_ids: set,
    allow_fallback: bool,
    include_price_history: bool,
    price_history_region: Optional[int],
) -> tuple[List[WatchChartsModelDTO], List[dict]]:
    sem = asyncio.Semaphore(max(1, concurrency))
    batch_seen = set()
    tasks = []

    for i, listing in enumerate(batch_listings):
        idx = listing.get("_order_idx")
        if idx is None:
            idx = batch_start + i
            listing["_order_idx"] = idx
        watch_id = listing["watchcharts_id"]

        if watch_id in existing_ids:
            print(f"[{idx + 1}/{total}] SKIP (already have {watch_id})")
            continue
        if watch_id in batch_seen:
            print(f"[{idx + 1}/{total}] SKIP (duplicate {watch_id})")
            continue

        batch_seen.add(watch_id)
        tasks.append(
            asyncio.create_task(
                    fetch_detail(
                        listing=listing,
                        idx=idx,
                        total=total,
                        base_url=base_url,
                        brand_name=brand_name,
                        fetcher=fetcher,
                        sem=sem,
                        allow_fallback=allow_fallback,
                        include_price_history=include_price_history,
                        price_history_region=price_history_region,
                    )
                )
        )

    models_by_idx = {}
    failed_urls = []

    for task in asyncio.as_completed(tasks):
        status, idx, listing, model, reason = await task
        if status == "ok":
            models_by_idx[idx] = model
            existing_ids.add(model.watchcharts_id)
            print(f"[{idx + 1}/{total}] OK - {model.reference}")
        elif status == "empty":
            failed_urls.append({
                "url": listing["detail_url"],
                "watchcharts_id": listing["watchcharts_id"],
                "reason": reason,
                "listing": listing,
            })
            print(f"[{idx + 1}/{total}] EMPTY")
        else:
            failed_urls.append({
                "url": listing["detail_url"],
                "watchcharts_id": listing["watchcharts_id"],
                "reason": reason,
                "listing": listing,
            })
            print(f"[{idx + 1}/{total}] ERROR - {reason}")

    batch_models = [models_by_idx[idx] for idx in sorted(models_by_idx)]
    return batch_models, failed_urls


async def retry_failed_rounds(
    failed_urls: List[dict],
    total: int,
    base_url: str,
    brand_name: str,
    fetcher: WatchChartsFetcher,
    concurrency: int,
    existing_ids: set,
    retry_rounds: int,
    retry_delay: float,
    retry_concurrency: int,
    allow_fallback: bool,
    include_price_history: bool,
    price_history_region: Optional[int],
) -> Tuple[List[WatchChartsModelDTO], List[dict]]:
    remaining = failed_urls
    recovered: List[WatchChartsModelDTO] = []

    for round_idx in range(retry_rounds):
        if not remaining:
            break

        round_num = round_idx + 1

        if retry_concurrency > 0:
            round_concurrency = retry_concurrency
        else:
            round_concurrency = max(1, concurrency // (2 ** round_num))

        print(f"Retry round {round_num}/{retry_rounds}: {len(remaining)} models | concurrency {round_concurrency}")
        listings = [entry["listing"] for entry in remaining]
        round_models, round_failed = await process_batch(
            batch_listings=listings,
            batch_start=0,
            total=total,
            base_url=base_url,
            brand_name=brand_name,
            fetcher=fetcher,
            concurrency=round_concurrency,
            existing_ids=existing_ids,
            allow_fallback=allow_fallback,
            include_price_history=include_price_history,
            price_history_region=price_history_region,
        )
        recovered.extend(round_models)

        for entry in round_failed:
            entry["attempt"] = round_num

        remaining = round_failed
        if remaining and retry_delay > 0:
            await asyncio.sleep(retry_delay * round_num)

    return recovered, remaining


async def crawl_watchcharts_async(
    entry_url: str,
    brand_name: str,
    brand_slug: str,
    base_url: str,
    max_models: int = 50,
    batch_size: int = 20,
    resume: bool = False,
    max_pages: int = 100,
    concurrency: int = 24,
    timeout: float = 30.0,
    retries: int = 1,
    backend: str = "curl-impersonate",
    impersonate: str = "chrome120",
    retry_rounds: int = 2,
    retry_delay: float = 2.0,
    retry_concurrency: int = 0,
    include_price_history: bool = False,
    price_history_region: Optional[int] = None,
    price_history_only: bool = False,
    proxy_settings: Optional[ProxySettings] = None,
    session_cookies: Optional[List[dict]] = None,
) -> WatchChartsBrandCatalog:
    OUTPUT_DIR.mkdir(exist_ok=True)

    checkpoint_file, listings_cache, failed_urls_file = get_checkpoint_paths(brand_slug)

    print(f"WatchCharts {brand_name} Crawler (Async HTTP)\n")

    models: List[WatchChartsModelDTO] = []
    failed_urls: List[dict] = []
    start_index = 0
    existing_total_available: Optional[int] = None

    output_file = OUTPUT_DIR / f"{brand_slug}.json"
    if output_file.exists():
        with open(output_file) as f:
            existing_data = json.load(f)
            existing_total_available = existing_data.get("total_available")
            existing_models = [WatchChartsModelDTO(**m) for m in existing_data.get("models", [])]
            if existing_models:
                print(f"Found {len(existing_models)} existing models in {output_file.name} (will skip these)")
                models = existing_models

    if resume:
        checkpoint_models, start_index = load_checkpoint(checkpoint_file)
        failed_urls = load_failed_urls(failed_urls_file)
        if checkpoint_models:
            existing_ids = {m.watchcharts_id for m in models}
            for m in checkpoint_models:
                if m.watchcharts_id not in existing_ids:
                    models.append(m)
        if start_index > 0:
            print(f"Resuming from checkpoint: {start_index} processed, {len(models)} OK, {len(failed_urls)} failed")

    listings: List[dict] = []
    if listings_cache.exists():
        listings = load_listings_cache(listings_cache)
        if listings:
            print(f"Loaded {len(listings)} listings from cache (skipping Phase 1)\n")

    existing_ids = {m.watchcharts_id for m in models}

    fetcher = WatchChartsFetcher(
        concurrency=concurrency,
        timeout=timeout,
        retries=retries,
        backend=backend,
        impersonate=impersonate,
        proxy_settings=proxy_settings,
        session_cookies=session_cookies,
    )

    await fetcher.start(entry_url)
    try:
        if include_price_history and price_history_only:
            if not models:
                raise RuntimeError(
                    f"No existing models found in {output_file}; run the full crawl first."
                )

            missing_history = [m for m in models if not has_price_history(m)]
            if not missing_history:
                print("All models already have price history; nothing to update.")
                return WatchChartsBrandCatalog(
                    brand=brand_name,
                    brand_slug=brand_slug,
                    models=models,
                    total_available=existing_total_available or len(models),
                    entry_url=entry_url,
                )

            total = len(missing_history)
            if batch_size <= 0:
                batch_size = total

            index_map = {m.watchcharts_id: idx for idx, m in enumerate(missing_history)}
            pending = list(missing_history)
            attempts = {m.watchcharts_id: 0 for m in missing_history}
            models_by_id = {m.watchcharts_id: m for m in missing_history}

            print(f"Price history only mode: {total} models missing history\n")

            batch_num = 0
            while pending:
                batch = pending[:batch_size]
                pending = pending[batch_size:]
                batch_num += 1
                total_batches = (total + batch_size - 1) // batch_size

                print(f"\n--- History batch {batch_num}/{total_batches} ({len(batch)} models) ---")
                updated, batch_failed = await process_price_history_batch(
                    batch_models=batch,
                    batch_start=0,
                    total=total,
                    fetcher=fetcher,
                    concurrency=concurrency,
                    base_url=base_url,
                    region_id=price_history_region,
                    index_map=index_map,
                )

                retryable = 0
                for entry in batch_failed:
                    watch_id = entry.get("watchcharts_id")
                    if not watch_id:
                        failed_urls.append(entry)
                        continue
                    attempts[watch_id] += 1
                    if attempts[watch_id] <= retry_rounds:
                        pending.append(models_by_id[watch_id])
                        retryable += 1
                    else:
                        failed_urls.append(entry)

                print(
                    f"History batch updated: {updated} OK, {len(batch_failed) - retryable} failed, {retryable} queued"
                )

                catalog = WatchChartsBrandCatalog(
                    brand=brand_name,
                    brand_slug=brand_slug,
                    models=models,
                    total_available=existing_total_available or len(models),
                    entry_url=entry_url,
                )
                with open(output_file, "w") as f:
                    json.dump(catalog.model_dump(mode="json"), f, indent=2, default=str)
                print(f"Saved progress to {output_file}")

                if pending and retry_delay > 0 and retryable:
                    await asyncio.sleep(retry_delay)

            if failed_urls:
                failed_urls_file = OUTPUT_DIR / f"{brand_slug}_failed_history.json"
                with open(failed_urls_file, "w") as f:
                    json.dump({"failed": failed_urls, "count": len(failed_urls)}, f, indent=2)
                print(f"History failures: {len(failed_urls)} (saved to {failed_urls_file})")

            return WatchChartsBrandCatalog(
                brand=brand_name,
                brand_slug=brand_slug,
                models=models,
                total_available=existing_total_available or len(models),
                entry_url=entry_url,
            )

        if not listings:
            print("Phase 1: Crawling listings...")
            listing_pages_cap = max_pages
            if max_models > 0:
                listing_pages_cap = min(
                    max_pages,
                    max(1, (max_models + LISTING_PAGE_SIZE - 1) // LISTING_PAGE_SIZE),
                )
            listings = await crawl_all_listing_pages(
                entry_url,
                fetcher=fetcher,
                max_pages=listing_pages_cap,
            )
            print(f"Found {len(listings)} watches total\n")
            save_checkpoint(checkpoint_file, listings_cache, failed_urls_file, models, listings, start_index)

        to_process = listings[start_index:max_models]
        total = min(len(listings), max_models)

        if batch_size <= 0:
            batch_size = len(to_process) or 1

        print(f"Phase 2: Fetching details ({start_index} → {total})...")
        print(f"Concurrency: {concurrency} | Batch size: {batch_size} | Retry rounds: {retry_rounds}\n")

        for batch_idx in range(0, len(to_process), batch_size):
            batch = to_process[batch_idx:batch_idx + batch_size]
            batch_start = start_index + batch_idx
            batch_num = batch_idx // batch_size + 1
            total_batches = (len(to_process) + batch_size - 1) // batch_size

            print(f"\n--- Batch {batch_num}/{total_batches} ({len(batch)} models) ---")
            batch_models, batch_failed = await process_batch(
                batch_listings=batch,
                batch_start=batch_start,
                total=total,
                base_url=base_url,
                brand_name=brand_name,
                fetcher=fetcher,
                concurrency=concurrency,
                existing_ids=existing_ids,
                allow_fallback=True,
                include_price_history=include_price_history,
                price_history_region=price_history_region,
            )

            if retry_rounds > 0 and batch_failed:
                retry_models, batch_failed = await retry_failed_rounds(
                    failed_urls=batch_failed,
                    total=total,
                    base_url=base_url,
                    brand_name=brand_name,
                    fetcher=fetcher,
                    concurrency=concurrency,
                    existing_ids=existing_ids,
                    retry_rounds=retry_rounds,
                    retry_delay=retry_delay,
                    retry_concurrency=retry_concurrency,
                    allow_fallback=True,
                    include_price_history=include_price_history,
                    price_history_region=price_history_region,
                )
                if retry_models:
                    batch_models.extend(retry_models)
            models.extend(batch_models)
            failed_urls.extend(batch_failed)

            save_checkpoint(
                checkpoint_file,
                listings_cache,
                failed_urls_file,
                models,
                listings,
                batch_start + len(batch),
                failed_urls,
            )
            print(f"Checkpoint saved: {len(models)} OK, {len(failed_urls)} failed")

    finally:
        await fetcher.close()

    catalog = WatchChartsBrandCatalog(
        brand=brand_name,
        brand_slug=brand_slug,
        models=models,
        total_available=len(listings),
        entry_url=entry_url,
    )

    with open(output_file, "w") as f:
        json.dump(catalog.model_dump(mode="json"), f, indent=2, default=str)

    if checkpoint_file.exists():
        checkpoint_file.unlink()
    if listings_cache.exists():
        listings_cache.unlink()

    print(f"\nDone! Saved {len(models)} models to {output_file}")
    if failed_urls:
        print(f"Failed: {len(failed_urls)} (saved to {failed_urls_file})")
        print("Run with --retry-failed to retry")

    return catalog


async def retry_failed_async(
    entry_url: str,
    brand_name: str,
    brand_slug: str,
    base_url: str,
    batch_size: int = 20,
    concurrency: int = 24,
    timeout: float = 30.0,
    retries: int = 1,
    backend: str = "curl-impersonate",
    impersonate: str = "chrome120",
    retry_rounds: int = 2,
    retry_delay: float = 2.0,
    retry_concurrency: int = 0,
    include_price_history: bool = False,
    price_history_region: Optional[int] = None,
    price_history_only: bool = False,
    proxy_settings: Optional[ProxySettings] = None,
    session_cookies: Optional[List[dict]] = None,
) -> None:
    OUTPUT_DIR.mkdir(exist_ok=True)
    checkpoint_file, listings_cache, failed_urls_file = get_checkpoint_paths(brand_slug)

    failed = load_failed_urls(failed_urls_file)
    if not failed:
        print("No failed URLs to retry")
        return

    print(f"Retrying {len(failed)} failed URLs\n")

    output_file = OUTPUT_DIR / f"{brand_slug}.json"
    models = load_existing_models(output_file, checkpoint_file)
    existing_ids = {m.watchcharts_id for m in models}

    listings_to_retry = [f["listing"] for f in failed if f["watchcharts_id"] not in existing_ids]
    print(f"After filtering already-successful: {len(listings_to_retry)} to retry\n")

    if not listings_to_retry:
        print("All previously failed URLs are now successful")
        return

    new_models: List[WatchChartsModelDTO] = []
    still_failed: List[dict] = []

    fetcher = WatchChartsFetcher(
        concurrency=concurrency,
        timeout=timeout,
        retries=retries,
        backend=backend,
        impersonate=impersonate,
        proxy_settings=proxy_settings,
        session_cookies=session_cookies,
    )

    await fetcher.start(entry_url)
    try:
        if batch_size <= 0:
            batch_size = len(listings_to_retry) or 1

        total = len(listings_to_retry)
        for batch_idx in range(0, len(listings_to_retry), batch_size):
            batch = listings_to_retry[batch_idx:batch_idx + batch_size]
            batch_start = batch_idx
            batch_num = batch_idx // batch_size + 1
            total_batches = (len(listings_to_retry) + batch_size - 1) // batch_size

            print(f"\n--- Retry batch {batch_num}/{total_batches} ({len(batch)} models) ---")
            batch_models, batch_failed = await process_batch(
                batch_listings=batch,
                batch_start=batch_start,
                total=total,
                base_url=base_url,
                brand_name=brand_name,
                fetcher=fetcher,
                concurrency=concurrency,
                existing_ids=existing_ids,
                allow_fallback=True,
                include_price_history=include_price_history,
                price_history_region=price_history_region,
            )
            if retry_rounds > 0 and batch_failed:
                retry_models, batch_failed = await retry_failed_rounds(
                    failed_urls=batch_failed,
                    total=total,
                    base_url=base_url,
                    brand_name=brand_name,
                    fetcher=fetcher,
                    concurrency=concurrency,
                    existing_ids=existing_ids,
                    retry_rounds=retry_rounds,
                    retry_delay=retry_delay,
                    retry_concurrency=retry_concurrency,
                    allow_fallback=True,
                    include_price_history=include_price_history,
                    price_history_region=price_history_region,
                )
                if retry_models:
                    batch_models.extend(retry_models)
            new_models.extend(batch_models)
            still_failed.extend(batch_failed)

    finally:
        await fetcher.close()

    models.extend(new_models)

    with open(failed_urls_file, "w") as f:
        json.dump({"failed": still_failed, "count": len(still_failed)}, f, indent=2)

    total_available = None
    if output_file.exists():
        with open(output_file) as f:
            existing_data = json.load(f)
            total_available = existing_data.get("total_available")

    catalog = WatchChartsBrandCatalog(
        brand=brand_name,
        brand_slug=brand_slug,
        models=models,
        total_available=total_available or len(models),
        entry_url=entry_url,
    )
    with open(output_file, "w") as f:
        json.dump(catalog.model_dump(mode="json"), f, indent=2, default=str)

    print(f"\nRetry complete: {len(new_models)} recovered, {len(still_failed)} still failed")
    print(f"Total models: {len(models)}")


def crawl_watchcharts(
    entry_url: str,
    brand_name: str,
    brand_slug: str,
    base_url: str,
    max_models: int = 50,
    batch_size: int = 20,
    resume: bool = False,
    max_pages: int = 100,
    concurrency: int = 24,
    timeout: float = 30.0,
    retries: int = 1,
    backend: str = "curl-impersonate",
    impersonate: str = "chrome120",
    retry_rounds: int = 2,
    retry_delay: float = 2.0,
    retry_concurrency: int = 0,
    include_price_history: bool = False,
    price_history_region: Optional[int] = None,
    price_history_only: bool = False,
    proxy_settings: Optional[ProxySettings] = None,
    session_cookies: Optional[List[dict]] = None,
) -> WatchChartsBrandCatalog:
    return asyncio.run(
        crawl_watchcharts_async(
            entry_url=entry_url,
            brand_name=brand_name,
            brand_slug=brand_slug,
            base_url=base_url,
            max_models=max_models,
            batch_size=batch_size,
            resume=resume,
            max_pages=max_pages,
            concurrency=concurrency,
            timeout=timeout,
            retries=retries,
            backend=backend,
            impersonate=impersonate,
            retry_rounds=retry_rounds,
            retry_delay=retry_delay,
            retry_concurrency=retry_concurrency,
            include_price_history=include_price_history,
            price_history_region=price_history_region,
            price_history_only=price_history_only,
            proxy_settings=proxy_settings,
            session_cookies=session_cookies,
        )
    )


def retry_failed(
    entry_url: str,
    brand_name: str,
    brand_slug: str,
    base_url: str,
    batch_size: int = 20,
    concurrency: int = 24,
    timeout: float = 30.0,
    retries: int = 1,
    backend: str = "curl-impersonate",
    impersonate: str = "chrome120",
    retry_rounds: int = 2,
    retry_delay: float = 2.0,
    retry_concurrency: int = 0,
    include_price_history: bool = False,
    price_history_region: Optional[int] = None,
    price_history_only: bool = False,
    proxy_settings: Optional[ProxySettings] = None,
    session_cookies: Optional[List[dict]] = None,
) -> None:
    asyncio.run(
        retry_failed_async(
            entry_url=entry_url,
            brand_name=brand_name,
            brand_slug=brand_slug,
            base_url=base_url,
            batch_size=batch_size,
            concurrency=concurrency,
            timeout=timeout,
            retries=retries,
            backend=backend,
            impersonate=impersonate,
            retry_rounds=retry_rounds,
            retry_delay=retry_delay,
            retry_concurrency=retry_concurrency,
            include_price_history=include_price_history,
            price_history_region=price_history_region,
            price_history_only=price_history_only,
            proxy_settings=proxy_settings,
            session_cookies=session_cookies,
        )
    )


def main() -> None:
    parser = argparse.ArgumentParser(description="WatchCharts Brand Crawler (Async HTTP)")
    parser.add_argument("--entry-url", type=str, help="Entry listing URL (e.g., https://watchcharts.com/watches?filters=...)")
    parser.add_argument("--filters", type=str, help="WatchCharts filters query param (used when entry URL is omitted)")
    parser.add_argument("--brand", type=str, help="Brand display name (e.g., Rolex)")
    parser.add_argument("--brand-slug", type=str, help="Slug used for output filenames (e.g., rolex)")
    parser.add_argument("--base-url", type=str, help="Override WatchCharts base URL (default: https://watchcharts.com)")
    parser.add_argument("--models", type=int, default=10, help="Number of models to crawl")
    parser.add_argument("--max-pages", type=int, default=100, help="Maximum listing pages to crawl")
    parser.add_argument("--batch", type=int, default=20, help="Batch size for checkpoints")
    parser.add_argument("--resume", action="store_true", help="Resume from last checkpoint")
    parser.add_argument("--retry-failed", action="store_true", help="Retry only failed URLs")
    parser.add_argument("--headless", action="store_true", help="Kept for CLI compatibility")
    parser.add_argument("--concurrency", type=int, default=6, help="Max concurrent detail fetches")
    parser.add_argument("--timeout", type=float, default=30.0, help="Request timeout in seconds")
    parser.add_argument("--retries", type=int, default=1, help="Retry count per request")
    parser.add_argument("--backend", type=str, default="curl-impersonate", help="HTTP backend: curl-impersonate (Docker), curl (curl_cffi), httpx")
    parser.add_argument("--impersonate", type=str, default="chrome120", help="curl_cffi impersonation profile(s), comma-separated")
    parser.add_argument("--retry-rounds", type=int, default=2, help="Recursive retry rounds per batch")
    parser.add_argument("--retry-delay", type=float, default=2.0, help="Base delay between retry rounds in seconds")
    parser.add_argument("--retry-concurrency", type=int, default=0, help="Override concurrency for retry rounds (0 = auto)")
    parser.add_argument("--env-file", type=str, help="Load env vars from a file (default: .env or WATCHCHARTS_ENV_FILE)")
    parser.add_argument("--cookies-file", type=str, help="Path to Netscape cookies.txt file for session authentication")
    parser.add_argument("--proxy", type=str, help="Proxy URL for HTTP requests (e.g. http://user:pass@host:port)")
    args = parser.parse_args()

    if load_dotenv:
        env_file = args.env_file or os.getenv("WATCHCHARTS_ENV_FILE")
        if env_file:
            load_dotenv(env_file, override=True)
        else:
            load_dotenv()

    entry_url = args.entry_url
    base_url = get_base_url(entry_url or DEFAULT_WATCHCHARTS_BASE, args.base_url)

    if not entry_url:
        if args.filters:
            entry_url = f"{base_url}/watches?filters={args.filters}"
        else:
            candidate_slug = args.brand_slug or (slugify(args.brand) if args.brand else None)
            if candidate_slug and candidate_slug in BRAND_FILTERS:
                entry_url = f"{base_url}/watches?filters={BRAND_FILTERS[candidate_slug]}"

    if not entry_url and not args.retry_failed:
        parser.error("Provide --entry-url or --filters (or a brand with known filters).")
    if not entry_url:
        entry_url = base_url
    entry_url = normalize_entry_url(entry_url, base_url)

    brand_slug = derive_brand_slug(args.brand_slug, args.brand, entry_url)
    brand_name = derive_brand_name(args.brand, brand_slug)

    cookies_file = args.cookies_file or os.getenv("WATCHCHARTS_COOKIES_FILE")
    session_cookies = []
    if cookies_file:
        if os.path.isfile(cookies_file):
            session_cookies = parse_netscape_cookies(cookies_file)
            print(f"Loaded {len(session_cookies)} cookies from {cookies_file}")
        else:
            print(f"Warning: cookies file not found: {cookies_file}")

    backend_choice = (args.backend or "auto").lower()
    proxy_input = args.proxy or os.getenv("WATCHCHARTS_PROXY")
    proxy_settings = None
    if proxy_input:
        try:
            proxy_settings = parse_proxy_settings(proxy_input, None)
        except ValueError as exc:
            parser.error(str(exc))
    if proxy_settings:
        print(f"Using proxy: {proxy_settings.server}")

    if args.retry_failed:
        retry_failed(
            entry_url=entry_url,
            brand_name=brand_name,
            brand_slug=brand_slug,
            base_url=base_url,
            batch_size=args.batch,
            concurrency=args.concurrency,
            timeout=args.timeout,
            retries=args.retries,
            backend=args.backend,
            impersonate=args.impersonate,
            retry_rounds=args.retry_rounds,
            retry_delay=args.retry_delay,
            retry_concurrency=args.retry_concurrency,
            proxy_settings=proxy_settings,
            session_cookies=session_cookies,
        )
    else:
        crawl_watchcharts(
            entry_url=entry_url,
            brand_name=brand_name,
            brand_slug=brand_slug,
            base_url=base_url,
            max_models=args.models,
            batch_size=args.batch,
            resume=args.resume,
            max_pages=args.max_pages,
            concurrency=args.concurrency,
            timeout=args.timeout,
            retries=args.retries,
            backend=args.backend,
            impersonate=args.impersonate,
            retry_rounds=args.retry_rounds,
            retry_delay=args.retry_delay,
            retry_concurrency=args.retry_concurrency,
            proxy_settings=proxy_settings,
            session_cookies=session_cookies,
        )


if __name__ == "__main__":
    main()
