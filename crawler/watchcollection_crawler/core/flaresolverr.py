import os
from typing import Optional

import requests
from bs4 import BeautifulSoup

FLARESOLVERR_URL = os.getenv("FLARESOLVERR_URL", "http://localhost:8191/v1")


class FlareSolverrClient:
    def __init__(self, base_url: str = FLARESOLVERR_URL):
        self.base_url = base_url
        self.session_id: Optional[str] = None
        self._http = requests.Session()

    def create_session(self, timeout: int = 30) -> str:
        resp = self._http.post(
            self.base_url,
            json={"cmd": "sessions.create"},
            timeout=timeout,
        )
        data = resp.json()
        if data.get("status") == "ok":
            self.session_id = data.get("session")
            return self.session_id
        raise RuntimeError(f"Failed to create session: {data}")

    def ensure_session(self, timeout: int = 30) -> Optional[str]:
        if self.session_id:
            return self.session_id
        return self.create_session(timeout=timeout)

    def destroy_session(self, timeout: int = 30) -> None:
        if self.session_id:
            self._http.post(
                self.base_url,
                json={"cmd": "sessions.destroy", "session": self.session_id},
                timeout=timeout,
            )
            self.session_id = None

    def request(
        self,
        url: str,
        max_timeout: int = 60000,
        headers: Optional[dict] = None,
        retry_on_crash: bool = True,
    ) -> dict:
        http_timeout = (max_timeout / 1000) + 30
        payload = {
            "cmd": "request.get",
            "url": url,
            "maxTimeout": max_timeout,
        }
        if self.session_id:
            payload["session"] = self.session_id
        if headers:
            payload["headers"] = headers

        try:
            resp = self._http.post(self.base_url, json=payload, timeout=http_timeout)
            data = resp.json()
        except Exception as exc:
            raise RuntimeError(f"FlareSolverr error: {exc}") from exc

        if data.get("status") == "ok":
            return data.get("solution", {})

        message = data.get("message", "Unknown error")
        lower_message = message.lower()
        if retry_on_crash and ("tab crashed" in lower_message or "session not found" in lower_message):
            self.destroy_session()
            self.create_session()
            return self.request(
                url,
                max_timeout=max_timeout,
                headers=headers,
                retry_on_crash=False,
            )

        raise RuntimeError(f"FlareSolverr error: {message}")

    def get(self, url: str, max_timeout: int = 60000, headers: Optional[dict] = None) -> str:
        solution = self.request(url, max_timeout=max_timeout, headers=headers)
        return solution.get("response", "")

    def get_soup(self, url: str, max_timeout: int = 60000, headers: Optional[dict] = None) -> BeautifulSoup:
        html = self.get(url, max_timeout=max_timeout, headers=headers)
        return BeautifulSoup(html, "html.parser")
