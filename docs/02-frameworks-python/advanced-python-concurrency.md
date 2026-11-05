# Advanced Python for Backend Engineers

Writing production-grade backend systems in Django or FastAPI requires mastering the core Python primitives that power framework internals: **Decorators**, **Generators**, **Context Managers**, **Dunder Methods**, and **`asyncio` fundamentals**.

---

## 1. Custom Decorators (Parameterized & Metadata-Preserving)

Decorators wrap functions to add cross-cutting behavior (authentication, caching, metrics, timing) without altering the function's internal logic.

### The Golden Rule: Always Use `functools.wraps`
If you forget `@functools.wraps(func)`, the decorated function loses its `__name__`, `__doc__`, and type annotations, breaking FastAPI route reflection and debugging tools.

=== "Production Decorator with Arguments & Timing"
    ```python
    import functools
    import time
    import logging
    from typing import Callable, Any

    logger = logging.getLogger("performance")

    def measure_time(threshold_seconds: float = 0.5) -> Callable:
        """
        Decorator that logs a warning if a function execution
        exceeds the specified threshold in seconds.
        """
        def decorator(func: Callable) -> Callable:
            @functools.wraps(func)
            def wrapper(*args: Any, **kwargs: Any) -> Any:
                start = time.perf_counter()
                try:
                    return func(*args, **kwargs)
                finally:
                    duration = time.perf_counter() - start
                    if duration > threshold_seconds:
                        logger.warning(
                            f"SLOW FUNCTION: '{func.__name__}' took {duration:.3f}s "
                            f"(Threshold: {threshold_seconds}s)"
                        )
            return wrapper
        return decorator

    # Usage:
    @measure_time(threshold_seconds=1.0)
    def calculate_heavy_report(org_id: int):
        ...
    ```

---

## 2. Generators & Streaming Memory Efficiency

When processing 1,000,000 records from a database or file, loading them into a list `[x for x in records]` consumes gigabytes of RAM and crashes the server with Out-Of-Memory (OOM).

**Generators** yield items one-by-one, keeping memory consumption at $O(1)$ constant time (~few kilobytes).

=== "Streaming Large Datasets with Generators"
    ```python
    from typing import Generator
    import csv

    def stream_large_csv(file_path: str) -> Generator[dict, None, None]:
        """
        Memory-safe reader: Only 1 line is held in RAM at any given time.
        """
        with open(file_path, mode="r", encoding="utf-8") as f:
            reader = csv.DictReader(f)
            for row in reader:
                yield row

    # Usage:
    for record in stream_large_csv("massive_export.csv"):
        process_single_record(record)
    ```

---

## 3. Context Managers (`__enter__` & `__exit__` / `contextlib`)

Context managers guarantee safe resource cleanup (closing database connections, releasing Redis locks, resetting temporary settings) even if an unhandled exception occurs.

=== "Custom Redis Mutex Lock Context Manager"
    ```python
    from contextlib import contextmanager
    import time
    import redis

    redis_client = redis.Redis.from_url("redis://localhost:6379/0")

    @contextmanager
    def distributed_lock(lock_key: str, expire_seconds: int = 10):
        """
        Guarantees lock acquisition and automatic release.
        """
        acquired = redis_client.set(lock_key, "locked", nx=True, ex=expire_seconds)
        if not acquired:
            raise RuntimeError(f"Could not acquire lock for key: {lock_key}")
        try:
            yield
        finally:
            redis_client.delete(lock_key)

    # Usage:
    with distributed_lock("payouts:batch:2026"):
        execute_payout_routine()
    ```

---

## 4. `asyncio` Fundamentals: Tasks, Gather & Semaphores

In FastAPI, multiple coroutines can run concurrently. But launching 1,000 tasks at once will hammer external APIs or exhaust file descriptors. Use **`asyncio.Semaphore`** to bound concurrency.

```python
import asyncio
import httpx

async def fetch_item(client: httpx.AsyncClient, item_id: int, semaphore: asyncio.Semaphore):
    # Limits concurrent requests to maximum 10 at any given millisecond
    async with semaphore:
        resp = await client.get(f"https://api.external.com/items/{item_id}")
        return resp.json()

async def fetch_all_items(item_ids: list[int]):
    semaphore = asyncio.Semaphore(10)  # Max 10 concurrent requests
    async with httpx.AsyncClient(timeout=5.0) as client:
        tasks = [fetch_item(client, i, semaphore) for i in item_ids]
        # return_exceptions=True prevents one failed request from cancelling all others
        results = await asyncio.gather(*tasks, return_exceptions=True)
        return results
```

---

## 5. Production Checklist
- [ ] Every custom decorator uses `@functools.wraps`.
- [ ] Large file or database iterations use `yield` (generators) instead of loading lists into memory.
- [ ] External resource cleanups are wrapped in `try...finally` or context managers.
- [ ] Unbounded `asyncio.gather(*tasks)` is avoided; concurrency is always bounded using `asyncio.Semaphore`.

