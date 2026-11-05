# Production Multi-Stage Dockerfiles for Python

Naive Dockerfiles result in images exceeding 1.5 GB in size, bundle unnecessary build compilers (GCC, headers) into production, run as the insecure `root` user, and mishandle POSIX termination signals (`SIGTERM`).

A production-grade Python Docker image should:
1. Use **Multi-stage builds** to discard compiler tools.
2. Run as a **non-root user** (`appuser`).
3. Leverage **`dumb-init`** or `tini` as PID 1 to ensure graceful shutdown when Kubernetes or Docker terminates the container.
4. Keep the image under **150 MB**.

---

## 1. Production Dockerfile (FastAPI & Django)

```dockerfile
# ==========================================
# Stage 1: Build & Dependencies Compiler
# ==========================================
FROM python:3.12-slim-bookworm AS builder

# Prevent Python from writing .pyc and buffering stdout
ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1

WORKDIR /install

# Install build dependencies required for compiling C-extensions
RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential \
    libpq-dev \
    && rm -rf /var/lib/apt/lists/*

COPY requirements.txt .

# Install dependencies into a separate wheels directory
RUN pip install --no-cache-dir --prefix=/install/wheels -r requirements.txt


# ==========================================
# Stage 2: Minimal Production Runtime
# ==========================================
FROM python:3.12-slim-bookworm AS runner

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PATH="/install/wheels/bin:$PATH"

WORKDIR /app

# Install only minimal runtime libraries (libpq for postgres) and dumb-init
RUN apt-get update && apt-get install -y --no-install-recommends \
    libpq5 \
    dumb-init \
    curl \
    && rm -rf /var/lib/apt/lists/*

# Copy installed Python packages from builder
COPY --from=builder /install/wheels /usr/local

# Create non-root user and group
RUN groupadd -g 10001 appgroup && \
    useradd -u 10001 -g appgroup -s /bin/bash -m appuser

# Copy application source code
COPY . /app

# Set ownership
RUN chown -R appuser:appgroup /app

# Switch to non-root user
USER appuser

EXPOSE 8000

# Use dumb-init as PID 1 to handle SIGTERM / SIGINT gracefully
ENTRYPOINT ["dumb-init", "--"]

# Production ASGI server command
CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8000", "--workers", "4"]
```

---

## 2. Docker Best Practices
* **`.dockerignore`**: Always exclude `.git`, `__pycache__`, `.venv`, `.env`, and test files from the build context.
* **Health Check Directive**: Include an internal health check instruction:
  ```dockerfile
  HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
      CMD curl -f http://localhost:8000/health/live || exit 1
  ```

