# Structured JSON Logging & Distributed Correlation IDs

In production microservices and high-throughput monoliths, traditional human-formatted log lines (e.g. `2026-11-05 ERROR User failed to login`) are almost impossible to query, filter, or aggregate in tools like Datadog, Grafana Loki, or AWS CloudWatch.

Production systems enforce **Structured JSON Logging** tagged with a unique **Correlation ID** (or Request ID) carried across every log statement in a request lifecycle.

---

## 1. What a Production JSON Log Looks Like

```json
{
  "timestamp": "2026-11-05T14:45:10.123Z",
  "level": "INFO",
  "logger": "app.services.payment",
  "message": "Payment charged successfully",
  "correlation_id": "corr_01HX9B4P10K93A8B",
  "user_id": 4921,
  "tenant_id": "9b1deb4d-3b7d-4bad-9bdd-2b0d7b3dcb6d",
  "duration_ms": 142.5,
  "http": {
    "method": "POST",
    "route": "/api/v1/payments/charge",
    "status_code": 201
  }
}
```

---

## 2. Propagating Correlation IDs with Python `contextvars`

Python's standard `threading.local()` fails in asynchronous frameworks like FastAPI because multiple coroutines share the same thread.

The standard solution is **`contextvars`**, which safely isolates state across async tasks, threads, and coroutines.

---

## 3. Production Code Implementations

=== "FastAPI (Async Correlation ID Middleware with Structlog)"
    ```python
    import uuid
    from contextvars import ContextVar
    from fastapi import FastAPI, Request
    import structlog

    # Define context variable
    correlation_id_ctx: ContextVar[str] = ContextVar("correlation_id", default="")

    app = FastAPI()

    # Configure structlog to output clean JSON
    structlog.configure(
        processors=[
            structlog.contextvars.merge_contextvars,
            structlog.processors.add_log_level,
            structlog.processors.TimeStamper(fmt="iso"),
            structlog.processors.JSONRenderer(),
        ]
    )
    logger = structlog.get_logger()

    @app.middleware("http")
    async def correlation_id_middleware(request: Request, call_next):
        # Read from incoming header or generate new UUID
        corr_id = request.headers.get("X-Correlation-ID", str(uuid.uuid4()))
        correlation_id_ctx.set(corr_id)
        request.state.correlation_id = corr_id

        # Bind to structlog context
        structlog.contextvars.bind_contextvars(
            correlation_id=corr_id,
            path=request.url.path,
            method=request.method,
        )

        response = await call_next(request)
        # Echo correlation ID back to the client
        response.headers["X-Correlation-ID"] = corr_id
        return response
    ```

=== "Django REST Framework (Correlation Middleware)"
    ```python
    import uuid
    import logging
    from asgiref.local import Local

    _thread_locals = Local()

    class CorrelationIDMiddleware:
        def __init__(self, get_response):
            self.get_response = get_response

        def __call__(self, request):
            corr_id = request.headers.get("X-Correlation-ID", str(uuid.uuid4()))
            _thread_locals.correlation_id = corr_id
            request.correlation_id = corr_id

            response = self.get_response(request)
            response["X-Correlation-ID"] = corr_id
            return response

    class CorrelationLogFilter(logging.Filter):
        def filter(self, record):
            record.correlation_id = getattr(_thread_locals, "correlation_id", "none")
            return True
    ```

---

## 4. PII Redaction & Security
* **Never Log Raw Passwords, Credit Cards, or Tokens**: Write custom log processors or filters that redact keys matching `password`, `token`, `secret`, `authorization`, `credit_card`.

