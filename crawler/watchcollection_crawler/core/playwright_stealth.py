import asyncio
from typing import Any, Optional

from playwright.async_api import async_playwright, Browser, BrowserContext, Page

from watchcollection_crawler.core.anticaptcha import (
    AntiCaptchaProxy,
    AntiCaptchaSolver,
    detect_captcha_challenge,
    detect_turnstile,
)


class PlaywrightStealthClient:
    def __init__(
        self,
        headless: bool = True,
        timeout: float = 60.0,
        channel: Optional[str] = None,
        user_data_dir: Optional[str] = None,
        use_stealth: bool = True,
        anti_captcha_key: Optional[str] = None,
        anti_captcha_timeout: float = 120.0,
        anti_captcha_proxy: Optional[AntiCaptchaProxy] = None,
        proxy: Optional[dict] = None,
    ):
        self._headless = headless
        self._timeout_ms = int(timeout * 1000)
        self._channel = channel
        self._user_data_dir = user_data_dir
        self._use_stealth = use_stealth
        self._anti_captcha_key = anti_captcha_key
        self._anti_captcha_timeout = anti_captcha_timeout
        self._anti_captcha_proxy = anti_captcha_proxy
        self._proxy = proxy
        self._anti_captcha: Optional[AntiCaptchaSolver] = None
        self._playwright = None
        self._browser: Optional[Browser] = None
        self._context: Optional[BrowserContext] = None
        self._page: Optional[Page] = None

    async def start(self) -> None:
        if self._browser or self._context:
            return

        if self._anti_captcha_key and not self._anti_captcha:
            self._anti_captcha = AntiCaptchaSolver(
                self._anti_captcha_key,
                timeout=int(self._anti_captcha_timeout),
                proxy=self._anti_captcha_proxy,
            )

        self._playwright = await async_playwright().start()
        launch_kwargs = {
            "headless": self._headless,
            "args": [
                "--disable-blink-features=AutomationControlled",
                "--disable-dev-shm-usage",
                "--no-sandbox",
            ],
        }
        if self._proxy:
            launch_kwargs["proxy"] = self._proxy
        if self._channel:
            launch_kwargs["channel"] = self._channel

        if self._user_data_dir:
            self._context = await self._playwright.chromium.launch_persistent_context(
                self._user_data_dir,
                viewport={"width": 1920, "height": 1080},
                user_agent=(
                    "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) "
                    "AppleWebKit/537.36 (KHTML, like Gecko) "
                    "Chrome/122.0.0.0 Safari/537.36"
                ),
                java_script_enabled=True,
                bypass_csp=True,
                **launch_kwargs,
            )
        else:
            self._browser = await self._playwright.chromium.launch(**launch_kwargs)
            self._context = await self._browser.new_context(
                viewport={"width": 1920, "height": 1080},
                user_agent=(
                    "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) "
                    "AppleWebKit/537.36 (KHTML, like Gecko) "
                    "Chrome/122.0.0.0 Safari/537.36"
                ),
                java_script_enabled=True,
                bypass_csp=True,
            )

        if self._use_stealth and self._context:
            await self._apply_stealth(self._context)
        if self._context:
            self._page = await self._context.new_page()

    async def _apply_stealth(self, context: BrowserContext) -> None:
        await context.add_init_script("""
            Object.defineProperty(navigator, 'webdriver', {get: () => undefined});
            Object.defineProperty(navigator, 'languages', {get: () => ['en-US', 'en']});
            Object.defineProperty(navigator, 'plugins', {get: () => [1, 2, 3, 4, 5]});

            const originalQuery = window.navigator.permissions.query;
            window.navigator.permissions.query = (parameters) => (
                parameters.name === 'notifications' ?
                    Promise.resolve({ state: Notification.permission }) :
                    originalQuery(parameters)
            );

            window.chrome = {runtime: {}};

            Object.defineProperty(navigator, 'platform', {get: () => 'MacIntel'});
            Object.defineProperty(navigator, 'hardwareConcurrency', {get: () => 8});
            Object.defineProperty(navigator, 'deviceMemory', {get: () => 8});
        """)

    async def close(self) -> None:
        if self._page:
            await self._page.close()
            self._page = None
        if self._context:
            await self._context.close()
            self._context = None
        if self._browser:
            await self._browser.close()
            self._browser = None
        if self._playwright:
            await self._playwright.stop()
            self._playwright = None

    @property
    def page(self) -> Optional[Page]:
        return self._page

    async def cookies(self) -> list:
        if not self._context:
            return []
        return await self._context.cookies()

    async def get(self, url: str, wait_for_cf: bool = True, cf_timeout: Optional[float] = None) -> str:
        if not self._page:
            await self.start()

        await self._page.goto(url, timeout=self._timeout_ms, wait_until="domcontentloaded")

        if wait_for_cf:
            await self._wait_for_cloudflare(url, max_wait=cf_timeout)

        return await self._page.content()

    async def get_text(self, url: str, wait_for_cf: bool = True, cf_timeout: Optional[float] = None) -> str:
        if not self._page:
            await self.start()

        await self._page.goto(url, timeout=self._timeout_ms, wait_until="domcontentloaded")

        if wait_for_cf:
            await self._wait_for_cloudflare(url, max_wait=cf_timeout)

        try:
            return await self._page.evaluate("document.body.innerText")
        except Exception:
            return await self._page.content()

    async def _wait_for_cloudflare(self, page_url: str, max_wait: Optional[float] = None) -> None:
        cf_markers = [
            "just a moment",
            "checking your browser",
            "attention required",
            "cf-browser-verification",
            "cf-chl",
            "cf-turnstile",
            "challenges.cloudflare.com",
            "challenge-platform",
            "cdn-cgi/challenge-platform",
        ]

        if max_wait is None:
            max_wait = max(30.0, self._anti_captcha_timeout)

        start = asyncio.get_event_loop().time()
        attempted_captcha = False
        while (asyncio.get_event_loop().time() - start) < max_wait:
            if await self._has_cookie("cf_clearance"):
                return
            content = await self._page.content()
            lower = content.lower()
            has_markers = any(marker in lower for marker in cf_markers)
            if not has_markers and not detect_captcha_challenge(content):
                return
            if self._anti_captcha and not attempted_captcha:
                attempted_captcha = await self._solve_captcha_if_present(content, page_url)
                if attempted_captcha:
                    await asyncio.sleep(3.0)
                    continue
            await asyncio.sleep(1.0)

        raise RuntimeError("Cloudflare challenge not resolved within timeout")

    async def _inject_token(self, target: Any, token: str) -> str:
        return await target.evaluate(
            """
            (token) => {
                const selectors = [
                    'textarea[name="cf-turnstile-response"]',
                    'input[name="cf-turnstile-response"]',
                    'textarea[name="g-recaptcha-response"]',
                    'input[name="g-recaptcha-response"]',
                    'textarea[name="h-captcha-response"]',
                    'input[name="h-captcha-response"]',
                ];
                let found = false;
                for (const selector of selectors) {
                    const el = document.querySelector(selector);
                    if (el) {
                        el.value = token;
                        el.innerHTML = token;
                        el.dispatchEvent(new Event('input', { bubbles: true }));
                        el.dispatchEvent(new Event('change', { bubbles: true }));
                        found = true;
                    }
                }

                if (window.turnstile && typeof window.turnstile.getResponse === 'function') {
                    try {
                        const widget = document.querySelector('[data-callback]');
                        if (widget) {
                            const callbackName = widget.getAttribute('data-callback');
                            if (callbackName && window[callbackName]) {
                                window[callbackName](token);
                                return 'callback';
                            }
                        }
                    } catch (e) {}
                }

                const form = document.querySelector('form[action*="challenge"], form.challenge-form, form');
                if (form) {
                    form.submit();
                    return 'form';
                }

                const buttons = document.querySelectorAll('button[type="submit"], input[type="submit"], .challenge-button');
                for (const btn of buttons) {
                    if (btn.offsetParent !== null) {
                        btn.click();
                        return 'button';
                    }
                }

                return found ? 'injected' : 'none';
            }
            """,
            token,
        )

    async def _has_cookie(self, name: str) -> bool:
        if not self._context:
            return False
        cookies = await self._context.cookies()
        return any(cookie.get("name") == name for cookie in cookies)

    async def _solve_captcha_if_present(self, html: str, page_url: str) -> bool:
        if not self._anti_captcha:
            return False

        turnstile = detect_turnstile(html, page_url)
        if not turnstile and self._page:
            for frame in self._page.frames:
                if frame == self._page.main_frame:
                    continue
                try:
                    frame_html = await frame.content()
                except Exception:
                    continue
                frame_url = frame.url or page_url
                turnstile = detect_turnstile(frame_html, page_url)
                if turnstile:
                    break

        if turnstile:
            print("Detected turnstile challenge, solving...")
            try:
                token = await asyncio.to_thread(self._anti_captcha.solve_turnstile, turnstile)
                print(f"Got token from anti-captcha ({len(token)} chars)")
            except Exception as exc:
                print(f"Anti-captcha solve failed: {exc}")
                return False
        else:
            challenge = detect_captcha_challenge(html)
            if not challenge and self._page:
                for frame in self._page.frames:
                    if frame == self._page.main_frame:
                        continue
                    try:
                        frame_html = await frame.content()
                    except Exception:
                        continue
                    challenge = detect_captcha_challenge(frame_html)
                    if challenge:
                        break
            if not challenge:
                return False

            print(f"Detected {challenge.kind} challenge, solving...")
            try:
                token = await asyncio.to_thread(self._anti_captcha.solve, challenge, page_url)
                print(f"Got token from anti-captcha ({len(token)} chars)")
            except Exception as exc:
                print(f"Anti-captcha solve failed: {exc}")
                return False

        injected = await self._inject_token(self._page, token)
        if injected == "none" and self._page:
            for frame in self._page.frames:
                if frame == self._page.main_frame:
                    continue
                try:
                    frame_injected = await self._inject_token(frame, token)
                except Exception:
                    continue
                if frame_injected != "none":
                    injected = frame_injected
                    break
        print(f"Token injection result: {injected}")

        try:
            await self._page.wait_for_navigation(timeout=10000)
        except Exception:
            pass

        await self._page.wait_for_timeout(2000)
        return True

    def get_cookies(self) -> list:
        if not self._context:
            return []
        return asyncio.get_event_loop().run_until_complete(self._context.cookies())
