# Database Schema Design & Indexing Strategies

Proper schema design and strategic indexing are the single highest leverage factors in backend performance. A poorly indexed query on a table with 10 million rows will trigger an entire table scan (taking seconds or minutes), while an indexed lookup runs in sub-milliseconds ($O(\log N)$).

---

## 1. Index Types in PostgreSQL

| Index Type | Internal Structure | Best Used For | Example Use Case |
| :--- | :--- | :--- | :--- |
| **B-Tree** (Default) | Balanced Tree | Equality (`=`), Range (`<`, `>`, `BETWEEN`), Sorting (`ORDER BY`) | Primary keys, timestamps, status fields |
| **GIN** (Generalized Inverted Index) | Inverted Index | JSONB queries, Arrays, Full-Text Search | `payload->>'event_name'`, `tags @> ARRAY['python']` |
| **Hash** | Hash Table | High-throughput exact equality only (`=`) | UUID / hash lookups (rarely preferred over B-tree) |
| **BRIN** (Block Range Index) | Min/Max per block range | Massive append-only time-series tables (gigabytes/terabytes) | Sensor logs, audit trails ordered by timestamp |

---

## 2. Advanced Indexing Patterns

### Composite Indexes & Column Ordering
When creating an index across multiple columns `(tenant_id, status, created_at)`:
* The **Leftmost Prefix Rule** applies:
  * ✅ Can filter by `(tenant_id)`
  * ✅ Can filter by `(tenant_id, status)`
  * ✅ Can filter by `(tenant_id, status, created_at)`
  * ❌ Cannot use index if filtering only by `(status)` or `(created_at)` alone!
* **Rule of Thumb**: Put high-cardinality equality columns first, followed by range/sort columns.

### Partial Indexes
Save index size and maintenance cost by indexing only active rows:
```sql
CREATE INDEX idx_pending_orders ON orders(created_at) WHERE status = 'PENDING';
```

---

## 3. Production Code Implementations

=== "Django REST Framework"
    ```python
    from django.db import models
    from django.contrib.postgres.indexes import GinIndex, BTreeIndex

    class Order(models.Model):
        tenant_id = models.UUIDField(db_index=True)
        user = models.ForeignKey("accounts.User", on_delete=models.PROTECT)
        status = models.CharField(max_length=32)
        metadata = models.JSONField(default=dict)
        created_at = models.DateTimeField(auto_now_add=True)

        class Meta:
            indexes = [
                # Composite index for tenant-scoped filtering and sorting
                models.Index(
                    fields=["tenant_id", "status", "-created_at"],
                    name="idx_tenant_status_created"
                ),
                # Partial index: Only index active/pending orders
                models.Index(
                    fields=["created_at"],
                    name="idx_pending_orders_created",
                    condition=models.Q(status="PENDING"),
                ),
                # GIN index for high-performance JSONB querying
                GinIndex(fields=["metadata"], name="idx_order_metadata_gin"),
            ]
    ```

=== "FastAPI (SQLAlchemy 2.0)"
    ```python
    from sqlalchemy import Column, Integer, String, DateTime, Index, text
    from sqlalchemy.dialects.postgresql import UUID, JSONB
    from app.core.database import Base

    class Order(Base):
        __tablename__ = "orders"

        id = Column(Integer, primary_key=True)
        tenant_id = Column(UUID(as_uuid=True), nullable=False)
        status = Column(String(32), nullable=False)
        metadata_payload = Column(JSONB, default=dict)
        created_at = Column(DateTime(timezone=True), server_default=text("now()"))

        __table_args__ = (
            # Composite index
            Index("idx_orders_tenant_status_created", "tenant_id", "status", text("created_at DESC")),
            # Partial index
            Index(
                "idx_orders_pending",
                "created_at",
                postgresql_where=(status == "PENDING"),
            ),
            # GIN index on JSONB
            Index("idx_orders_metadata_gin", "metadata_payload", postgresql_using="gin"),
        )
    ```

---

## 4. Query Profiling & `EXPLAIN ANALYZE`
Never guess whether your index is being used. Run `EXPLAIN (ANALYZE, BUFFERS)` in PostgreSQL:
* **Seq Scan (Sequential Scan)**: ❌ PostgreSQL scanned the entire table row-by-row.
* **Index Scan / Bitmap Index Scan**: ✅ PostgreSQL used the index to locate matching pages instantly.

