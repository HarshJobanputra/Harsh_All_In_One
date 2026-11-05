# API Versioning Strategies & RFC 8594 Safe Deprecation

In production systems, APIs cannot be updated in place if changes break existing mobile apps, third-party partners, or web clients.

---

## 1. Versioning Strategies Comparison

| Strategy | Example | Pros | Cons |
| :--- | :--- | :--- | :--- |
| **URL Path** *(Recommended)* | `GET /api/v1/orders` | Completely explicit, easy to route in Nginx/ALB, cache-friendly. | URL changes for major versions. |
| **Custom Header** | `X-API-Version: 2` | Clean URLs. | Harder to test in browsers, CDN caching requires `Vary: X-API-Version`. |
| **Accept Header** | `Accept: application/vnd.api.v1+json` | Follows REST content-negotiation theory. | High client friction; awkward for mobile/curl. |

---

## 2. Production Code Implementations

=== "FastAPI: Router-Level URL Versioning"
    ```python
    from fastapi import FastAPI, APIRouter

    app = FastAPI()

    # V1 Router
    v1_router = APIRouter(prefix="/api/v1", tags=["V1 Endpoints"])
    @v1_router.get("/users")
    def get_users_v1():
        return [{"id": 1, "name": "Alice Smith"}]

    # V2 Router (Introduced breaking change: split name into first/last)
    v2_router = APIRouter(prefix="/api/v2", tags=["V2 Endpoints"])
    @v2_router.get("/users")
    def get_users_v2():
        return [{"id": 1, "first_name": "Alice", "last_name": "Smith"}]

    app.include_router(v1_router)
    app.include_router(v2_router)
    ```

=== "Django REST Framework: URL & Namespace Versioning"
    ```python
    # urls.py
    from django.urls import path, include

    urlpatterns = [
        path("api/v1/", include(("myapp.api_v1_urls", "myapp"), namespace="v1")),
        path("api/v2/", include(("myapp.api_v2_urls", "myapp"), namespace="v2")),
    ]
    ```

---

## 3. Safe Deprecation with RFC 8594 (`Sunset` Header)

When retiring an old API endpoint, **never turn it off abruptly**.

The official standard is **RFC 8594 (`Sunset` HTTP Header)**, which tells client developers the exact date and time the endpoint will become unresponsive:

```http
HTTP/1.1 200 OK
Content-Type: application/json
Deprecation: @1762300800
Sunset: Wed, 11 Nov 2026 00:00:00 GMT
Link: <https://docs.api.example.com/migration-v1-to-v2>; rel="deprecation"
```

### FastAPI Sunset Middleware
```python
from fastapi import Request
from starlette.middleware.base import BaseHTTPMiddleware

class SunsetDeprecatedEndpointsMiddleware(BaseHTTPMiddleware):
    async def dispatch(self, request: Request, call_next):
        response = await call_next(request)
        # If calling legacy V1 endpoints:
        if request.url.path.startswith("/api/v1/"):
            response.headers["Deprecation"] = "true"
            response.headers["Sunset"] = "Wed, 11 Nov 2026 00:00:00 GMT"
            response.headers["Link"] = '<https://docs.api.com/migration>; rel="deprecation"'
        return response
```

