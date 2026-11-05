# Bulk Operations & Batching APIs

Executing database queries in a loop (`for item in items: Order.objects.create(...)`) generates $N$ individual network roundtrips to the database, exhausting connection pools and causing massive latency.

Production backends use **Bulk Operations** and **Batch Upserts** (`INSERT ... ON CONFLICT DO UPDATE`) to process thousands of records in a single roundtrip.

---

## 1. Bulk Operations in Django REST Framework

Django ORM provides high-performance bulk primitives:

```python
from myapp.models import Product

# 1. BULK CREATE WITH BATCH SIZING
products_to_create = [
    Product(sku=f"SKU-{i}", name=f"Product {i}", price=19.99)
    for i in range(5000)
]
# batch_size prevents exceeding PostgreSQL query parameter limits
Product.objects.bulk_create(products_to_create, batch_size=1000)

# 2. BULK UPSERT (PostgreSQL ON CONFLICT DO UPDATE)
Product.objects.bulk_create(
    products_to_create,
    batch_size=1000,
    update_conflicts=True,
    unique_fields=["sku"],                 # Conflict target
    update_fields=["name", "price"],       # Fields to overwrite if conflict exists
)

# 3. BULK UPDATE EXISTING RECORDS
for p in existing_products:
    p.price *= 1.10  # 10% price bump

Product.objects.bulk_update(existing_products, fields=["price"], batch_size=1000)
```

> **Crucial Django Caveat**: `bulk_create` and `bulk_update` **do NOT trigger `post_save` signals or call `save()` methods** on individual model instances! If you rely on signals, handle that logic explicitly in your Service Layer.

---

## 2. Bulk Operations in FastAPI (SQLAlchemy 2.0 Async)

SQLAlchemy 2.0 features high-efficiency bulk upserts:

```python
from sqlalchemy.dialects.postgresql import insert
from sqlalchemy.ext.asyncio import AsyncSession
from app.models.product import Product

async def bulk_upsert_products(db: AsyncSession, product_dicts: list[dict]):
    stmt = insert(Product).values(product_dicts)

    # Convert to PostgreSQL ON CONFLICT DO UPDATE
    upsert_stmt = stmt.on_conflict_do_update(
        index_elements=[Product.sku],
        set_={
            "name": stmt.excluded.name,
            "price": stmt.excluded.price,
        },
    )

    await db.execute(upsert_stmt)
    await db.commit()
```

---

## 3. Production Rules for Bulk APIs
* **Cap Payload Size**: Never allow an API client to submit an unbounded array (`POST /api/v1/products/bulk`). Enforce a strict max length (e.g. `max_items = 500`) in your serializer or Pydantic schema.
* **Wrap in Single Transaction**: Always enclose bulk operations inside an atomic transaction block so a failure on the 499th record rolls back cleanly.

