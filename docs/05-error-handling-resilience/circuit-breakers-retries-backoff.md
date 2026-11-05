# Circuit Breakers, Retries & Exponential Backoff

When your backend communicates with external dependencies (payment gateways, third-party APIs, LLM providers, microservices), network failures are inevitable.

Naive retry loops without backoff create the **Thundering Herd problem** and can crash an already struggling downstream service. Waiting indefinitely on a hanging service exhausts thread pools and causes **cascading failures**.

---

## 1. The Circuit Breaker Pattern

```mermaid
stateDiagram-v2
    [*] --> Closed: Normal Operation

    Closed --> Open: Failure threshold exceeded (e.g. 5 consecutive errors)
    note right of Open: All calls immediately fail fast without hitting dependency!
    
    Open --> HalfOpen: Reset timeout expires (e.g. after 30 seconds)
    note right of HalfOpen: Probe: Allow limited trial calls
    
    HalfOpen --> Closed: Trial calls succeed (Service recovered)
    HalfOpen --> Open: Trial calls fail (Stay in Open)
```

* **Closed**: Requests pass through normally. Failures are counted.
* **Open**: If failure threshold is reached, the circuit trips. All incoming requests **fail fast immediately** (or return fallback data) without wasting resources calling the broken dependency.
* **Half-Open**: After a cooling period, a small percentage of test requests are allowed through to verify if the external service has recovered.

---

## 2. Exponential Backoff with Jitter

When retrying temporary network glitches (e.g. HTTP 503 or connection timeouts):
$$\text{Delay} = \min(\text{MaxDelay}, \text{BaseDelay} \times 2^{\text{attempt}}) + \text{random\_jitter}$$

* **Why Jitter is Crucial**: If 1,000 requests fail simultaneously at 12:00:00, without randomized jitter, all 1,000 requests will retry at the exact same millisecond (e.g. at 12:00:02), triggering a self-inflicted DDoS attack on your own infrastructure.

---

## 3. Production Code Implementations

=== "Python Tenacity (Exponential Backoff with Full Jitter)"
    ```python
    import httpx
    from tenacity import retry, stop_after_attempt, wait_random_exponential, retry_if_exception_type

    @retry(
        # Stop after 4 attempts
        stop=stop_after_attempt(4),
        # Wait exponentially: min 1s, max 10s, with randomized jitter
        wait=wait_random_exponential(multiplier=1, max=10),
        # Only retry on network transport errors or 5xx server responses
        retry=retry_if_exception_type((httpx.ConnectTimeout, httpx.ReadTimeout, httpx.NetworkError)),
        reraise=True,
    )
    async def fetch_external_exchange_rate(currency: str) -> dict:
        async with httpx.AsyncClient(timeout=3.0) as client:
            response = await client.get(f"https://api.forex.internal/v1/rates/{currency}")
            response.raise_for_status()
            return response.json()
    ```

=== "FastAPI (Circuit Breaker with `pybreaker`)"
    ```python
    import pybreaker
    import httpx
    from fastapi import APIRouter, HTTPException, status

    # Trip circuit after 5 failures; attempt recovery after 30 seconds
    payment_breaker = pybreaker.CircuitBreaker(fail_max=5, reset_timeout=30)

    router = APIRouter()

    @router.post("/process-charge")
    async def process_payment(amount: float):
        try:
            # Wrap the external call with the breaker
            @payment_breaker
            def call_external_gateway():
                # External synchronous or wrapped HTTP call
                resp = httpx.post("https://payment-provider.com/charge", json={"amount": amount}, timeout=3.0)
                resp.raise_for_status()
                return resp.json()

            return call_external_gateway()

        except pybreaker.CircuitBreakerError:
            # Circuit is OPEN: Fail fast without waiting on timeout!
            raise HTTPException(
                status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
                detail="Payment gateway is currently experiencing outages. Please retry in 1 minute.",
            )
        except httpx.HTTPError:
            raise HTTPException(
                status_code=status.HTTP_502_BAD_GATEWAY,
                detail="Payment provider failed to process request.",
            )
    ```

