import os
import time
from typing import Optional, Tuple

import requests

DEFAULT_BRIGHTDATA_ENDPOINT = "https://api.brightdata.com/request"
DEFAULT_BRIGHTDATA_FORMAT = "raw"
DEFAULT_RATE_LIMIT_RPM = 1000


def resolve_brightdata_env(
    api_key: Optional[str] = None,
    zone: Optional[str] = None,
    endpoint: Optional[str] = None,
    response_format: Optional[str] = None,
) -> Tuple[Optional[str], Optional[str], str, str]:
    api_key = api_key or os.getenv("BRIGHTDATA_API_KEY") or os.getenv("BRIGHTDATA_WEB_ACCESS_KEY")
    zone = zone or os.getenv("BRIGHTDATA_WEB_ACCESS_ZONE") or os.getenv("BRIGHTDATA_ZONE")
    endpoint = endpoint or os.getenv("BRIGHTDATA_ENDPOINT") or DEFAULT_BRIGHTDATA_ENDPOINT
    response_format = response_format or os.getenv("BRIGHTDATA_FORMAT") or DEFAULT_BRIGHTDATA_FORMAT
    return api_key, zone, endpoint, response_format


class BrightDataClient:
    def __init__(
        self,
        api_key: str,
        zone: str,
        endpoint: str = DEFAULT_BRIGHTDATA_ENDPOINT,
        response_format: str = DEFAULT_BRIGHTDATA_FORMAT,
        session: Optional[requests.Session] = None,
        rate_limit_rpm: int = DEFAULT_RATE_LIMIT_RPM,
    ) -> None:
        self.api_key = api_key
        self.zone = zone
        self.endpoint = endpoint
        self.response_format = response_format
        self._http = session or requests.Session()
        self._min_interval = 60.0 / rate_limit_rpm if rate_limit_rpm > 0 else 0
        self._last_request_time: float = 0

    @classmethod
    def has_env(cls, api_key: Optional[str] = None, zone: Optional[str] = None) -> bool:
        resolved_key, resolved_zone, _, _ = resolve_brightdata_env(api_key=api_key, zone=zone)
        return bool(resolved_key) and bool(resolved_zone)

    @classmethod
    def from_env(
        cls,
        api_key: Optional[str] = None,
        zone: Optional[str] = None,
        endpoint: Optional[str] = None,
        response_format: Optional[str] = None,
        session: Optional[requests.Session] = None,
    ) -> "BrightDataClient":
        resolved_key, resolved_zone, resolved_endpoint, resolved_format = resolve_brightdata_env(
            api_key=api_key,
            zone=zone,
            endpoint=endpoint,
            response_format=response_format,
        )
        if not resolved_key or not resolved_zone:
            raise ValueError("Bright Data API key and zone are required")
        return cls(
            api_key=resolved_key,
            zone=resolved_zone,
            endpoint=resolved_endpoint,
            response_format=resolved_format,
            session=session,
        )

    def close(self) -> None:
        self._http.close()

    def _rate_limit(self) -> None:
        if self._min_interval > 0:
            elapsed = time.time() - self._last_request_time
            if elapsed < self._min_interval:
                time.sleep(self._min_interval - elapsed)
        self._last_request_time = time.time()

    def request(self, url: str, headers: Optional[dict] = None, timeout: float = 60.0) -> requests.Response:
        self._rate_limit()
        payload = {
            "zone": self.zone,
            "url": url,
            "format": self.response_format,
        }
        if headers:
            payload["headers"] = headers
        resp = self._http.post(
            self.endpoint,
            json=payload,
            headers={"Authorization": f"Bearer {self.api_key}"},
            timeout=timeout,
        )
        return resp

    def get(self, url: str, headers: Optional[dict] = None, timeout: float = 60.0) -> str:
        resp = self.request(url, headers=headers, timeout=timeout)
        content_type = resp.headers.get("content-type", "").lower()
        if "application/json" in content_type:
            try:
                data = resp.json()
            except ValueError:
                data = None
            if isinstance(data, dict):
                for key in ("response", "body", "data"):
                    if isinstance(data.get(key), str):
                        return data[key]
                error = data.get("error") or data.get("message")
                if error:
                    raise RuntimeError(f"Bright Data API error: {error}")
        return resp.text
