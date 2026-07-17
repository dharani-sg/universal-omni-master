#!/usr/bin/env python3
"""UOM Free-Tier API Client — implements NETWORK_CODE_POLICY.md exactly."""

import json
import logging
import threading
import time
import urllib.error
import urllib.request
from typing import Any, Optional

logging.basicConfig(
    level=logging.INFO,
    format="[%(asctime)s] %(levelname)s %(message)s",
    datefmt="%Y-%m-%dT%H:%M:%S",
)
logger = logging.getLogger("uom-api")


class APIError(Exception):
    def __init__(self, message: str, status: int = 0):
        self.message = message
        self.status = status
        super().__init__(message)


class APIExhaustedError(APIError):
    def __init__(self, message: str, status: int = 0, retries: int = 0):
        self.retries = retries
        super().__init__(message, status)


class AuthRequiredError(APIError):
    def __init__(self, message: str = "Endpoint requires authentication"):
        super().__init__(message, 401)


RETRYABLE_CODES = {429, 500, 502, 503, 504}
NON_RETRYABLE_CODES = {400, 401, 403, 404, 422}
BACKOFF_BASE = 1
MAX_RETRIES = 3
MIN_REQUEST_INTERVAL = 0.1
MAX_REQUESTS_PER_MINUTE = 100
MAX_CONCURRENT = 3


class FreeTierClient:
    def __init__(self, base_url: str):
        self.base_url = base_url.rstrip("/")
        self._semaphore = threading.Semaphore(MAX_CONCURRENT)
        self._lock = threading.Lock()
        self._request_times: list[float] = []
        self._last_request_time = 0.0

    def _pacing(self):
        with self._lock:
            now = time.time()
            elapsed = now - self._last_request_time
            if elapsed < MIN_REQUEST_INTERVAL:
                time.sleep(MIN_REQUEST_INTERVAL - elapsed)
            window_start = time.time() - 60
            self._request_times = [t for t in self._request_times if t > window_start]
            if len(self._request_times) >= MAX_REQUESTS_PER_MINUTE:
                sleep_time = self._request_times[0] - window_start
                logger.info("Rate limit: sleeping %.1fs", sleep_time)
                time.sleep(sleep_time)
            self._request_times.append(time.time())
            self._last_request_time = time.time()

    def _request(self, method: str, path: str, data: Optional[bytes] = None) -> Optional[dict]:
        url = f"{self.base_url}{path}"
        headers = {
            "User-Agent": "UOM/0.29.0",
            "Accept": "application/json",
        }
        retries = 0
        while True:
            self._pacing()
            self._semaphore.acquire()
            try:
                start = time.time()
                req = urllib.request.Request(url, data=data, headers=headers, method=method)
                try:
                    resp = urllib.request.urlopen(req, timeout=90)
                    status = resp.getcode()
                    body = resp.read().decode("utf-8")
                    latency = time.time() - start
                    logger.info("%s %s %d %.3fs r=%d", method, path, status, latency, retries)
                    if status == 404:
                        return None
                    if not body:
                        return None
                    return json.loads(body)
                except urllib.error.HTTPError as e:
                    status = e.code
                    latency = time.time() - start
                    logger.info("%s %s %d %.3fs r=%d", method, path, status, latency, retries)
                    if status == 404:
                        return None
                    if status in NON_RETRYABLE_CODES:
                        if status == 401:
                            raise AuthRequiredError(f"Auth required: {path}")
                        raise APIError(f"HTTP {status}: {path}", status)
                    if status in RETRYABLE_CODES:
                        if retries >= MAX_RETRIES:
                            raise APIExhaustedError(
                                f"Retries exhausted: {path}", status, retries
                            )
                        retry_after = int(e.headers.get("Retry-After", BACKOFF_BASE * (2 ** retries)))
                        logger.info("Retry %d/%d after %ds", retries + 1, MAX_RETRIES, retry_after)
                        time.sleep(retry_after)
                        retries += 1
                        continue
                    raise APIError(f"HTTP {status}: {path}", status)
                except urllib.error.URLError as e:
                    raise APIError(f"Connection error: {e.reason}", 0)
            finally:
                self._semaphore.release()

    def get(self, path: str) -> Optional[dict]:
        return self._request("GET", path)

    def post(self, path: str, data: dict) -> Optional[dict]:
        body = json.dumps(data).encode("utf-8")
        return self._request("POST", path, data=body)

    def put(self, path: str, data: dict) -> Optional[dict]:
        body = json.dumps(data).encode("utf-8")
        return self._request("PUT", path, data=body)

    def delete(self, path: str) -> Optional[dict]:
        return self._request("DELETE", path)


if __name__ == "__main__":
    BASE_URL = "https://api.example.com/v1"
    client = FreeTierClient(base_url=BASE_URL)

    try:
        result = client.get("/status")
        if result is not None:
            print(f"Status: {result}")
        else:
            print("Status: not found")
    except APIExhaustedError as e:
        print(f"Failed after {e.retries} retries: {e.message}")
    except APIError as e:
        print(f"Error ({e.status}): {e.message}")
    except AuthRequiredError as e:
        print(f"Auth required: {e.message}")
    except Exception as e:
        print(f"Unexpected: {e}")
