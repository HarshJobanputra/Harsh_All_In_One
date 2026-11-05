# Database Connection Pooling: PgBouncer, Django & FastAPI

In PostgreSQL, each incoming database connection spawns a **dedicated OS process** consuming 2MB to 10MB of RAM. If 1,000 concurrent client requests hit your API server, attempting to open 1,000 direct database connections will exhaust CPU and RAM, crashing PostgreSQL with:

```
FATAL: remaining connection slots are reserved for non-replication superuser connections
FATAL: sorry, too many clients already
```

---

## 1. Connection Architecture

```mermaid
flowchart TD
    subgraph Clients["Application Web Nodes (Gunicorn / Uvicorn)"]
        W1["Worker 1 (50 coroutines)"]
        W2["Worker 2 (50 coroutines)"]
        W3["Worker 3 (50 coroutines)"]
    end

    subgraph Pooler["PgBouncer Connection Pooler"]
        Pool["Transaction-Mode Pool<br/>(Maintains 25 persistent backend connections)"]
    end

    subgraph Postgres["PostgreSQL Database Server"]
        DB[("PostgreSQL Engine<br/>max_connections = 100")]
    end

    W1 & W2 & W3 -->|Hundreds of short-lived client queries| Pool
    Pool -->|25 reused, persistent server connections| DB
```

---

## 2. Pooling Paradigms: Django vs. FastAPI

### Django (Synchronous Model)
* Django creates a connection per request or worker thread.
* `CONN_MAX_AGE`: Set to a non-zero value (e.g. `60` seconds) to avoid closing and re-opening TCP/TLS handshakes on every single HTTP request.
* **Under High Scale**: Django nodes must connect through an external pooler like **PgBouncer** in **Transaction Pooling mode**.

### FastAPI + SQLAlchemy 2.0 (Async Model)
* Uses `asyncpg` with built-in async connection pools managed by SQLAlchemy `create_async_engine`:
  * `pool_size`: Number of connections permanently kept open (e.g. 20).
  * `max_overflow`: Maximum temporary connections allowed during spikes (e.g. 10).
  * `pool_timeout`: Seconds to wait before throwing a timeout error if all pool connections are busy (e.g. 30).
  * `pool_recycle`: Seconds after which connections are refreshed to avoid stale firewall disconnects (e.g. 1800).

---

## 3. Production Configuration Examples

=== "Django REST Framework (`settings.py` with PgBouncer)"
    ```python
    DATABASES = {
        "default": {
            "ENGINE": "django.db.backends.postgresql",
            "NAME": "production_db",
            "USER": "app_user",
            "PASSWORD": os.environ["DB_PASSWORD"],
            "HOST": "pgbouncer.internal",  # Connect to PgBouncer, not PostgreSQL directly
            "PORT": 6432,                  # Standard PgBouncer port
            "CONN_MAX_AGE": 0,             # Keep 0 when using PgBouncer in transaction mode
            "OPTIONS": {
                "connect_timeout": 5,
            },
        }
    }
    ```

=== "FastAPI (SQLAlchemy 2.0 Async Engine Setup)"
    ```python
    from sqlalchemy.ext.asyncio import create_async_engine, async_sessionmaker, AsyncSession

    DATABASE_URL = "postgresql+asyncpg://app_user:secret@localhost:5432/production_db"

    engine = create_async_engine(
        DATABASE_URL,
        pool_size=20,            # 20 persistent connections
        max_overflow=10,         # 10 burst connections
        pool_timeout=30,         # 30s timeout
        pool_recycle=1800,       # Recycle connections every 30 mins
        pool_pre_ping=True,      # Tests connection liveness before handing it to a request
        echo=False,              # Disable SQL echoing in production
    )

    AsyncSessionLocal = async_sessionmaker(
        bind=engine,
        class_=AsyncSession,
        expire_on_commit=False,
    )

    async def get_db() -> AsyncSession:
        async with AsyncSessionLocal() as session:
            try:
                yield session
            finally:
                await session.close()
    ```

---

## 4. PgBouncer Modes: Session vs. Transaction vs. Statement

| PgBouncer Mode | How Connection is Allocated | Prepared Statements Supported? | Best For |
| :--- | :--- | :--- | :--- |
| **Session** | Assigned to client for the entire connection duration | Yes | Low concurrency legacy apps |
| **Transaction** (Recommended) | Assigned only during an active transaction (`BEGIN` to `COMMIT`) | Requires special config or server-side pooling | **High-throughput web APIs** |
| **Statement** | Assigned per single SQL query (Transactions prohibited) | No | Pure read-only analytics |

