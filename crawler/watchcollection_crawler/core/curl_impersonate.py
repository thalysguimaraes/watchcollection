import asyncio
import os
import random
import subprocess
import shutil
import time
from typing import Optional
from bs4 import BeautifulSoup

DOCKER_IMAGE = os.getenv("CURL_IMPERSONATE_IMAGE", "lwthiker/curl-impersonate:0.6-chrome")
CURL_BINARY = os.getenv("CURL_IMPERSONATE_BINARY", "curl_chrome116")
DEFAULT_TIMEOUT = int(os.getenv("CURL_IMPERSONATE_TIMEOUT", "30"))
DEFAULT_MIN_DELAY = float(os.getenv("CURL_IMPERSONATE_MIN_DELAY", "2.0"))
DEFAULT_MAX_DELAY = float(os.getenv("CURL_IMPERSONATE_MAX_DELAY", "4.0"))


class CurlImpersonateClient:
    def __init__(
        self,
        docker_image: str = DOCKER_IMAGE,
        curl_binary: str = CURL_BINARY,
        timeout: int = DEFAULT_TIMEOUT,
        use_docker: Optional[bool] = None,
    ):
        self.docker_image = docker_image
        self.curl_binary = curl_binary
        self.timeout = timeout

        if use_docker is None:
            self.use_docker = not self._check_native_binary()
        else:
            self.use_docker = use_docker

    def _check_native_binary(self) -> bool:
        native_path = shutil.which(self.curl_binary)
        if native_path:
            try:
                result = subprocess.run(
                    [native_path, "--version"],
                    capture_output=True,
                    timeout=5,
                )
                return result.returncode == 0
            except Exception:
                pass
        return False

    def _build_command(self, url: str, headers: Optional[dict] = None, follow_redirects: bool = True) -> list[str]:
        if self.use_docker:
            cmd = [
                "docker", "run", "--rm",
                self.docker_image,
                self.curl_binary,
            ]
        else:
            cmd = [self.curl_binary]

        cmd.extend(["-s"])

        if follow_redirects:
            cmd.append("-L")

        if headers:
            for key, value in headers.items():
                cmd.extend(["-H", f"{key}: {value}"])

        cmd.append(url)
        return cmd

    def get(
        self,
        url: str,
        headers: Optional[dict] = None,
        follow_redirects: bool = True,
        timeout: Optional[int] = None,
    ) -> str:
        cmd = self._build_command(url, headers, follow_redirects)
        effective_timeout = timeout or self.timeout

        try:
            result = subprocess.run(
                cmd,
                capture_output=True,
                timeout=effective_timeout,
                text=True,
            )
            if result.returncode != 0:
                stderr = result.stderr.strip()
                raise RuntimeError(f"curl-impersonate failed: {stderr or 'unknown error'}")
            return result.stdout
        except subprocess.TimeoutExpired:
            raise RuntimeError(f"curl-impersonate timeout after {effective_timeout}s")
        except FileNotFoundError as e:
            if self.use_docker:
                raise RuntimeError("Docker not found. Install Docker or use native curl-impersonate.") from e
            raise RuntimeError(f"curl-impersonate binary not found: {self.curl_binary}") from e

    def get_soup(
        self,
        url: str,
        headers: Optional[dict] = None,
        follow_redirects: bool = True,
        timeout: Optional[int] = None,
    ) -> BeautifulSoup:
        html = self.get(url, headers, follow_redirects, timeout)
        return BeautifulSoup(html, "html.parser")

    def get_status(
        self,
        url: str,
        headers: Optional[dict] = None,
        follow_redirects: bool = True,
        timeout: Optional[int] = None,
    ) -> tuple[int, str]:
        if self.use_docker:
            cmd = [
                "docker", "run", "--rm",
                self.docker_image,
                self.curl_binary,
            ]
        else:
            cmd = [self.curl_binary]

        cmd.extend(["-s", "-w", "%{http_code}", "-o", "-"])

        if follow_redirects:
            cmd.append("-L")

        if headers:
            for key, value in headers.items():
                cmd.extend(["-H", f"{key}: {value}"])

        cmd.append(url)
        effective_timeout = timeout or self.timeout

        try:
            result = subprocess.run(
                cmd,
                capture_output=True,
                timeout=effective_timeout,
            )
            if result.returncode != 0:
                stderr = result.stderr.decode("utf-8", errors="replace").strip()
                raise RuntimeError(f"curl-impersonate failed: {stderr}")

            output = result.stdout.decode("utf-8", errors="replace")
            status_code = int(output[-3:])
            body = output[:-3]
            return status_code, body
        except subprocess.TimeoutExpired:
            raise RuntimeError(f"curl-impersonate timeout after {effective_timeout}s")


class AsyncCurlImpersonateClient:
    def __init__(
        self,
        docker_image: str = DOCKER_IMAGE,
        curl_binary: str = CURL_BINARY,
        timeout: int = DEFAULT_TIMEOUT,
        use_docker: Optional[bool] = None,
        max_concurrent: int = 10,
        min_delay: float = DEFAULT_MIN_DELAY,
        max_delay: float = DEFAULT_MAX_DELAY,
        rate_limit: bool = True,
    ):
        self._sync_client = CurlImpersonateClient(
            docker_image=docker_image,
            curl_binary=curl_binary,
            timeout=timeout,
            use_docker=use_docker,
        )
        self._semaphore = asyncio.Semaphore(max_concurrent)
        self.timeout = timeout
        self.min_delay = min_delay
        self.max_delay = max_delay
        self.rate_limit = rate_limit
        self._last_request_time: dict[str, float] = {}
        self._lock = asyncio.Lock()

    async def _wait_for_rate_limit(self, domain: str) -> None:
        if not self.rate_limit:
            return
        async with self._lock:
            now = time.time()
            last_time = self._last_request_time.get(domain, 0)
            elapsed = now - last_time
            min_wait = random.uniform(self.min_delay, self.max_delay)
            if elapsed < min_wait:
                await asyncio.sleep(min_wait - elapsed)
            self._last_request_time[domain] = time.time()

    def _extract_domain(self, url: str) -> str:
        from urllib.parse import urlparse
        return urlparse(url).netloc

    @property
    def use_docker(self) -> bool:
        return self._sync_client.use_docker

    async def get(
        self,
        url: str,
        headers: Optional[dict] = None,
        follow_redirects: bool = True,
        timeout: Optional[int] = None,
    ) -> str:
        domain = self._extract_domain(url)
        await self._wait_for_rate_limit(domain)
        async with self._semaphore:
            return await asyncio.to_thread(
                self._sync_client.get,
                url,
                headers,
                follow_redirects,
                timeout,
            )

    async def get_soup(
        self,
        url: str,
        headers: Optional[dict] = None,
        follow_redirects: bool = True,
        timeout: Optional[int] = None,
    ) -> BeautifulSoup:
        html = await self.get(url, headers, follow_redirects, timeout)
        return BeautifulSoup(html, "html.parser")

    async def get_status(
        self,
        url: str,
        headers: Optional[dict] = None,
        follow_redirects: bool = True,
        timeout: Optional[int] = None,
    ) -> tuple[int, str]:
        domain = self._extract_domain(url)
        await self._wait_for_rate_limit(domain)
        async with self._semaphore:
            return await asyncio.to_thread(
                self._sync_client.get_status,
                url,
                headers,
                follow_redirects,
                timeout,
            )

    async def get_many(
        self,
        urls: list[str],
        headers: Optional[dict] = None,
        follow_redirects: bool = True,
        timeout: Optional[int] = None,
    ) -> list[tuple[str, Optional[str], Optional[str]]]:
        async def fetch_one(url: str) -> tuple[str, Optional[str], Optional[str]]:
            try:
                html = await self.get(url, headers, follow_redirects, timeout)
                return (url, html, None)
            except Exception as e:
                return (url, None, str(e))

        tasks = [fetch_one(url) for url in urls]
        return await asyncio.gather(*tasks)
