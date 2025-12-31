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

from watchcollection_crawler.core.anticaptcha import AntiCaptchaClient, AntiCaptchaProxy, detect_turnstile
from watchcollection_crawler.core.curl_impersonate import AsyncCurlImpersonateClient
from watchcollection_crawler.core.flaresolverr import FlareSolverrClient
from watchcollection_crawler.core.paths import WATCHCHARTS_OUTPUT_DIR
from watchcollection_crawler.core.playwright_stealth import PlaywrightStealthClient
from watchcollection_crawler.schemas_watchcharts import (
    WatchChartsModelDTO,
    WatchChartsBrandCatalog,
    CaseSpecs,
    MovementSpecs,
    MarketPriceHistory,
    MarketPriceHistoryPoint,
)
from watchcollection_crawler.utils.strings import slugify
from watchcollection_crawler.reference_matcher import generate_aliases

sys.stdout.reconfigure(line_buffering=True)
sys.stderr.reconfigure(line_buffering=True)

DEFAULT_WATCHCHARTS_BASE = "https://watchcharts.com"
DEFAULT_BRIGHTDATA_ENDPOINT = "https://api.brightdata.com/request"
DEFAULT_BRIGHTDATA_FORMAT = "raw"
CHALLENGE_TEXT_MARKERS = ("just a moment", "attention required", "checking your browser")
HTML_PARSER = "lxml"
LISTING_PAGE_SIZE = 24
CHALLENGE_THRESHOLD_DEFAULT = 0.6
CHALLENGE_MIN_COUNT = 5
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
CSRF_TOKEN_RE = re.compile(r'id="csrfToken"[^>]*data-token=["\']([^"\']+)["\']')
CSRF_WINDOW_RE = re.compile(r'window\.csrf_token\s*=\s*["\']([^"\']+)["\']')
SYS_CURRENCY_RE = re.compile(r'window\.sys_currency\s*=\s*["\']([^"\']+)["\']')

DEFAULT_PRICE_HISTORY_REGION = 0
DEFAULT_PRICE_HISTORY_CONDITION_ID = 0
DEFAULT_PRICE_HISTORY_ACCESSORIES_ID = 1
DEFAULT_PRICE_HISTORY_SEGMENT_ID = 0


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


def should_rotate_credentials(failed_urls: List[dict], threshold: float) -> bool:
    if not failed_urls or len(failed_urls) < CHALLENGE_MIN_COUNT:
        return False
    challenge_count = sum(1 for f in failed_urls if classify_failure(f.get("reason", "")) == "challenge")
    if challenge_count == 0:
        return False
    return (challenge_count / len(failed_urls)) >= threshold


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
        use_anticaptcha: bool,
        ac_concurrency: int,
        ac_timeout: float,
        backend: str,
        impersonate: str,
        pw_headless: bool = True,
        anti_captcha_key: Optional[str] = None,
        proxy_settings: Optional[ProxySettings] = None,
        brightdata_api_key: Optional[str] = None,
        brightdata_zone: Optional[str] = None,
        brightdata_endpoint: str = DEFAULT_BRIGHTDATA_ENDPOINT,
        brightdata_format: str = DEFAULT_BRIGHTDATA_FORMAT,
        session_cookies: Optional[List[dict]] = None,
    ) -> None:
        self.retries = max(0, retries)
        self._ac: Optional[AntiCaptchaClient] = None
        self._ac_enabled = use_anticaptcha
        self._ac_timeout = max(30.0, ac_timeout)
        self._ac_sem = asyncio.Semaphore(max(1, ac_concurrency))
        self._refresh_lock = asyncio.Lock()
        self._last_refresh = 0.0
        self._refresh_min_interval = 60.0
        self._ac_failures = 0
        self._ac_disable_until = 0.0
        self._bootstrap_url: Optional[str] = None
        self._stale_clients: List[Any] = []

        self._pw: Optional[PlaywrightStealthClient] = None
        self._pw_headless = pw_headless
        self._pw_timeout = max(30.0, ac_timeout)
        self._pw_sem = asyncio.Semaphore(1)
        self._pw_failures = 0
        self._pw_disable_until = 0.0
        self._anti_captcha_key = anti_captcha_key
        self._anti_captcha_timeout = ac_timeout
        self._proxy_settings = proxy_settings
        self._proxy_url = proxy_settings.url if proxy_settings else None
        self._pw_proxy = None
        self._ac_proxy = None
        self._brightdata_api_key = brightdata_api_key
        self._brightdata_zone = brightdata_zone
        self._brightdata_endpoint = brightdata_endpoint or DEFAULT_BRIGHTDATA_ENDPOINT
        self._brightdata_format = brightdata_format or DEFAULT_BRIGHTDATA_FORMAT
        self._brightdata_client: Optional[httpx.AsyncClient] = None
        self._fs_enabled = bool(os.getenv("USE_FLARESOLVERR")) or bool(os.getenv("FLARESOLVERR_URL"))
        self._fs_client: Optional[FlareSolverrClient] = FlareSolverrClient() if self._fs_enabled else None
        self._fs_sem = asyncio.Semaphore(1)
        self._fs_lock = asyncio.Lock()
        self._fs_failures = 0
        self._fs_disable_until = 0.0

        if proxy_settings:
            self._pw_proxy = {"server": proxy_settings.server}
            if proxy_settings.username:
                self._pw_proxy["username"] = proxy_settings.username
            if proxy_settings.password:
                self._pw_proxy["password"] = proxy_settings.password
            self._ac_proxy = AntiCaptchaProxy(
                proxy_type=proxy_settings.proxy_type,
                address=urlparse(proxy_settings.server).hostname or "",
                port=urlparse(proxy_settings.server).port or 0,
                login=proxy_settings.username,
                password=proxy_settings.password,
            )

        if use_anticaptcha and anti_captcha_key:
            self._ac = AntiCaptchaClient(
                api_key=anti_captcha_key,
                timeout=int(ac_timeout),
                proxy=self._ac_proxy,
            )

        backend_choice = (backend or "auto").lower()
        if backend_choice == "auto":
            backend_choice = "curl" if CurlAsyncSession else "httpx"
        if backend_choice in {"brightdata", "brightdata-api", "brightdata-webaccess"}:
            backend_choice = "brightdata"
        if backend_choice == "curl" and not CurlAsyncSession:
            raise RuntimeError("curl_cffi is not installed; install it or use --backend httpx or --backend curl-impersonate")
        if backend_choice not in {"curl", "httpx", "brightdata", "curl-impersonate"}:
            raise RuntimeError(f"Unknown backend '{backend_choice}'")
        if backend_choice == "brightdata" and (not brightdata_api_key or not brightdata_zone):
            raise RuntimeError("Bright Data backend requires --brightdata-api-key and --brightdata-zone")
        if backend_choice == "brightdata":
            self._ac_enabled = False
            self._ac = None
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

        if self._backend == "brightdata":
            self._brightdata_client = httpx.AsyncClient(
                headers={
                    "Authorization": f"Bearer {self._brightdata_api_key}",
                    "Content-Type": "application/json",
                },
                timeout=timeout_cfg,
                limits=limits,
            )
        elif self._backend == "curl":
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

        if self._backend == "brightdata":
            print("Using Bright Data Web Unlocker API")
        elif self._backend == "curl-impersonate":
            print("Using curl-impersonate (Docker)")

        try:
            status_code, text = await self._get(bootstrap_url)
            if status_code < 400 and not is_challenge_html(text):
                print("Initial request succeeded without challenge")
                return
        except Exception as exc:
            print(f"Bootstrap request failed ({exc})")

        if self._backend == "brightdata":
            print("Bright Data request failed; check API key, zone, and credits.")
            return
        print("Note: Challenges will be handled via Playwright fallback")

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
        if self._brightdata_client:
            await self._brightdata_client.aclose()
        if self._pw:
            await self._pw.close()
            self._pw = None
        if self._fs_client:
            await asyncio.to_thread(self._fs_client.destroy_session)

    def _ac_disabled(self) -> bool:
        return self._ac_disable_until and time.monotonic() < self._ac_disable_until

    def _note_ac_failure(self, exc: Exception) -> None:
        self._ac_failures += 1
        message = str(exc)
        if "ERROR_IP_BLOCKED" in message:
            self._ac_disable_until = time.monotonic() + 1800
            self._ac_failures = 0
            print("AntiCaptcha disabled for 30m after ERROR_IP_BLOCKED. Configure a proxy to continue.")
            return
        if self._ac_failures >= 3 and not self._ac_disabled():
            self._ac_disable_until = time.monotonic() + 300
            self._ac_failures = 0
            print(f"AntiCaptcha disabled for 5m after repeated failures ({exc}).")

    def _pw_disabled(self) -> bool:
        return self._pw_disable_until and time.monotonic() < self._pw_disable_until

    def _note_pw_failure(self, exc: Exception) -> None:
        self._pw_failures += 1
        if self._pw_failures >= 10 and not self._pw_disabled():
            self._pw_disable_until = time.monotonic() + 60
            self._pw_failures = 0
            print(f"Playwright paused for 1m after repeated failures ({exc}).")

    def _fs_disabled(self) -> bool:
        return self._fs_disable_until and time.monotonic() < self._fs_disable_until

    def _note_fs_failure(self, exc: Exception) -> None:
        self._fs_failures += 1
        if self._fs_failures >= 3 and not self._fs_disabled():
            self._fs_disable_until = time.monotonic() + 120
            self._fs_failures = 0
            print(f"FlareSolverr paused for 2m after repeated failures ({exc}).")

    def _flaresolverr_available(self) -> bool:
        return self._fs_client is not None and not self._fs_disabled()

    def _apply_solution(self, solution: dict) -> None:
        user_agent = solution.get("userAgent")
        if user_agent:
            if self._httpx:
                self._httpx.headers["User-Agent"] = user_agent
            if self._curl:
                self._curl.headers["User-Agent"] = user_agent

        cf_cookie = solution.get("cf_clearance")
        if cf_cookie:
            print(f"Applying cf_clearance: domain={cf_cookie.get('domain')}, value={cf_cookie.get('value', '')[:20]}...")

        for cookie in solution.get("cookies", []):
            name = cookie.get("name")
            if not name:
                continue
            if self._httpx:
                self._httpx.cookies.set(
                    name,
                    cookie.get("value", ""),
                    domain=cookie.get("domain"),
                    path=cookie.get("path") or "/",
                )
            if self._curl:
                self._curl.cookies.set(
                    name,
                    cookie.get("value", ""),
                    domain=cookie.get("domain"),
                    path=cookie.get("path") or "/",
                )

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

    async def _brightdata_request(
        self,
        url: str,
        headers: Optional[dict],
        session_id: Optional[str] = None,
    ) -> tuple[int, str]:
        if not self._brightdata_client:
            raise RuntimeError("Bright Data client not initialized")
        merged_headers = DEFAULT_HEADERS.copy()
        if headers:
            merged_headers.update(headers)
        cookie_header = self.get_cookie_header()
        if cookie_header:
            merged_headers["Cookie"] = cookie_header
        payload = {
            "zone": self._brightdata_zone,
            "url": url,
            "format": self._brightdata_format,
            "headers": merged_headers,
            "country": "us",
        }
        resp = await self._brightdata_client.post(self._brightdata_endpoint, json=payload)
        brd_error = resp.headers.get("x-brd-error") or resp.headers.get("x-luminati-error")
        if brd_error:
            raise RuntimeError(f"Bright Data error: {brd_error}")
        content_type = resp.headers.get("content-type", "").lower()
        if "application/json" in content_type:
            try:
                data = resp.json()
            except ValueError:
                data = None
            if isinstance(data, dict):
                for key in ("response", "body", "data"):
                    if isinstance(data.get(key), str):
                        return resp.status_code, data[key]
                error = data.get("error") or data.get("message")
                if error:
                    raise RuntimeError(f"Bright Data API error: {error}")
        return resp.status_code, resp.text

    async def _get(self, url: str, session_id: Optional[str] = None) -> tuple[int, str]:
        if self._backend == "brightdata":
            return await self._brightdata_request(url, None, session_id=session_id)
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
        if self._backend == "brightdata":
            return await self._brightdata_request(url, headers, session_id=session_id)
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

    async def _solve_challenge_with_playwright(self, url: str) -> Optional[dict]:
        if not self._ac or self._ac_disabled():
            return None

        async with self._pw_sem:
            async with self._ac_sem:
                try:
                    if not self._pw:
                        self._pw = PlaywrightStealthClient(
                            headless=self._pw_headless,
                            timeout=self._pw_timeout,
                            anti_captcha_key=self._anti_captcha_key,
                            anti_captcha_timeout=self._anti_captcha_timeout,
                            anti_captcha_proxy=self._ac_proxy,
                            proxy=self._pw_proxy,
                        )
                        await self._pw.start()

                    print(f"Navigating to {url} with Playwright...")
                    html = await self._pw.get(url, wait_for_cf=True, cf_timeout=self._anti_captcha_timeout)

                    if is_challenge_html(html):
                        print("Challenge still present after wait_for_cf, challenge may have failed")
                        return None

                    cookies = await self._pw.cookies()
                    cf_clearance = None

                    for cookie in cookies:
                        if cookie.get("name") == "cf_clearance":
                            cf_clearance = cookie
                            break

                    if cf_clearance:
                        self._ac_failures = 0
                        pw_ua = await self._pw.page.evaluate("navigator.userAgent")
                        print(f"Got cf_clearance cookie: {cf_clearance.get('value', '')[:20]}...")
                        return {
                            "cookies": cookies,
                            "cf_clearance": cf_clearance,
                            "userAgent": pw_ua,
                        }

                    print("No cf_clearance cookie found after challenge")
                    return None
                except Exception as exc:
                    self._note_ac_failure(exc)
                    print(f"Challenge solve failed: {exc}")
                    return None

    async def _refresh_cookies(self) -> bool:
        if self._backend == "brightdata":
            return False
        if not self._ac_enabled or not self._bootstrap_url or self._ac_disabled():
            return False

        async with self._refresh_lock:
            now = time.monotonic()
            if now - self._last_refresh < self._refresh_min_interval:
                return True

            print("Refreshing cf_clearance cookie...")
            solution = await self._solve_challenge_with_playwright(self._bootstrap_url)
            if solution:
                self._apply_solution(solution)
                self._last_refresh = now
                print("Cookie refreshed successfully")
                return True
            print("Cookie refresh failed")
            return False

    async def rotate_credentials(self, force_new_session: bool = True) -> bool:
        if self._backend == "brightdata":
            return False
        if not self._ac_enabled or not self._bootstrap_url:
            return False
        async with self._refresh_lock:
            if force_new_session and self._pw:
                await self._pw.close()
                self._pw = None

            if self._backend == "curl":
                next_impersonate = self._next_impersonate()
                if next_impersonate and next_impersonate != self._impersonate:
                    self._swap_curl_session(next_impersonate)

            solution = await self._solve_challenge_with_playwright(self._bootstrap_url)
            if solution:
                self._apply_solution(solution)
                self._last_refresh = time.monotonic()
                self._ac_failures = 0
                return True
            return False

    async def rotate_impersonate(self) -> bool:
        if self._backend == "brightdata":
            return False
        if self._backend != "curl":
            return False
        async with self._refresh_lock:
            next_impersonate = self._next_impersonate()
            if not next_impersonate or next_impersonate == self._impersonate:
                return False
            self._swap_curl_session(next_impersonate)
            return True

    async def _solve_and_fetch(self, url: str) -> Optional[str]:
        if not self._ac or self._ac_disabled():
            return None
        try:
            solution = await self._solve_challenge_with_playwright(url)
            if solution:
                self._apply_solution(solution)
                if self._pw and self._pw.page:
                    html = await self._pw.page.content()
                    if html and not is_challenge_html(html):
                        return html

            status_code, text = await self._get(url)
            if status_code < 400 and not is_challenge_html(text):
                return text
            return None
        except Exception as exc:
            self._note_ac_failure(exc)
            return None

    async def solve_challenge(self, url: str) -> Optional[str]:
        if not self._ac or self._ac_disabled():
            return None
        solution = await self._solve_challenge_with_playwright(url)
        if solution:
            self._apply_solution(solution)
            if self._pw and self._pw.page:
                html = await self._pw.page.content()
                self._ac_failures = 0
                return html
        return None

    async def _fetch_via_playwright(self, url: str) -> Optional[str]:
        if self._pw_disabled():
            return None
        async with self._pw_sem:
            try:
                if not self._pw:
                    self._pw = PlaywrightStealthClient(
                        headless=self._pw_headless,
                        timeout=self._pw_timeout,
                        anti_captcha_key=self._anti_captcha_key,
                        anti_captcha_timeout=self._anti_captcha_timeout,
                        anti_captcha_proxy=self._ac_proxy,
                        proxy=self._pw_proxy,
                    )
                    await self._pw.start()
                html = await self._pw.get(url, wait_for_cf=True, cf_timeout=self._anti_captcha_timeout)
                self._pw_failures = 0
                return html
            except Exception as exc:
                self._note_pw_failure(exc)
                return None

    async def _fetch_via_playwright_text(self, url: str) -> Optional[str]:
        if self._pw_disabled():
            return None
        async with self._pw_sem:
            try:
                if not self._pw:
                    self._pw = PlaywrightStealthClient(
                        headless=self._pw_headless,
                        timeout=self._pw_timeout,
                        anti_captcha_key=self._anti_captcha_key,
                        anti_captcha_timeout=self._anti_captcha_timeout,
                        anti_captcha_proxy=self._ac_proxy,
                        proxy=self._pw_proxy,
                    )
                    await self._pw.start()
                text = await self._pw.get_text(url, wait_for_cf=True, cf_timeout=self._anti_captcha_timeout)
                self._pw_failures = 0
                return text
            except Exception as exc:
                self._note_pw_failure(exc)
                return None

    async def _fetch_json_via_playwright(self, url: str, headers: Optional[dict] = None) -> Optional[str]:
        if self._pw_disabled():
            return None
        if not self._pw or not self._pw._page:
            return None
        async with self._pw_sem:
            try:
                header_obj = json.dumps(headers) if headers else "{}"
                result = await self._pw._page.evaluate(
                    f"""
                    async () => {{
                        const resp = await fetch("{url}", {{
                            method: "GET",
                            headers: {header_obj},
                            credentials: "same-origin"
                        }});
                        return await resp.text();
                    }}
                    """
                )
                self._pw_failures = 0
                return result
            except Exception as exc:
                self._note_pw_failure(exc)
                return None

    async def _ensure_flaresolverr_session(self) -> bool:
        if not self._flaresolverr_available():
            return False
        async with self._fs_lock:
            if self._fs_client and self._fs_client.session_id:
                return True
            try:
                await asyncio.to_thread(self._fs_client.create_session)
                return True
            except Exception as exc:
                self._note_fs_failure(exc)
                return False

    async def _fetch_via_flaresolverr(
        self,
        url: str,
        headers: Optional[dict] = None,
        max_timeout: int = 60000,
    ) -> Optional[str]:
        if not self._flaresolverr_available():
            return None
        async with self._fs_sem:
            ready = await self._ensure_flaresolverr_session()
            if not ready or not self._fs_client:
                return None
            try:
                text = await asyncio.to_thread(self._fs_client.get, url, max_timeout, headers)
                self._fs_failures = 0
                return text
            except Exception as exc:
                self._note_fs_failure(exc)
                return None

    async def fetch(
        self,
        url: str,
        allow_fallback: bool = True,
        session_id: Optional[str] = None,
    ) -> str:
        last_error: Optional[Exception] = None
        challenge_count = 0
        if self._backend == "brightdata":
            allow_fallback = False

        for attempt in range(self.retries + 1):
            try:
                status_code, text = await self._get(url, session_id=session_id)
                if status_code < 400 and not is_challenge_html(text):
                    return text
                if is_challenge_html(text):
                    last_error = RuntimeError("Cloudflare challenge")
                    challenge_count += 1
                else:
                    last_error = RuntimeError(f"HTTP {status_code}")
            except Exception as exc:
                last_error = exc

            if attempt < self.retries:
                await asyncio.sleep(0.5 * (2**attempt))

        if allow_fallback and challenge_count > 0:
            html = await self._fetch_via_playwright(url)
            if html and not is_challenge_html(html):
                return html

        raise RuntimeError(f"Failed after {self.retries + 1} attempts: {last_error}")

    async def fetch_with_headers(
        self,
        url: str,
        headers: Optional[dict] = None,
        allow_fallback: bool = True,
        session_id: Optional[str] = None,
    ) -> str:
        last_error: Optional[Exception] = None
        if self._backend == "brightdata":
            allow_fallback = False
        for attempt in range(self.retries + 1):
            needs_refresh = False
            try:
                status_code, text = await self._get_with_headers(url, headers, session_id=session_id)
                if status_code < 400 and not is_challenge_html(text):
                    return text
                if is_challenge_html(text):
                    last_error = RuntimeError("Cloudflare challenge")
                    needs_refresh = True
                else:
                    last_error = RuntimeError(f"HTTP {status_code}")
                    if status_code in {403, 429, 503}:
                        needs_refresh = True
            except Exception as exc:
                last_error = exc
                needs_refresh = True

            if allow_fallback and self._ac_enabled and needs_refresh:
                refreshed = await self._refresh_cookies()
                if refreshed:
                    try:
                        status_code, text = await self._get_with_headers(url, headers)
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


def has_price_history(model: WatchChartsModelDTO) -> bool:
    history = model.market_price_history
    if not history:
        return False
    points = getattr(history, "points", None)
    if points is None and isinstance(history, dict):
        points = history.get("points")
    return bool(points)


def derive_base_url_from_full_url(full_url: str, fallback: str) -> str:
    parsed = urlparse(full_url)
    if parsed.scheme and parsed.netloc:
        return f"{parsed.scheme}://{parsed.netloc}"
    return fallback


def extract_csrf_token(soup: BeautifulSoup, html: str) -> Optional[str]:
    token_elem = soup.select_one("#csrfToken")
    if token_elem:
        token = token_elem.get("data-token")
        if token:
            return token
    match = CSRF_TOKEN_RE.search(html)
    if match:
        return match.group(1)
    match = CSRF_WINDOW_RE.search(html)
    return match.group(1) if match else None


def extract_sys_currency(html: str) -> Optional[str]:
    match = SYS_CURRENCY_RE.search(html)
    return match.group(1) if match else None


def extract_price_history_context(soup: BeautifulSoup) -> tuple[int, int]:
    container = soup.select_one("#priceHistoryChartTabContent")
    if not container:
        return DEFAULT_PRICE_HISTORY_REGION, 0
    region = safe_int(container.get("data-default-region"), DEFAULT_PRICE_HISTORY_REGION)
    variation = safe_int(container.get("data-variation-id"), 0)
    return region, variation


def build_appraisal_key(
    region_id: int,
    condition_id: int = DEFAULT_PRICE_HISTORY_CONDITION_ID,
    accessories_id: int = DEFAULT_PRICE_HISTORY_ACCESSORIES_ID,
    segment_id: int = DEFAULT_PRICE_HISTORY_SEGMENT_ID,
) -> str:
    return f"{condition_id}{accessories_id}{region_id}{segment_id}"


def build_chart_headers(csrf_token: str, referer: str) -> dict:
    return {
        "X-CSRF-Token": csrf_token,
        "X-Requested-With": "XMLHttpRequest",
        "Referer": referer,
        "Accept": "application/json, text/javascript, */*; q=0.01",
    }


def coerce_float(value: Optional[float]) -> Optional[float]:
    if value is None:
        return None
    try:
        return float(value)
    except (TypeError, ValueError):
        return None


def get_series_value(series: dict, ts: int) -> Optional[float]:
    if not series:
        return None
    if ts in series:
        return series.get(ts)
    return series.get(str(ts))


def parse_price_history_payload(
    payload: dict,
    region_id: int,
    variation_id: int,
    key: str,
    currency: Optional[str],
) -> Optional[MarketPriceHistory]:
    data = payload.get("data")
    if not isinstance(data, dict):
        return None

    all_series = data.get("all") if isinstance(data.get("all"), dict) else {}
    min_series = data.get("min") if isinstance(data.get("min"), dict) else {}
    max_series = data.get("max") if isinstance(data.get("max"), dict) else {}

    if not any((all_series, min_series, max_series)):
        return None

    raw_keys = list(all_series.keys()) + list(min_series.keys()) + list(max_series.keys())
    timestamps = []
    for ts in raw_keys:
        ts_int = safe_int(ts)
        if ts_int is not None:
            timestamps.append(ts_int)
    timestamps = sorted(set(timestamps))
    points = []
    for ts in timestamps:
        points.append(MarketPriceHistoryPoint(
            timestamp=ts,
            price=coerce_float(get_series_value(all_series, ts)),
            min_price=coerce_float(get_series_value(min_series, ts)),
            max_price=coerce_float(get_series_value(max_series, ts)),
        ))

    return MarketPriceHistory(
        region_id=region_id,
        variation_id=variation_id,
        key=key,
        currency=currency,
        points=points,
        max_time=safe_int(payload.get("max_time")),
        chart_id=payload.get("chart_id"),
    )


def decode_json_response(text: str) -> Optional[dict]:
    if not text:
        return None
    raw = text.strip()
    if raw.startswith("<"):
        try:
            raw = BeautifulSoup(raw, "html.parser").get_text().strip()
        except Exception:
            pass
    try:
        return json.loads(raw)
    except json.JSONDecodeError:
        return None


async def fetch_price_history_for_model(
    model: WatchChartsModelDTO,
    fetcher: WatchChartsFetcher,
    base_url: str,
    region_id: Optional[int],
) -> Optional[MarketPriceHistory]:
    full_url = model.watchcharts_url
    if not full_url:
        return None
    session_id: Optional[str] = None
    if fetcher._backend == "brightdata":
        session_id = str(uuid.uuid4().int % 1_000_000_000)

    try:
        html = await fetcher.fetch(full_url, allow_fallback=True, session_id=session_id)
    except Exception as exc:
        if fetcher._ac:
            html = await fetcher.solve_challenge(full_url)
            if not html or is_challenge_html(html):
                raise exc
        else:
            raise exc
    soup = make_soup(html)
    chart_base = derive_base_url_from_full_url(full_url, base_url)

    return await fetch_price_history(
        html=html,
        soup=soup,
        full_url=full_url,
        watch_id=model.watchcharts_id,
        base_url=chart_base,
        fetcher=fetcher,
        region_id=region_id,
        session_id=session_id,
    )


def extract_id_from_url(url: str) -> str:
    match = WATCH_MODEL_ID_RE.search(url)
    return match.group(1) if match else url


def normalize_text(text: str) -> str:
    return re.sub(r"\s+", " ", text).strip()


def extract_reference_from_specs(soup: BeautifulSoup) -> Optional[str]:
    for label in soup.select("table.spec-table td"):
        label_text = normalize_text(label.get_text(" ", strip=True)).lower()
        if label_text in {"reference", "reference(s)"}:
            value_td = label.find_next_sibling("td")
            if value_td:
                value_text = normalize_text(value_td.get_text(" ", strip=True))
                if value_text:
                    return value_text.split(",")[0].strip()
    return None


def extract_reference_from_url(detail_url: str) -> Optional[str]:
    match = REFERENCE_URL_RE.search(detail_url)
    return match.group("ref") if match else None


def is_valid_reference(reference: str) -> bool:
    if not reference:
        return False
    lower = reference.lower()
    if "watchcharts" in lower or is_challenge_html(lower):
        return False
    return True


def extract_reference(soup: BeautifulSoup, detail_url: str) -> str:
    h1 = soup.select_one("h1")
    if h1:
        span = h1.select_one("span")
        if span:
            span_text = normalize_text(span.get_text(" ", strip=True))
            if is_valid_reference(span_text):
                return span_text

        h1_text = normalize_text(h1.get_text(" ", strip=True))
        ref_match = REF_IN_TITLE_RE.search(h1_text)
        if ref_match and is_valid_reference(ref_match.group(1)):
            return ref_match.group(1)

        if h1_text and "ref" not in h1_text.lower() and len(h1_text) <= 24 and is_valid_reference(h1_text):
            return h1_text

    spec_reference = extract_reference_from_specs(soup)
    if spec_reference and is_valid_reference(spec_reference):
        return spec_reference

    url_reference = extract_reference_from_url(detail_url)
    return url_reference or ""


def clean_title_text(text: str) -> str:
    text = normalize_text(text)
    text = text.replace("| WatchCharts", "").strip()
    text = re.sub(r"\s+Price\s+as\s+of.*$", "", text, flags=re.IGNORECASE)
    text = re.sub(r"\s+Price.*$", "", text, flags=re.IGNORECASE)
    return text


def extract_full_name(soup: BeautifulSoup) -> str:
    h2 = soup.select_one("h2.h4.font-weight-bolder, h2.font-weight-bolder")
    if h2:
        text = normalize_text(h2.get_text(" ", strip=True))
        if text and not is_challenge_html(text):
            return text

    og_title = soup.find("meta", attrs={"property": "og:title"})
    if og_title and og_title.get("content"):
        text = clean_title_text(og_title["content"])
        if not is_challenge_html(text):
            return text

    if soup.title:
        text = clean_title_text(soup.title.get_text(" ", strip=True))
        if not is_challenge_html(text):
            return text

    return ""


def extract_is_current(soup: BeautifulSoup) -> Optional[bool]:
    containers = []
    overview = soup.select_one("#scrollspyOverview")
    if overview:
        containers.append(overview)
    containers.append(soup)

    for container in containers:
        for badge in container.select("span.badge"):
            badge_text = normalize_text(badge.get_text(" ", strip=True)).lower()
            tooltip_text = normalize_text(badge.get("data-bs-original-title", "")).lower()
            combined = f"{badge_text} {tooltip_text}".strip()

            if "current production" in combined or "in production" in combined:
                return True
            if "discontinued" in combined or "not in production" in combined or "out of production" in combined:
                return False

    return None


def extract_spec_table(soup: BeautifulSoup) -> dict:
    specs = {
        "case": {},
        "movement": {},
        "complications": [],
        "features": [],
        "style": None,
    }

    case_fields = {
        "case diameter": ("diameter_mm", parse_mm),
        "case thickness": ("thickness_mm", parse_mm),
        "case material": ("material", str),
        "bezel material": ("bezel_material", str),
        "crystal": ("crystal", str),
        "water resistance": ("water_resistance_m", parse_water_resistance),
        "lug width": ("lug_width_mm", parse_mm),
        "dial color": ("dial_color", str),
        "dial numerals": ("dial_numerals", str),
    }

    movement_fields = {
        "movement type": ("type", str),
        "movement caliber": ("caliber", str),
        "power reserve": ("power_reserve_hours", parse_hours),
        "frequency": ("frequency_bph", parse_bph),
        "number of jewels": ("jewels_count", parse_int),
    }

    selectors = [
        "table.spec-table tr",
        "#specificationModal table tr",
        "#scrollspyOverview table tr",
        ".specifications table tr",
    ]

    rows = []
    for selector in selectors:
        rows.extend(soup.select(selector))

    for row in rows:
        tds = row.select("td")
        if len(tds) != 2:
            continue

        label = normalize_text(tds[0].get_text()).lower()
        value_td = tds[1]
        value = normalize_text(value_td.get_text())

        if not value or value.lower() in ("n/a", "-", ""):
            continue

        if label == "complications":
            links = value_td.select("a")
            if links:
                specs["complications"] = [normalize_text(a.get_text()) for a in links if a.get_text(strip=True)]
            elif value:
                specs["complications"] = [v.strip() for v in value.split(",") if v.strip()]
        elif label == "features":
            links = value_td.select("a")
            if links:
                specs["features"] = [normalize_text(a.get_text()) for a in links if a.get_text(strip=True)]
            elif value:
                specs["features"] = [v.strip() for v in value.split(",") if v.strip()]
        elif label == "style":
            link = value_td.select_one("a")
            specs["style"] = normalize_text(link.get_text()) if link else value
        elif label in case_fields:
            field, parser = case_fields[label]
            parsed = parser(value) if parser != str else value
            if parsed:
                specs["case"][field] = parsed
        elif label in movement_fields:
            field, parser = movement_fields[label]
            parsed = parser(value) if parser != str else value
            if parsed:
                specs["movement"][field] = parsed

    return specs


def make_soup(html: str) -> BeautifulSoup:
    try:
        return BeautifulSoup(html, HTML_PARSER)
    except FeatureNotFound:
        return BeautifulSoup(html, "html.parser")


def parse_listing_html(html: str) -> List[dict]:
    soup = make_soup(html)

    cards = soup.select("div.col-md-6.col-lg-4")
    print(f"Found {len(cards)} watch cards")

    watches = []
    for card in cards:
        link = card.select_one('a[href*="/watch_model/"]')
        if not link:
            continue

        href = link.get("href", "")
        if not href:
            continue

        img = card.select_one("img.card-img-top")
        image_url = img.get("src") if img else None

        card_text = card.get_text(separator=" ", strip=True)
        case_diameter = parse_mm(card_text)
        is_current = None
        if "In Production" in card_text:
            is_current = True
        elif "Discontinued" in card_text or "Out of Production" in card_text:
            is_current = False

        retail_match = RETAIL_PRICE_RE.search(card_text)
        retail_price = int(retail_match.group(1).replace(",", "")) if retail_match else None

        market_match = MARKET_PRICE_RE.search(card_text)
        market_price = int(market_match.group(1).replace(",", "")) if market_match else None

        name_elem = card.select_one("h4")
        full_name = normalize_text(name_elem.get_text(" ", strip=True)) if name_elem else ""
        if not full_name:
            full_name = normalize_text(link.get_text(" ", strip=True)) if link else ""

        collection_elem = card.select_one("h5")
        collection = normalize_text(collection_elem.get_text(" ", strip=True)) if collection_elem else ""

        watches.append({
            "detail_url": href,
            "watchcharts_id": extract_id_from_url(href),
            "full_name": full_name,
            "collection": collection,
            "image_url": image_url,
            "case_diameter_mm": case_diameter,
            "is_current": is_current,
            "retail_price_usd": retail_price,
            "market_price_usd": market_price,
        })

    return watches


def parse_detail_soup(soup: BeautifulSoup, full_url: str) -> dict:
    full_name = extract_full_name(soup)
    reference = extract_reference(soup, full_url)

    breadcrumb = soup.select_one('nav[aria-label="breadcrumb"]')
    collection = ""
    if breadcrumb:
        links = breadcrumb.select("a")
        if len(links) >= 2:
            collection = links[-1].get_text(strip=True)

    is_current = extract_is_current(soup)

    retail_price = None
    market_price = None

    market_elem = soup.select_one(".market-price")
    if market_elem:
        market_price = parse_price(market_elem.get_text())

    if not market_price:
        for elem in soup.select("div.h1.market-price, div.h2.market-price"):
            price = parse_price(elem.get_text())
            if price:
                market_price = price
                break

    retail_label = soup.find(string=re.compile(r"Retail Price"))
    if retail_label:
        parent = retail_label.find_parent("div", class_=True)
        if parent:
            grand = parent.find_parent("div", class_=True)
            search_containers = [parent, grand] if grand else [parent]
            for container in search_containers:
                if not container:
                    continue
                for selector in [".h2.text-secondary", ".h3.text-secondary", ".h2.font-weight-bolder", ".h3.font-weight-bolder"]:
                    price_elem = container.select_one(selector)
                    if price_elem:
                        retail_price = parse_price(price_elem.get_text())
                        if retail_price:
                            break
                if retail_price:
                    break

    if not retail_price:
        for card in soup.select(".market-price-card, .card"):
            label = card.find(string=re.compile(r"Retail", re.I))
            if label:
                for selector in [".h5", ".h4", ".h3", ".h2"]:
                    elem = card.select_one(selector)
                    if elem:
                        price = parse_price(elem.get_text())
                        if price:
                            retail_price = price
                            break
                if retail_price:
                    break

    image_url = None

    og_img = soup.find("meta", attrs={"property": "og:image"})
    if og_img and og_img.get("content"):
        content = og_img["content"]
        if "cdn.watchcharts.com" in content and "/logo/" not in content:
            image_url = content.split("?")[0]

    if not image_url:
        featherlight = soup.select_one('a[data-featherlight="image"]')
        if featherlight and featherlight.get("href"):
            href = featherlight["href"]
            if "cdn.watchcharts.com" in href and "/logo/" not in href:
                image_url = href

    if not image_url:
        for img in soup.select("img.img-fluid"):
            src = img.get("src", "")
            if "cdn.watchcharts.com" in src and "/logo/" not in src and "/removebg/" in src:
                image_url = src.split("?")[0]
                break

    specs = extract_spec_table(soup)

    return {
        "full_name": full_name,
        "reference": reference,
        "collection": collection,
        "is_current": is_current,
        "retail_price_usd": retail_price,
        "market_price_usd": market_price,
        "image_url": image_url,
        "watchcharts_url": full_url,
        "case": specs.get("case") or None,
        "movement": specs.get("movement") or None,
        "complications": specs.get("complications", []),
        "features": specs.get("features", []),
        "style": specs.get("style"),
    }


def parse_detail_html(html: str, full_url: str) -> dict:
    soup = make_soup(html)
    return parse_detail_soup(soup, full_url)


async def fetch_price_history(
    html: str,
    soup: BeautifulSoup,
    full_url: str,
    watch_id: str,
    base_url: str,
    fetcher: WatchChartsFetcher,
    region_id: Optional[int] = None,
    session_id: Optional[str] = None,
) -> Optional[MarketPriceHistory]:
    async def fetch_via_flaresolverr() -> Optional[MarketPriceHistory]:
        if not fetcher._flaresolverr_available():
            return None
        fs_html = await fetcher._fetch_via_flaresolverr(full_url)
        if not fs_html or is_challenge_html(fs_html):
            return None
        fs_soup = make_soup(fs_html)
        fs_csrf = extract_csrf_token(fs_soup, fs_html)
        if not fs_csrf:
            return None
        fs_default_region, fs_variation_id = extract_price_history_context(fs_soup)
        fs_region = region_id if region_id is not None else fs_default_region
        fs_key = build_appraisal_key(fs_region)
        fs_chart_url = (
            f"{base_url}/charts/watch/{watch_id}.json?type=trend&key={fs_key}"
            f"&variation_id={fs_variation_id}&mobile=0"
        )
        fs_headers = build_chart_headers(fs_csrf, full_url)
        fs_text = await fetcher._fetch_via_flaresolverr(fs_chart_url, headers=fs_headers)
        if not fs_text:
            return None
        fs_payload = decode_json_response(fs_text)
        if not fs_payload:
            return None
        fs_currency = extract_sys_currency(fs_html)
        return parse_price_history_payload(
            payload=fs_payload,
            region_id=fs_region,
            variation_id=fs_variation_id,
            key=fs_key,
            currency=fs_currency,
        )

    if not soup.select_one("#priceHistoryChartTabContent"):
        return None

    csrf_token = extract_csrf_token(soup, html)
    if not csrf_token:
        return None

    default_region, variation_id = extract_price_history_context(soup)
    if region_id is None:
        region_id = default_region

    key = build_appraisal_key(region_id)
    chart_url = f"{base_url}/charts/watch/{watch_id}.json?type=trend&key={key}&variation_id={variation_id}&mobile=0"
    headers = build_chart_headers(csrf_token, full_url)
    attempted_flaresolverr = False

    try:
        text = await fetcher.fetch_with_headers(
            chart_url,
            headers=headers,
            allow_fallback=True,
            session_id=session_id,
        )
    except Exception as exc:
        history = await fetch_via_flaresolverr()
        attempted_flaresolverr = True
        if history:
            print(f"[{watch_id}] price history via flaresolverr")
            return history

        if fetcher._backend in {"brightdata", "curl-impersonate"}:
            pw_html = await fetcher._fetch_via_playwright_text(full_url)
            if pw_html:
                pw_soup = make_soup(pw_html)
                pw_csrf = extract_csrf_token(pw_soup, pw_html)
                if pw_csrf:
                    pw_region, pw_var_id = extract_price_history_context(pw_soup)
                    effective_region = region_id if region_id is not None else pw_region
                    pw_key = build_appraisal_key(effective_region)
                    pw_chart_url = (
                        f"{base_url}/charts/watch/{watch_id}.json?type=trend&key={pw_key}"
                        f"&variation_id={pw_var_id}&mobile=0"
                    )
                    pw_headers = build_chart_headers(pw_csrf, full_url)
                    pw_text = await fetcher._fetch_json_via_playwright(pw_chart_url, pw_headers)
                    if pw_text:
                        text = pw_text
                        print(f"[{watch_id}] price history via playwright")
                    else:
                        print(f"[{watch_id}] price history fetch failed: {exc}")
                        return None
                else:
                    print(f"[{watch_id}] price history fetch failed: no csrf token via playwright")
                    return None
            else:
                print(f"[{watch_id}] price history fetch failed: {exc}")
                return None
        elif fetcher._ac:
            refreshed = await fetcher.solve_challenge(full_url)
            if refreshed:
                try:
                    text = await fetcher.fetch_with_headers(
                        chart_url,
                        headers=headers,
                        allow_fallback=True,
                        session_id=session_id,
                    )
                except Exception as retry_exc:
                    print(f"[{watch_id}] price history fetch failed: {retry_exc}")
                    return None
            else:
                print(f"[{watch_id}] price history fetch failed: {exc}")
                return None
        else:
            print(f"[{watch_id}] price history fetch failed: {exc}")
            return None

    payload = decode_json_response(text)
    if not payload:
        if not attempted_flaresolverr:
            history = await fetch_via_flaresolverr()
            attempted_flaresolverr = True
            if history:
                print(f"[{watch_id}] price history via flaresolverr")
                return history
        print(f"[{watch_id}] price history invalid JSON")
        return None

    currency = extract_sys_currency(html)
    history = parse_price_history_payload(
        payload=payload,
        region_id=region_id,
        variation_id=variation_id,
        key=key,
        currency=currency,
    )
    if history and history.points:
        return history

    if not attempted_flaresolverr:
        error_message = None
        if isinstance(payload, dict):
            error_message = payload.get("message") or payload.get("error")
        history = await fetch_via_flaresolverr()
        attempted_flaresolverr = True
        if history:
            print(f"[{watch_id}] price history via flaresolverr")
            return history
        if error_message:
            return None

    return history if history and history.points else None


async def fetch_price_history_task(
    model: WatchChartsModelDTO,
    idx: int,
    total: int,
    fetcher: WatchChartsFetcher,
    sem: asyncio.Semaphore,
    base_url: str,
    region_id: Optional[int],
) -> tuple:
    async with sem:
        try:
            history = await fetch_price_history_for_model(
                model=model,
                fetcher=fetcher,
                base_url=base_url,
                region_id=region_id,
            )
            if not history or not history.points:
                return "empty", idx, model, None, "no_history"
            return "ok", idx, model, history, None
        except Exception as exc:
            reason = str(exc)
            if not reason:
                reason = f"{type(exc).__name__}"
            return "error", idx, model, None, reason


async def process_price_history_batch(
    batch_models: List[WatchChartsModelDTO],
    batch_start: int,
    total: int,
    fetcher: WatchChartsFetcher,
    concurrency: int,
    base_url: str,
    region_id: Optional[int],
    index_map: Optional[dict] = None,
) -> tuple[int, List[dict]]:
    sem = asyncio.Semaphore(max(1, concurrency))
    tasks = []

    for i, model in enumerate(batch_models):
        idx = batch_start + i
        if index_map:
            idx = index_map.get(model.watchcharts_id, idx)
        tasks.append(
            asyncio.create_task(
                fetch_price_history_task(
                    model=model,
                    idx=idx,
                    total=total,
                    fetcher=fetcher,
                    sem=sem,
                    base_url=base_url,
                    region_id=region_id,
                )
            )
        )

    updated = 0
    failed = []

    for task in asyncio.as_completed(tasks):
        status, idx, model, history, reason = await task
        if status == "ok":
            model.market_price_history = history
            updated += 1
            print(f"[{idx + 1}/{total}] HISTORY OK - {model.reference}")
        elif status == "empty":
            failed.append({
                "watchcharts_id": model.watchcharts_id,
                "reason": reason,
            })
            print(f"[{idx + 1}/{total}] HISTORY EMPTY")
        else:
            failed.append({
                "watchcharts_id": model.watchcharts_id,
                "reason": reason,
            })
            print(f"[{idx + 1}/{total}] HISTORY ERROR - {reason}")

    return updated, failed


def default_detail_payload(full_url: str) -> dict:
    return {
        "full_name": "",
        "reference": extract_reference_from_url(full_url) or "",
        "collection": "",
        "is_current": None,
        "retail_price_usd": None,
        "market_price_usd": None,
        "market_price_history": None,
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
    rotate_credentials: bool = True,
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
            if is_challenge_error(exc) and rotate_credentials:
                rotated = await fetcher.rotate_credentials(force_new_session=True)
                if not rotated:
                    rotated = await fetcher.rotate_impersonate()
                if rotated:
                    print(f"Listing page {page_num}: rotated credentials")
            if attempt < attempts - 1 and retry_delay > 0:
                await asyncio.sleep(retry_delay * (attempt + 1))

    if last_exc:
        raise last_exc
    raise RuntimeError(f"Failed to fetch listing page {page_num}")


async def crawl_all_listing_pages(
    entry_url: str,
    fetcher: WatchChartsFetcher,
    max_pages: int = 100,
    rotate_credentials: bool = True,
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
                rotate_credentials=rotate_credentials,
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
    rotate_credentials: bool,
    challenge_threshold: float,
) -> Tuple[List[WatchChartsModelDTO], List[dict]]:
    remaining = failed_urls
    recovered: List[WatchChartsModelDTO] = []

    for round_idx in range(retry_rounds):
        if not remaining:
            break

        round_num = round_idx + 1
        if rotate_credentials and should_rotate_credentials(remaining, challenge_threshold):
            rotated = await fetcher.rotate_credentials(force_new_session=True)
            if not rotated:
                rotated = await fetcher.rotate_impersonate()
            if rotated:
                print(f"Retry round {round_num}: rotated credentials")

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
    headless: bool = False,
    concurrency: int = 24,
    timeout: float = 30.0,
    retries: int = 1,
    use_anticaptcha: bool = True,
    ac_concurrency: int = 2,
    ac_timeout: float = 120.0,
    backend: str = "auto",
    impersonate: str = "chrome120",
    retry_rounds: int = 2,
    retry_delay: float = 2.0,
    retry_concurrency: int = 0,
    rotate_credentials: bool = True,
    challenge_threshold: float = CHALLENGE_THRESHOLD_DEFAULT,
    pw_headless: bool = True,
    include_price_history: bool = False,
    price_history_region: Optional[int] = None,
    price_history_only: bool = False,
    anti_captcha_key: Optional[str] = None,
    proxy_settings: Optional[ProxySettings] = None,
    brightdata_api_key: Optional[str] = None,
    brightdata_zone: Optional[str] = None,
    brightdata_endpoint: str = DEFAULT_BRIGHTDATA_ENDPOINT,
    brightdata_format: str = DEFAULT_BRIGHTDATA_FORMAT,
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
        use_anticaptcha=use_anticaptcha,
        ac_concurrency=ac_concurrency,
        ac_timeout=ac_timeout,
        backend=backend,
        impersonate=impersonate,
        pw_headless=pw_headless,
        anti_captcha_key=anti_captcha_key,
        proxy_settings=proxy_settings,
        brightdata_api_key=brightdata_api_key,
        brightdata_zone=brightdata_zone,
        brightdata_endpoint=brightdata_endpoint,
        brightdata_format=brightdata_format,
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
                if fetcher._ac_disabled() and fetcher._ac:
                    wait_time = fetcher._ac_disable_until - time.monotonic()
                    if wait_time > 0:
                        print(f"AntiCaptcha cooling down; waiting {int(wait_time)}s before continuing...")
                        await asyncio.sleep(wait_time)

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
                rotate_credentials=rotate_credentials,
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
                    rotate_credentials=rotate_credentials,
                    challenge_threshold=challenge_threshold,
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
    headless: bool = False,
    batch_size: int = 20,
    concurrency: int = 24,
    timeout: float = 30.0,
    retries: int = 1,
    use_anticaptcha: bool = True,
    ac_concurrency: int = 2,
    ac_timeout: float = 120.0,
    backend: str = "auto",
    impersonate: str = "chrome120",
    retry_rounds: int = 2,
    retry_delay: float = 2.0,
    retry_concurrency: int = 0,
    rotate_credentials: bool = True,
    challenge_threshold: float = CHALLENGE_THRESHOLD_DEFAULT,
    pw_headless: bool = True,
    include_price_history: bool = False,
    price_history_region: Optional[int] = None,
    price_history_only: bool = False,
    anti_captcha_key: Optional[str] = None,
    proxy_settings: Optional[ProxySettings] = None,
    brightdata_api_key: Optional[str] = None,
    brightdata_zone: Optional[str] = None,
    brightdata_endpoint: str = DEFAULT_BRIGHTDATA_ENDPOINT,
    brightdata_format: str = DEFAULT_BRIGHTDATA_FORMAT,
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
        use_anticaptcha=use_anticaptcha,
        ac_concurrency=ac_concurrency,
        ac_timeout=ac_timeout,
        backend=backend,
        impersonate=impersonate,
        pw_headless=pw_headless,
        anti_captcha_key=anti_captcha_key,
        proxy_settings=proxy_settings,
        brightdata_api_key=brightdata_api_key,
        brightdata_zone=brightdata_zone,
        brightdata_endpoint=brightdata_endpoint,
        brightdata_format=brightdata_format,
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
                    rotate_credentials=rotate_credentials,
                    challenge_threshold=challenge_threshold,
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
    headless: bool = False,
    concurrency: int = 24,
    timeout: float = 30.0,
    retries: int = 1,
    use_anticaptcha: bool = True,
    ac_concurrency: int = 2,
    ac_timeout: float = 120.0,
    backend: str = "auto",
    impersonate: str = "chrome120",
    retry_rounds: int = 2,
    retry_delay: float = 2.0,
    retry_concurrency: int = 0,
    rotate_credentials: bool = True,
    challenge_threshold: float = CHALLENGE_THRESHOLD_DEFAULT,
    pw_headless: bool = True,
    include_price_history: bool = False,
    price_history_region: Optional[int] = None,
    price_history_only: bool = False,
    anti_captcha_key: Optional[str] = None,
    proxy_settings: Optional[ProxySettings] = None,
    brightdata_api_key: Optional[str] = None,
    brightdata_zone: Optional[str] = None,
    brightdata_endpoint: str = DEFAULT_BRIGHTDATA_ENDPOINT,
    brightdata_format: str = DEFAULT_BRIGHTDATA_FORMAT,
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
            headless=headless,
            concurrency=concurrency,
            timeout=timeout,
            retries=retries,
            use_anticaptcha=use_anticaptcha,
            ac_concurrency=ac_concurrency,
            ac_timeout=ac_timeout,
            backend=backend,
            impersonate=impersonate,
            retry_rounds=retry_rounds,
            retry_delay=retry_delay,
            retry_concurrency=retry_concurrency,
            rotate_credentials=rotate_credentials,
            challenge_threshold=challenge_threshold,
            pw_headless=pw_headless,
            include_price_history=include_price_history,
            price_history_region=price_history_region,
            price_history_only=price_history_only,
            anti_captcha_key=anti_captcha_key,
            proxy_settings=proxy_settings,
            brightdata_api_key=brightdata_api_key,
            brightdata_zone=brightdata_zone,
            brightdata_endpoint=brightdata_endpoint,
            brightdata_format=brightdata_format,
            session_cookies=session_cookies,
        )
    )


def retry_failed(
    entry_url: str,
    brand_name: str,
    brand_slug: str,
    base_url: str,
    headless: bool = False,
    batch_size: int = 20,
    concurrency: int = 24,
    timeout: float = 30.0,
    retries: int = 1,
    use_anticaptcha: bool = True,
    ac_concurrency: int = 2,
    ac_timeout: float = 120.0,
    backend: str = "auto",
    impersonate: str = "chrome120",
    retry_rounds: int = 2,
    retry_delay: float = 2.0,
    retry_concurrency: int = 0,
    rotate_credentials: bool = True,
    challenge_threshold: float = CHALLENGE_THRESHOLD_DEFAULT,
    pw_headless: bool = True,
    include_price_history: bool = False,
    price_history_region: Optional[int] = None,
    price_history_only: bool = False,
    anti_captcha_key: Optional[str] = None,
    proxy_settings: Optional[ProxySettings] = None,
    brightdata_api_key: Optional[str] = None,
    brightdata_zone: Optional[str] = None,
    brightdata_endpoint: str = DEFAULT_BRIGHTDATA_ENDPOINT,
    brightdata_format: str = DEFAULT_BRIGHTDATA_FORMAT,
    session_cookies: Optional[List[dict]] = None,
) -> None:
    asyncio.run(
        retry_failed_async(
            entry_url=entry_url,
            brand_name=brand_name,
            brand_slug=brand_slug,
            base_url=base_url,
            headless=headless,
            batch_size=batch_size,
            concurrency=concurrency,
            timeout=timeout,
            retries=retries,
            use_anticaptcha=use_anticaptcha,
            ac_concurrency=ac_concurrency,
            ac_timeout=ac_timeout,
            backend=backend,
            impersonate=impersonate,
            retry_rounds=retry_rounds,
            retry_delay=retry_delay,
            retry_concurrency=retry_concurrency,
            rotate_credentials=rotate_credentials,
            challenge_threshold=challenge_threshold,
            pw_headless=pw_headless,
            include_price_history=include_price_history,
            price_history_region=price_history_region,
            price_history_only=price_history_only,
            anti_captcha_key=anti_captcha_key,
            proxy_settings=proxy_settings,
            brightdata_api_key=brightdata_api_key,
            brightdata_zone=brightdata_zone,
            brightdata_endpoint=brightdata_endpoint,
            brightdata_format=brightdata_format,
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
    parser.add_argument("--backend", type=str, default="brightdata", help="HTTP backend: curl-impersonate (Docker), brightdata, curl (curl_cffi), httpx")
    parser.add_argument("--impersonate", type=str, default="chrome120", help="curl_cffi impersonation profile(s), comma-separated")
    parser.add_argument("--retry-rounds", type=int, default=2, help="Recursive retry rounds per batch")
    parser.add_argument("--retry-delay", type=float, default=2.0, help="Base delay between retry rounds in seconds")
    parser.add_argument("--retry-concurrency", type=int, default=0, help="Override concurrency for retry rounds (0 = auto)")
    parser.add_argument("--challenge-threshold", type=float, default=CHALLENGE_THRESHOLD_DEFAULT, help="Challenge ratio to rotate credentials")
    parser.add_argument("--no-rotate-credentials", action="store_true", help="Disable credential rotation on challenge spikes")
    parser.add_argument("--no-anticaptcha", action="store_true", help="Disable anti-captcha.com Cloudflare solving")
    parser.add_argument("--ac-concurrency", type=int, default=2, help="Max concurrent anti-captcha solves")
    parser.add_argument("--ac-timeout", type=float, default=120.0, help="Anti-captcha solve timeout in seconds")
    parser.add_argument("--no-pw-headless", action="store_true", help="Show browser window (debug mode)")
    parser.add_argument("--price-history", action="store_true", help="Fetch market price history chart data")
    parser.add_argument("--price-history-region", type=int, default=None, help="Region id for price history (0 = Global)")
    parser.add_argument("--price-history-only", action="store_true", help="Update only models missing price history in existing output file")
    parser.add_argument("--anti-captcha-key", type=str, help="Anti-captcha API key (prefer ANTICAPTCHA_API_KEY env var)")
    parser.add_argument("--env-file", type=str, help="Load env vars from a file (default: .env or WATCHCHARTS_ENV_FILE)")
    parser.add_argument("--brightdata-api-key", type=str, help="Bright Data Web Access API key (Unlocker)")
    parser.add_argument("--brightdata-zone", type=str, help="Bright Data Web Unlocker zone name")
    parser.add_argument("--brightdata-endpoint", type=str, help=f"Bright Data API endpoint (default: {DEFAULT_BRIGHTDATA_ENDPOINT})")
    parser.add_argument("--brightdata-format", type=str, default=DEFAULT_BRIGHTDATA_FORMAT, help="Bright Data response format (default: raw)")
    parser.add_argument("--cookies-file", type=str, help="Path to Netscape cookies.txt file for session authentication")
    parser.add_argument("--proxy", type=str, help="Proxy URL for HTTP/Playwright/anti-captcha (e.g. http://user:pass@host:port)")
    parser.add_argument("--proxy-type", type=str, help="Proxy type for anti-captcha (http, https, socks4, socks5)")
    parser.add_argument("--brightdata-username", type=str, help="Bright Data proxy username (full username from dashboard)")
    parser.add_argument("--brightdata-password", type=str, help="Bright Data proxy password")
    parser.add_argument("--brightdata-host", type=str, help="Bright Data proxy host (default: brd.superproxy.io)")
    parser.add_argument("--brightdata-port", type=int, help="Bright Data proxy port (default: 22225)")
    parser.add_argument("--brightdata-scheme", type=str, help="Proxy scheme for Bright Data (http or https)")
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

    if not entry_url and not args.retry_failed and not args.price_history_only:
        parser.error("Provide --entry-url or --filters (or a brand with known filters).")
    if not entry_url:
        entry_url = base_url
    entry_url = normalize_entry_url(entry_url, base_url)

    brand_slug = derive_brand_slug(args.brand_slug, args.brand, entry_url)
    brand_name = derive_brand_name(args.brand, brand_slug)

    if args.price_history_only:
        args.price_history = True
        if args.concurrency > 2:
            args.concurrency = 2
        if args.retries < 2:
            args.retries = 2
        if args.timeout < 60:
            args.timeout = 60
        print(f"Price history only tuning: concurrency={args.concurrency} retries={args.retries} timeout={args.timeout}")

    brightdata_api_key = (
        args.brightdata_api_key
        or os.getenv("BRIGHTDATA_API_KEY")
        or os.getenv("BRIGHTDATA_WEB_ACCESS_KEY")
    )
    brightdata_zone = (
        args.brightdata_zone
        or os.getenv("BRIGHTDATA_WEB_ACCESS_ZONE")
        or os.getenv("BRIGHTDATA_ZONE")
    )
    brightdata_endpoint = args.brightdata_endpoint or os.getenv("BRIGHTDATA_ENDPOINT") or DEFAULT_BRIGHTDATA_ENDPOINT
    brightdata_format = args.brightdata_format or os.getenv("BRIGHTDATA_FORMAT") or DEFAULT_BRIGHTDATA_FORMAT

    cookies_file = args.cookies_file or os.getenv("WATCHCHARTS_COOKIES_FILE")
    session_cookies = []
    if cookies_file:
        if os.path.isfile(cookies_file):
            session_cookies = parse_netscape_cookies(cookies_file)
            print(f"Loaded {len(session_cookies)} cookies from {cookies_file}")
        else:
            print(f"Warning: cookies file not found: {cookies_file}")

    backend_choice = (args.backend or "auto").lower()
    use_brightdata = backend_choice in {"brightdata", "brightdata-api", "brightdata-webaccess"}
    if use_brightdata and (not brightdata_api_key or not brightdata_zone):
        parser.error("Bright Data backend requires --brightdata-api-key and --brightdata-zone")

    anti_captcha_key = args.anti_captcha_key or os.getenv("ANTICAPTCHA_API_KEY")
    use_anticaptcha = not args.no_anticaptcha and bool(anti_captcha_key)
    if use_brightdata:
        use_anticaptcha = False
    if (
        not args.no_anticaptcha
        and not anti_captcha_key
        and not use_brightdata
    ):
        print("Warning: ANTICAPTCHA_API_KEY not set, Cloudflare solving disabled")
        print("Set env var or use --anti-captcha-key to enable")

    proxy_input = None if use_brightdata else (args.proxy or os.getenv("WATCHCHARTS_PROXY"))
    proxy_type = args.proxy_type or os.getenv("WATCHCHARTS_PROXY_TYPE")
    proxy_settings = None
    if proxy_input:
        try:
            proxy_settings = parse_proxy_settings(proxy_input, proxy_type)
        except ValueError as exc:
            parser.error(str(exc))
    elif not use_brightdata:
        bd_username = args.brightdata_username or os.getenv("BRIGHTDATA_USERNAME")
        bd_password = args.brightdata_password or os.getenv("BRIGHTDATA_PASSWORD")
        bd_host = args.brightdata_host or os.getenv("BRIGHTDATA_HOST", "brd.superproxy.io")
        bd_port = args.brightdata_port or int(os.getenv("BRIGHTDATA_PORT", "22225"))
        bd_scheme = args.brightdata_scheme or os.getenv("BRIGHTDATA_SCHEME", "http")
        if bd_username and bd_password:
            proxy_input = f"{bd_scheme}://{bd_username}:{bd_password}@{bd_host}:{bd_port}"
            try:
                proxy_settings = parse_proxy_settings(proxy_input, proxy_type)
            except ValueError as exc:
                parser.error(str(exc))
    if proxy_settings:
        print(f"Using proxy: {proxy_settings.server}")
    elif use_anticaptcha:
        print("Note: AntiCaptcha is running proxyless; Cloudflare may block (ERROR_IP_BLOCKED).")

    if args.retry_failed:
        retry_failed(
            entry_url=entry_url,
            brand_name=brand_name,
            brand_slug=brand_slug,
            base_url=base_url,
            headless=args.headless,
            batch_size=args.batch,
            concurrency=args.concurrency,
            timeout=args.timeout,
            retries=args.retries,
            use_anticaptcha=use_anticaptcha,
            ac_concurrency=args.ac_concurrency,
            ac_timeout=args.ac_timeout,
            backend=args.backend,
            impersonate=args.impersonate,
            retry_rounds=args.retry_rounds,
            retry_delay=args.retry_delay,
            retry_concurrency=args.retry_concurrency,
            rotate_credentials=not args.no_rotate_credentials,
            challenge_threshold=args.challenge_threshold,
            pw_headless=not args.no_pw_headless,
            include_price_history=args.price_history,
            price_history_region=args.price_history_region,
            price_history_only=args.price_history_only,
            anti_captcha_key=anti_captcha_key,
            proxy_settings=proxy_settings,
            brightdata_api_key=brightdata_api_key,
            brightdata_zone=brightdata_zone,
            brightdata_endpoint=brightdata_endpoint,
            brightdata_format=brightdata_format,
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
            headless=args.headless,
            concurrency=args.concurrency,
            timeout=args.timeout,
            retries=args.retries,
            use_anticaptcha=use_anticaptcha,
            ac_concurrency=args.ac_concurrency,
            ac_timeout=args.ac_timeout,
            backend=args.backend,
            impersonate=args.impersonate,
            retry_rounds=args.retry_rounds,
            retry_delay=args.retry_delay,
            retry_concurrency=args.retry_concurrency,
            rotate_credentials=not args.no_rotate_credentials,
            challenge_threshold=args.challenge_threshold,
            pw_headless=not args.no_pw_headless,
            include_price_history=args.price_history,
            price_history_region=args.price_history_region,
            price_history_only=args.price_history_only,
            anti_captcha_key=anti_captcha_key,
            proxy_settings=proxy_settings,
            brightdata_api_key=brightdata_api_key,
            brightdata_zone=brightdata_zone,
            brightdata_endpoint=brightdata_endpoint,
            brightdata_format=brightdata_format,
            session_cookies=session_cookies,
        )


if __name__ == "__main__":
    main()
