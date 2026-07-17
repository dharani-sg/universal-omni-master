# Network Code Policy — UOM Free-Tier API Client

All network client code in this project MUST follow this policy.

## Requirements

### 1. HTTP Client

- Use `urllib.request` (stdlib) or `requests` if available.
- Set `User-Agent: UOM/0.29.0` on all requests.
- Set `Accept: application/json` unless endpoint requires otherwise.
- Connection timeout: 30s. Read timeout: 60s.
- Never disable SSL verification.

### 2. Retry Logic

- Max retries: 3 (exponential backoff: 1s, 2s, 4s).
- Retry on: 429, 500, 502, 503, 504.
- Do NOT retry on: 400, 401, 403, 404, 422.
- Respect `Retry-After` header when present.

### 3. Rate Limiting / Pacing

- Enforce minimum 100ms between requests.
- Track request count per 60s window (max: 100 req/min).
- If quota exhausted, sleep for window reset rather than failing immediately.

### 4. Concurrency

- Max concurrent requests: 3 (use `threading.Semaphore`).
- All requests share a single connection pool.

### 5. Logging

- Log: timestamp, method, URL, status code, latency, retry count.
- Use `logging` module, level INFO, format: `[%(asctime)s] %(levelname)s %(message)s`.
- Never log request bodies or auth headers.

### 6. Error Handling

- On quota exhaustion (429): wait `Retry-After`, retry remaining budget.
- On retry exhaustion: raise `APIExhaustedError(message, status, retries)`.
- On unexpected error: log, raise `APIError(message, status)`.
- Return `None` for 404 (not found) instead of raising.

### 7. Response Handling

- Always check `response.status_code` before parsing body.
- Parse JSON response body with `json.loads()`.
- Return `None` for empty bodies.

### 8. API Key / Auth

- This project uses FREE TIER endpoints only.
- No API keys required. No auth headers.
- If an endpoint requires auth, raise `AuthRequiredError`.

## Example Usage

```python
import api_wrapper

client = api_wrapper.FreeTierClient(base_url="https://api.example.com/v1")
result = client.get("/status")
print(result)
```
