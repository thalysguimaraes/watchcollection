import os
import time
from datetime import datetime
from typing import Optional, List, Dict, Any

import requests


class TheWatchAPIClient:
    BASE_URL = "https://api.thewatchapi.com"

    def __init__(
        self,
        api_token: str,
        rate_limit_rpm: int = 60,
        session: Optional[requests.Session] = None,
    ) -> None:
        self.api_token = api_token
        self._min_interval = 60.0 / rate_limit_rpm if rate_limit_rpm > 0 else 0
        self._last_request: float = 0.0
        self._http = session or requests.Session()

    @classmethod
    def from_env(
        cls,
        api_token: Optional[str] = None,
        rate_limit_rpm: int = 60,
        session: Optional[requests.Session] = None,
    ) -> "TheWatchAPIClient":
        token = api_token or os.getenv("THEWATCHAPI_API_KEY")
        if not token:
            raise ValueError("THEWATCHAPI_API_KEY environment variable not set")
        return cls(api_token=token, rate_limit_rpm=rate_limit_rpm, session=session)

    def close(self) -> None:
        self._http.close()

    def _rate_limit(self) -> None:
        if self._min_interval > 0:
            elapsed = time.time() - self._last_request
            if elapsed < self._min_interval:
                time.sleep(self._min_interval - elapsed)
        self._last_request = time.time()

    def _get(self, path: str, params: Optional[Dict[str, Any]] = None, timeout: float = 30.0) -> Dict[str, Any]:
        self._rate_limit()
        url = f"{self.BASE_URL}{path}"
        req_params = {"api_token": self.api_token}
        if params:
            req_params.update(params)
        resp = self._http.get(url, params=req_params, timeout=timeout)
        resp.raise_for_status()
        return resp.json()

    def list_brands(self) -> List[str]:
        data = self._get("/v1/brand/list")
        return data.get("data", [])

    def list_references(self, brand: str) -> List[str]:
        data = self._get("/v1/reference/list", params={"brand": brand})
        return data.get("data", [])

    def get_price_history(
        self,
        reference_number: str,
        date_from: Optional[str] = None,
        date_to: Optional[str] = None,
    ) -> List[Dict[str, Any]]:
        params: Dict[str, Any] = {"reference_number": reference_number}
        if date_from:
            params["date_from"] = date_from
        if date_to:
            params["date_to"] = date_to
        data = self._get("/v1/reference/price/history", params=params)
        return data.get("data", [])


def parse_price_date(date_str: str) -> Optional[int]:
    if not date_str:
        return None
    clean = date_str.split(".")[0].rstrip("Z")
    for fmt in ("%Y-%m-%dT%H:%M:%S", "%Y-%m-%d"):
        try:
            dt = datetime.strptime(clean, fmt)
            return int(dt.timestamp())
        except ValueError:
            continue
    return None
