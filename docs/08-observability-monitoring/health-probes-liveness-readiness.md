# Health Checks & Reliability: Liveness vs. Readiness Probes

A naive health check endpoint that simply returns `{"status": "ok"}` is dangerous:
* If your PostgreSQL connection pool is exhausted or Redis is down, the load balancer still thinks the server is healthy and routes users to broken pages!
* If a background worker hangs, the orchestrator never knows to restart it.

Kubernetes and modern load balancers (AWS ALB) require two distinct health probes:

---

## 1. Liveness vs. Readiness Explained Simply

| Probe | Purpose | What It Checks | What Happens If It Fails |
| :--- | :--- | :--- | :--- |
| **Readiness Probe** (`/health/ready`) | Can this pod **accept traffic** right now? | Tests connections to PostgreSQL and Redis. | Load balancer temporarily **removes pod from routing**. |
| **Liveness Probe** (`/health/live`) | Is the Python process **alive or deadlocked**? | Basic internal process responsiveness. | Kubernetes **restarts/kills the container**. |

---

## 2. Production Code Implementations

=== "FastAPI Health Check Router"
    ```python
    from fastapi import APIRouter, status, Depends
    from fastapi.responses import JSONResponse
    from sqlalchemy.ext.asyncio import AsyncSession
    from sqlalchemy import text
    from redis.asyncio import Redis
    from app.core.database import get_db
    from app.core.redis import get_redis

    router = APIRouter(prefix="/health", tags=["Health Checks"])

    @router.get("/live", status_code=status.HTTP_200_OK)
    async def liveness_probe():
        """Fast check to verify the event loop is responsive."""
        return {"status": "alive"}

    @router.get("/ready")
    async def readiness_probe(
        db: AsyncSession = Depends(get_db),
        redis: Redis = Depends(get_redis),
    ):
        """Deep check verifying critical backing infrastructure."""
        checks = {"database": "unknown", "redis": "unknown"}
        is_healthy = True

        # 1. Test PostgreSQL connectivity
        try:
            await db.execute(text("SELECT 1;"))
            checks["database"] = "healthy"
        except Exception as e:
            checks["database"] = f"unhealthy: {str(e)}"
            is_healthy = False

        # 2. Test Redis connectivity
        try:
            await redis.ping()
            checks["redis"] = "healthy"
        except Exception as e:
            checks["redis"] = f"unhealthy: {str(e)}"
            is_healthy = False

        status_code = status.HTTP_200_OK if is_healthy else status.HTTP_503_SERVICE_UNAVAILABLE
        return JSONResponse(
            status_code=status_code,
            content={"status": "ready" if is_healthy else "degraded", "checks": checks},
        )
    ```

=== "Django REST Framework Health View"
    ```python
    from rest_framework.views import APIView
    from rest_framework.response import Response
    from rest_framework import status
    from django.db import connection
    from django.core.cache import cache

    class ReadinessHealthView(APIView):
        permission_classes = [] # Publicly accessible to load balancer

        def get(self, request):
            checks = {}
            is_healthy = True

            # Check DB
            try:
                with connection.cursor() as cursor:
                    cursor.execute("SELECT 1;")
                checks["database"] = "healthy"
            except Exception:
                checks["database"] = "unhealthy"
                is_healthy = False

            # Check Cache
            try:
                cache.set("health_check_test", "1", 10)
                checks["cache"] = "healthy"
            except Exception:
                checks["cache"] = "unhealthy"
                is_healthy = False

            code = status.HTTP_200_OK if is_healthy else status.HTTP_503_SERVICE_UNAVAILABLE
            return Response({"status": "ready" if is_healthy else "degraded", "checks": checks}, status=code)
    ```

