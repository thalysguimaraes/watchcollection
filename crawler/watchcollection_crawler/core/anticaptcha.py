import asyncio
import html as html_lib
import os
import re
from dataclasses import dataclass
from typing import Optional

SITEKEY_PATTERNS = [
    re.compile(r'data-sitekey=["\']([^"\']+)["\']', re.IGNORECASE),
    re.compile(r'turnstile\.render\([^,]*,\s*\{[^}]*sitekey:\s*["\']([^"\']+)["\']', re.IGNORECASE),
    re.compile(r'siteKey["\']?\s*[:=]\s*["\']([^"\']+)["\']', re.IGNORECASE),
    re.compile(r'cf-turnstile[^>]*data-sitekey=["\']([^"\']+)["\']', re.IGNORECASE),
    re.compile(r'[?&]sitekey=([0-9A-Za-z_-]+)', re.IGNORECASE),
]

TURNSTILE_TAG_PATTERN = re.compile(
    r'<[^>]*class=["\'][^"\']*cf-turnstile[^"\']*["\'][^>]*>',
    re.IGNORECASE,
)
TURNSTILE_ATTR_PATTERN = re.compile(r'([a-zA-Z0-9_-]+)=["\']([^"\']+)["\']')
TURNSTILE_RENDER_PATTERN = re.compile(
    r'turnstile\.render\([^,]*,\s*\{(.*?)\}\s*\)',
    re.IGNORECASE | re.DOTALL,
)

SITEKEY_RENDER_PATTERN = re.compile(r'\bsitekey\s*:\s*["\']([^"\']+)["\']', re.IGNORECASE)
ACTION_PATTERN = re.compile(r'\baction\s*:\s*["\']([^"\']+)["\']', re.IGNORECASE)
CDATA_PATTERN = re.compile(r'\bcData\s*:\s*["\']([^"\']+)["\']', re.IGNORECASE)
CHL_PAGE_DATA_PATTERN = re.compile(r'\bchlPageData\s*:\s*["\']([^"\']+)["\']', re.IGNORECASE)


def _clean_attr(value: Optional[str]) -> Optional[str]:
    if value is None:
        return None
    return html_lib.unescape(value)


def _extract_turnstile_attrs(html: str) -> dict:
    match = TURNSTILE_TAG_PATTERN.search(html)
    if not match:
        return {}
    tag = match.group(0)
    attrs = {}
    for key, value in TURNSTILE_ATTR_PATTERN.findall(tag):
        attrs[key.lower()] = _clean_attr(value)
    return attrs


def _extract_turnstile_render_config(html: str) -> dict:
    match = TURNSTILE_RENDER_PATTERN.search(html)
    if not match:
        return {}
    block = match.group(1)
    config = {}

    sitekey_match = SITEKEY_RENDER_PATTERN.search(block)
    if sitekey_match:
        config["sitekey"] = _clean_attr(sitekey_match.group(1))
    action_match = ACTION_PATTERN.search(block)
    if action_match:
        config["action"] = _clean_attr(action_match.group(1))
    cdata_match = CDATA_PATTERN.search(block)
    if cdata_match:
        config["cdata"] = _clean_attr(cdata_match.group(1))
    chl_match = CHL_PAGE_DATA_PATTERN.search(block)
    if chl_match:
        config["chlpagedata"] = _clean_attr(chl_match.group(1))

    return config


@dataclass(frozen=True)
class TurnstileChallenge:
    site_key: str
    page_url: str
    action: Optional[str] = None
    cdata: Optional[str] = None
    chl_page_data: Optional[str] = None


@dataclass(frozen=True)
class AntiCaptchaProxy:
    proxy_type: str
    address: str
    port: int
    login: Optional[str] = None
    password: Optional[str] = None


def detect_turnstile(html: str, page_url: str) -> Optional[TurnstileChallenge]:
    if not html:
        return None

    lower = html.lower()
    if (
        "turnstile" not in lower
        and "cf-turnstile" not in lower
        and "challenges.cloudflare.com" not in lower
        and "challenge-platform" not in lower
    ):
        return None

    site_key = None
    action = None
    cdata = None
    chl_page_data = None

    attrs = _extract_turnstile_attrs(html)
    if attrs:
        site_key = attrs.get("data-sitekey") or attrs.get("sitekey")
        action = attrs.get("data-action")
        cdata = attrs.get("data-cdata")
        chl_page_data = attrs.get("data-chl-page-data")

    render_config = _extract_turnstile_render_config(html)
    if render_config:
        site_key = site_key or render_config.get("sitekey")
        action = action or render_config.get("action")
        cdata = cdata or render_config.get("cdata")
        chl_page_data = chl_page_data or render_config.get("chlpagedata")

    if not site_key:
        for pattern in SITEKEY_PATTERNS:
            match = pattern.search(html)
            if match:
                site_key = _clean_attr(match.group(1))
                break

    if not site_key:
        return None

    return TurnstileChallenge(
        site_key=site_key,
        page_url=page_url,
        action=action,
        cdata=cdata,
        chl_page_data=chl_page_data,
    )


class AntiCaptchaClient:
    def __init__(
        self,
        api_key: Optional[str] = None,
        timeout: int = 120,
        proxy: Optional[AntiCaptchaProxy] = None,
    ) -> None:
        self._api_key = api_key or os.getenv("ANTICAPTCHA_API_KEY", "")
        if not self._api_key:
            raise RuntimeError("ANTICAPTCHA_API_KEY env var or api_key parameter required")
        self._timeout = max(30, int(timeout))
        self._proxy = proxy
        self._solver_cls = None

    def _get_solver(self):
        if self._solver_cls is None:
            try:
                if self._proxy:
                    from anticaptchaofficial.turnstileproxyon import turnstileProxyon
                    self._solver_cls = turnstileProxyon
                else:
                    from anticaptchaofficial.turnstileproxyless import turnstileProxyless
                    self._solver_cls = turnstileProxyless
            except ImportError as exc:
                raise RuntimeError(
                    "anticaptchaofficial is required; install with `pip install anticaptchaofficial`"
                ) from exc
        return self._solver_cls()

    def _configure_turnstile_solver(self, solver, challenge: TurnstileChallenge) -> None:
        solver.set_verbose(0)
        solver.set_key(self._api_key)
        solver.set_website_url(challenge.page_url)
        solver.set_website_key(challenge.site_key)

        if self._proxy:
            solver.set_proxy_type(self._proxy.proxy_type)
            solver.set_proxy_address(self._proxy.address)
            solver.set_proxy_port(self._proxy.port)
            if self._proxy.login:
                solver.set_proxy_login(self._proxy.login)
            if self._proxy.password:
                solver.set_proxy_password(self._proxy.password)

        if challenge.action:
            solver.set_action(challenge.action)
        if challenge.cdata:
            solver.set_cdata(challenge.cdata)
        if challenge.chl_page_data:
            solver.set_chlpagedata(challenge.chl_page_data)

    def solve_turnstile_sync(self, challenge: TurnstileChallenge) -> str:
        solver = self._get_solver()
        self._configure_turnstile_solver(solver, challenge)

        token = solver.solve_and_return_solution()
        if token == 0:
            if (
                solver.error_code == "ERROR_INCORRECT_SESSION_DATA"
                and (challenge.action or challenge.cdata or challenge.chl_page_data)
            ):
                solver = self._get_solver()
                self._configure_turnstile_solver(
                    solver,
                    TurnstileChallenge(site_key=challenge.site_key, page_url=challenge.page_url),
                )
                token = solver.solve_and_return_solution()
                if token != 0:
                    return token
            if solver.error_code == "ERROR_IP_BLOCKED" and not self._proxy:
                raise RuntimeError(
                    "Anti-captcha solve failed: ERROR_IP_BLOCKED (proxyless). "
                    "Use a proxy-backed TurnstileTask."
                )
            raise RuntimeError(f"Anti-captcha solve failed: {solver.error_code}")

        return token

    async def solve_turnstile(self, challenge: TurnstileChallenge) -> str:
        return await asyncio.to_thread(self.solve_turnstile_sync, challenge)


@dataclass(frozen=True)
class CaptchaChallenge:
    kind: str
    site_key: str


def detect_captcha_challenge(html: str) -> Optional[CaptchaChallenge]:
    if not html:
        return None

    lower = html.lower()
    for pattern in SITEKEY_PATTERNS:
        match = pattern.search(html)
        if match:
            site_key = _clean_attr(match.group(1))
            if (
                "turnstile" in lower
                or "cf-turnstile" in lower
                or "challenges.cloudflare.com" in lower
                or "challenge-platform" in lower
            ):
                return CaptchaChallenge(kind="turnstile", site_key=site_key)
            if "hcaptcha" in lower:
                return CaptchaChallenge(kind="hcaptcha", site_key=site_key)
            if "recaptcha" in lower or "g-recaptcha" in lower:
                return CaptchaChallenge(kind="recaptcha", site_key=site_key)
    return None


class AntiCaptchaSolver:
    def __init__(
        self,
        api_key: str,
        timeout: int = 120,
        proxy: Optional[AntiCaptchaProxy] = None,
    ) -> None:
        self._client = AntiCaptchaClient(api_key=api_key, timeout=timeout, proxy=proxy)

    def solve_turnstile(self, challenge: TurnstileChallenge) -> str:
        return self._client.solve_turnstile_sync(challenge)

    def solve(self, challenge: CaptchaChallenge, page_url: str) -> str:
        if challenge.kind == "turnstile":
            tc = TurnstileChallenge(site_key=challenge.site_key, page_url=page_url)
            return self._client.solve_turnstile_sync(tc)

        solver = self._get_solver_for_type(challenge.kind)
        solver.set_verbose(0)
        solver.set_key(self._client._api_key)
        solver.set_website_url(page_url)
        solver.set_website_key(challenge.site_key)

        token = solver.solve_and_return_solution()
        if token == 0:
            raise RuntimeError(f"Anti-captcha solve failed: {solver.error_code}")
        return token

    def _get_solver_for_type(self, kind: str):
        if kind == "hcaptcha":
            try:
                from anticaptchaofficial.hcaptchaproxyless import hCaptchaProxyless
                return hCaptchaProxyless()
            except ImportError:
                pass
        try:
            from anticaptchaofficial.recaptchav2proxyless import recaptchaV2Proxyless
            return recaptchaV2Proxyless()
        except ImportError as exc:
            raise RuntimeError("anticaptchaofficial is required") from exc
