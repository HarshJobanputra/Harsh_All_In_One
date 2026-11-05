# RFC 7807: Problem Details for Standardized API Errors

When an API call fails in production, returning inconsistent errors (sometimes a string `"Bad Request"`, sometimes HTML error pages from an unhandled 500, sometimes an ad-hoc dictionary) causes frontend applications to crash or display broken generic alerts.

The IETF **RFC 7807** specification establishes a uniform schema for HTTP error responses.

---

## 1. RFC 7807 Error Schema

```json
{
  "type": "https://api.yourdomain.com/errors/insufficient-balance",
  "title": "Insufficient Funds",
  "status": 400,
  "detail": "Your wallet balance of $40.00 is insufficient for a $60.00 transaction.",
  "instance": "/api/v1/wallets/123/debit",
  "code": "WALLET_INSUFFICIENT_FUNDS",
  "trace_id": "corr_01HXA7B39Y",
  "invalid_params": [
    {
      "name": "amount",
      "reason": "Exceeds available balance"
    }
  ]
}
```

* **`type`**: URI reference identifying the error type.
* **`title`**: Short, human-readable summary.
* **`status`**: HTTP status code.
* **`detail`**: Detailed explanation specific to this occurrence.
* **`instance`**: URI identifying the specific request resource.
* **`trace_id`**: Correlation ID allowing the user or support engineer to look up the exact server log in Sentry/Datadog.

---

## 2. Production Code Implementations

=== "Django REST Framework (Global Exception Handler)"
    ```python
    from rest_framework.views import exception_handler
    from rest_framework.response import Response
    from rest_framework import status
    import uuid

    def rfc7807_exception_handler(exc, context):
        response = exception_handler(exc, context)
        request = context.get("request")
        trace_id = getattr(request, "correlation_id", str(uuid.uuid4()))
        instance_path = request.path if request else ""

        if response is not None:
            # Format validation or DRF errors into RFC 7807
            rfc_payload = {
                "type": f"https://api.example.com/errors/{exc.__class__.__name__.lower()}",
                "title": getattr(exc, "default_detail", "Bad Request"),
                "status": response.status_code,
                "detail": str(exc.detail) if hasattr(exc, "detail") else str(exc),
                "instance": instance_path,
                "trace_id": trace_id,
                "invalid_params": response.data if isinstance(response.data, (dict, list)) else None,
            }
            return Response(rfc_payload, status=response.status_code)

        # Unhandled 500 crash -> Never expose raw stack traces in production!
        return Response({
            "type": "https://api.example.com/errors/internal-server-error",
            "title": "Internal Server Error",
            "status": status.HTTP_500_INTERNAL_SERVER_ERROR,
            "detail": "An unexpected error occurred. Please quote the trace_id to support.",
            "instance": instance_path,
            "trace_id": trace_id,
        }, status=status.HTTP_500_INTERNAL_SERVER_ERROR)
    ```

=== "FastAPI (Global Custom Exception Handlers)"
    ```python
    from fastapi import FastAPI, Request, status
    from fastapi.responses import JSONResponse
    from fastapi.exceptions import RequestValidationError
    from pydantic import BaseModel
    from typing import Optional, Any

    app = FastAPI()

    class RFC7807Error(BaseModel):
        type: str
        title: str
        status: int
        detail: str
        instance: str
        trace_id: str
        invalid_params: Optional[Any] = None

    @app.exception_handler(RequestValidationError)
    async def validation_exception_handler(request: Request, exc: RequestValidationError):
        trace_id = getattr(request.state, "correlation_id", "unknown")
        error_body = RFC7807Error(
            type="https://api.example.com/errors/validation-error",
            title="Request Validation Failed",
            status=status.HTTP_422_UNPROCESSABLE_ENTITY,
            detail="One or more fields failed schema validation.",
            instance=str(request.url.path),
            trace_id=trace_id,
            invalid_params=exc.errors(),
        )
        return JSONResponse(status_code=422, content=error_body.model_dump())
    ```

