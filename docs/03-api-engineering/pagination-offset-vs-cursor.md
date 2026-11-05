# API Pagination: Offset vs. Keyset (Cursor-Based)

Pagination is mandatory on all collection endpoints to prevent clients from fetching millions of records in a single query.

However, choosing between **Offset/Limit** pagination and **Keyset/Cursor** pagination has profound performance and UX implications.

---

## 1. Why Offset Pagination Fails at Scale

In traditional Offset pagination:
```sql
SELECT * FROM transactions ORDER BY created_at DESC LIMIT 20 OFFSET 500000;
```

PostgreSQL must read, sort, and discard all **500,000 previous rows** from disk and memory before returning the 20 requested records.

As the offset increases:
* Execution time explodes from **2ms** to **several seconds**.
* Database CPU and buffer cache thrash.
* **The "Page Drift" Bug**: If new records are inserted while a user scrolls from page 1 to page 2, records shift down, causing the user to see duplicate entries or miss items completely.

---

## 2. Keyset (Cursor-Based) Pagination: $O(1)$ Speed

Instead of an arbitrary page number, the client receives a **Cursor** (typically an opaque, base64-encoded pointer containing the last seen values, such as `(created_at, id)`).

The query becomes:
```sql
SELECT * FROM transactions
WHERE (created_at, id) < ('2026-11-05 14:00:00', 987654)
ORDER BY created_at DESC, id DESC
LIMIT 20;
```

PostgreSQL uses a B-Tree composite index `idx_created_id` to jump directly to the target record in **$O(1)$ constant time**, whether you are on the 1st page or the 10,000th page!

---

## 3. Comparison Matrix

| Feature | Offset / Limit | Keyset / Cursor |
| :--- | :--- | :--- |
| **Performance on Large Datasets** | $O(N)$ (Degrades severely) | $O(1)$ (Consistently fast) |
| **Page Drift (Duplicates/Missed)** | ❌ Yes (Common bug) | ✅ Immune |
| **Jump to Arbitrary Page (Page 42)** | ✅ Supported | ❌ Sequential next/prev only |
| **Ideal Use Case** | Small datasets, Admin tables | Infinite scroll feeds, mobile apps, high-volume APIs |

---

## 4. Production Code Implementations

=== "Django REST Framework (CursorPagination)"
    ```python
    from rest_framework.pagination import CursorPagination
    from rest_framework import viewsets
    from myapp.models import Transaction
    from myapp.serializers import TransactionSerializer

    class TransactionCursorPagination(CursorPagination):
        page_size = 25
        page_size_query_param = "limit"
        max_page_size = 100
        # Must be ordered by an indexed unique combination
        ordering = "-created_at"

    class TransactionViewSet(viewsets.ReadOnlyModelViewSet):
        queryset = Transaction.objects.all()
        serializer_class = TransactionSerializer
        pagination_class = TransactionCursorPagination
    ```

=== "FastAPI (SQLAlchemy 2.0 Async Keyset Helper)"
    ```python
    import base64
    import json
    from datetime import datetime
    from typing import Optional
    from sqlalchemy import select
    from sqlalchemy.ext.asyncio import AsyncSession
    from app.models.transaction import Transaction

    def encode_cursor(created_at: datetime, record_id: int) -> str:
        data = {"created_at": created_at.isoformat(), "id": record_id}
        return base64.urlsafe_b64encode(json.dumps(data).encode()).decode()

    def decode_cursor(cursor_str: str) -> tuple[datetime, int]:
        raw = base64.urlsafe_b64decode(cursor_str.encode()).decode()
        data = json.loads(raw)
        return datetime.fromisoformat(data["created_at"]), data["id"]

    async def get_transactions_cursor(
        db: AsyncSession,
        limit: int = 20,
        cursor: Optional[str] = None,
    ):
        stmt = select(Transaction).order_by(Transaction.created_at.desc(), Transaction.id.desc())

        if cursor:
            last_date, last_id = decode_cursor(cursor)
            # Tuple comparison supported natively in PostgreSQL
            stmt = stmt.where(
                (Transaction.created_at < last_date) |
                ((Transaction.created_at == last_date) & (Transaction.id < last_id))
            )

        stmt = stmt.limit(limit + 1)  # Fetch limit + 1 to check if has_more exists
        result = await db.execute(stmt)
        rows = result.scalars().all()

        has_more = len(rows) > limit
        items = rows[:limit]

        next_cursor = None
        if has_more and items:
            last_item = items[-1]
            next_cursor = encode_cursor(last_item.created_at, last_item.id)

        return {"items": items, "next_cursor": next_cursor, "has_more": has_more}
    ```

