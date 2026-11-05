# Framework Internals: Django vs. FastAPI Under the Hood

To write high-performance backend code, you must understand what happens between the moment an HTTP socket receives bytes and when your view or route handler executes.

---

## 1. Request-Response Lifecycles

```mermaid
flowchart TD
    subgraph DjangoWSGI["Django Request Lifecycle (WSGI / Synchronous)"]
        D1["Web Server (Gunicorn)"] --> D2["WSGIHandler"]
        D2 --> D3["Security & Session Middleware"]
        D3 --> D4["Authentication Middleware (request.user)"]
        D4 --> D5["URL Resolver (urls.py)"]
        D5 --> D6["View / ViewSet"]
        D6 --> D7["Response Middleware & Renderers"]
    end

    subgraph FastAPIASGI["FastAPI Request Lifecycle (ASGI / Asynchronous)"]
        F1["Web Server (Uvicorn)"] --> F2["ASGI Scope & Lifespan"]
        F2 --> F3["Starlette Base Middleware Stack"]
        F3 --> F4["Dependency Injection Graph Resolution (Depends)"]
        F4 --> F5["Pydantic v2 Deserialization & Rust Validation"]
        F5 --> F6["Async Route Handler (async def)"]
        F6 --> F7["Pydantic v2 Serialization & Response"]
    end
```

---

## 2. Django Deep Dive

### Middleware Execution Order
Django middlewares execute **top-to-bottom on the request phase**, and **bottom-to-top on the response phase**:

```python
# settings.py
MIDDLEWARE = [
    "django.middleware.security.SecurityMiddleware",       # 1st in, Last out
    "django.contrib.sessions.middleware.SessionMiddleware", # 2nd in
    "django.middleware.common.CommonMiddleware",
    "django.middleware.csrf.CsrfViewMiddleware",
    "django.contrib.auth.middleware.AuthenticationMiddleware", # Injects request.user
    "myapp.middleware.TenantMiddleware",                  # Custom
]
```

### Writing a Clean Django Middleware (Class-Based)
```python
import time
import logging

logger = logging.getLogger("django.request")

class RequestTimingMiddleware:
    def __init__(self, get_response):
        self.get_response = get_response

    def __call__(self, request):
        # 1. Request processing phase (before view)
        start_time = time.perf_counter()

        response = self.get_response(request)

        # 2. Response processing phase (after view)
        duration = time.perf_counter() - start_time
        response["X-Response-Time-Ms"] = str(round(duration * 1000, 2))
        return response
```

---

## 3. FastAPI Deep Dive

### Lifespan Events (The Modern Startup/Shutdown Standard)
Never use the deprecated `@app.on_event("startup")`. Use the async context manager **`lifespan`**:

```python
from contextlib import asynccontextmanager
from fastapi import FastAPI
from redis.asyncio import Redis

redis_pool: Redis = None

@asynccontextmanager
async def lifespan(app: FastAPI):
    global redis_pool
    # --- STARTUP PHASE ---
    # Initialize connection pools, load ML models, verify DB connections
    redis_pool = Redis.from_url("redis://localhost:6379/0", decode_responses=True)
    await redis_pool.ping()
    app.state.redis = redis_pool
    print("Application Startup: Connection pools established.")

    yield  # Application serves incoming requests here

    # --- SHUTDOWN PHASE ---
    # Gracefully close connections and flush background buffers
    await redis_pool.aclose()
    print("Application Shutdown: Connection pools gracefully closed.")

app = FastAPI(lifespan=lifespan)
```

---

## 4. Dependency Injection (`Depends`) Mechanics in FastAPI

FastAPI builds a **Directed Acyclic Graph (DAG)** of all dependencies required by a route, evaluates them concurrently, caches results within the request scope, and handles cleanup.

### Yield Dependencies for Automatic Cleanup
```python
from fastapi import Depends, HTTPException
from sqlalchemy.ext.asyncio import AsyncSession
from app.core.database import AsyncSessionLocal

async def get_db() -> AsyncSession:
    """
    Yields database session and guarantees closure even if an exception occurs.
    """
    async with AsyncSessionLocal() as session:
        try:
            yield session
            await session.commit()
        except Exception:
            await session.rollback()
            raise
        finally:
            await session.close()
```

---

## 5. Architectural Comparison

| Dimension | Django REST Framework | FastAPI |
| :--- | :--- | :--- |
| **Request Context** | Bound to `request` object (`request.user`, `request.auth`) | Injected via type-annotated `Depends(...)` |
| **Data Validation** | DRF Serializers (`is_valid()`) | Pydantic v2 Models (compiled in Rust) |
| **Startup / Shutdown** | `AppConfig.ready()` signals | `@asynccontextmanager` Lifespan events |
| **Thread Model** | 1 OS thread per request (synchronous WSGI) | Single event loop running thousands of coroutines |

