# Dynamic Filtering, Multi-Column Sorting & Full-Text Search

Production APIs must allow clients to search, filter, and sort collections without exposing the database to arbitrary SQL injection or generating unindexed, slow table scans.

---

## 1. Dynamic Filtering & Ordering Patterns

=== "Django REST Framework (`django-filter`)"
    ```python
    import django_filters
    from myapp.models import Order
    from rest_framework import viewsets, filters

    class OrderFilter(django_filters.FilterSet):
        min_amount = django_filters.NumberFilter(field_name="total_amount", lookup_expr="gte")
        max_amount = django_filters.NumberFilter(field_name="total_amount", lookup_expr="lte")
        status = django_filters.ChoiceFilter(choices=Order.Status.choices)
        created_after = django_filters.DateTimeFilter(field_name="created_at", lookup_expr="gte")

        class Meta:
            model = Order
            fields = ["status", "min_amount", "max_amount", "created_after"]

    class OrderViewSet(viewsets.ReadOnlyModelViewSet):
        queryset = Order.objects.all()
        filterset_class = OrderFilter
        filter_backends = [django_filters.rest_framework.DjangoFilterBackend, filters.OrderingFilter]
        # Whitelist allowed sorting fields to prevent unindexed sort attacks!
        ordering_fields = ["created_at", "total_amount"]
        ordering = ["-created_at"]
    ```

=== "FastAPI + SQLAlchemy 2.0 Dynamic Query Builder"
    ```python
    from typing import Optional
    from decimal import Decimal
    from datetime import datetime
    from fastapi import APIRouter, Depends, Query
    from sqlalchemy import select
    from sqlalchemy.ext.asyncio import AsyncSession
    from app.models.order import Order

    router = APIRouter(prefix="/orders", tags=["Orders"])

    @router.get("/")
    async def list_orders(
        db: AsyncSession = Depends(get_db),
        status: Optional[str] = None,
        min_amount: Optional[Decimal] = None,
        order_by: str = Query(default="-created_at", regex="^(-?created_at|-?total_amount)$"),
    ):
        query = select(Order)

        # Dynamic filters
        if status:
            query = query.where(Order.status == status)
        if min_amount is not None:
            query = query.where(Order.total_amount >= min_amount)

        # Dynamic safe sorting
        descending = order_by.startswith("-")
        col_name = order_by.lstrip("-")
        col = getattr(Order, col_name)
        query = query.order_by(col.desc() if descending else col.asc())

        result = await db.execute(query.limit(50))
        return result.scalars().all()
    ```

---

## 2. Typo-Tolerant Search with PostgreSQL Trigram Similarity

Standard SQL `LIKE '%query%'` cannot use regular B-Tree indexes and crashes on large datasets.

The industry solution in PostgreSQL is **Trigram Similarity (`pg_trgm`)**, which enables typo-tolerant fuzzy matching indexed via **GIN**:

```sql
-- 1. Enable extension
CREATE EXTENSION IF NOT EXISTS pg_trgm;

-- 2. Create GIN trigram index on searchable fields
CREATE INDEX idx_products_name_trgm ON products USING gin (name gin_trgm_ops);

-- 3. Query with similarity ranking (matches "ipone" to "iPhone")
SELECT id, name, similarity(name, 'ipone') AS score
FROM products
WHERE name % 'ipone'
ORDER BY score DESC
LIMIT 10;
```

