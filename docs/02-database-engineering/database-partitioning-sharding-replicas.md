# Database Scaling: Read Replicas, Partitioning & Sharding

When a database grows beyond a single server's capacity or when read traffic spikes (e.g. 95% reads vs 5% writes), scaling requires architectural partitioning rather than simply buying a bigger server.

---

## 1. The Scaling Hierarchy

```mermaid
flowchart TD
    Step1["1. Single Primary Database (ACID)"] --> Step2["2. Primary + Read Replicas (Read/Write Splitting)"]
    Step2 --> Step3["3. Declarative Table Partitioning (Single DB, Multiple Tables)"]
    Step3 --> Step4["4. Sharding / Citus (Multiple DB Servers Distributed)"]
```

---

## 2. Read Replicas & Primary/Replica Routing

In most web applications, **reads outnumber writes 10 to 1**. 

By deploying read-only replica databases via PostgreSQL streaming replication:
* **Primary (Leader)**: Handles all `INSERT`, `UPDATE`, `DELETE` writes and transactions.
* **Replicas (Followers)**: Handle read-only `SELECT` queries across load-balanced nodes.

### Replication Lag Warning
Replication to followers is typically asynchronous. If a user creates an order and is immediately redirected to view it, reading from a lagging replica might return a 404! 
**Rule**: Always read from the Primary for 5 seconds after a user executes a write (or use sticky session routing).

---

## 3. Production Code Implementations

=== "Django REST Framework: Database Router"
    ```python
    # core/db_router.py
    class PrimaryReplicaRouter:
        def db_for_read(self, model, **hints):
            # Send all reads to replica
            return "replica"

        def db_for_write(self, model, **hints):
            # Send all writes to primary
            return "default"

        def allow_relation(self, obj1, obj2, **hints):
            return True

        def allow_migrate(self, db, app_label, model_name=None, **hints):
            # Only run schema migrations on primary
            return db == "default"

    # settings.py
    DATABASE_ROUTERS = ["core.db_router.PrimaryReplicaRouter"]
    ```

=== "FastAPI / SQLAlchemy 2.0: Dynamic Session Routing"
    ```python
    from sqlalchemy.ext.asyncio import create_async_engine, AsyncSession, async_sessionmaker

    primary_engine = create_async_engine("postgresql+asyncpg://user:pass@primary-db:5432/app")
    replica_engine = create_async_engine("postgresql+asyncpg://user:pass@replica-db:5432/app")

    PrimarySession = async_sessionmaker(primary_engine, expire_on_commit=False)
    ReplicaSession = async_sessionmaker(replica_engine, expire_on_commit=False)

    async def get_read_db() -> AsyncSession:
        async with ReplicaSession() as session:
            yield session

    async def get_write_db() -> AsyncSession:
        async with PrimarySession() as session:
            yield session
    ```

---

## 4. PostgreSQL Declarative Table Partitioning

When a single table reaches tens of millions of rows (e.g. `audit_logs`, `metrics`, `orders`), B-Tree indexes no longer fit in RAM.

**Partitioning** divides one logical table into smaller physical tables (e.g., one partition per month or per year). When querying, PostgreSQL performs **Partition Pruning**, searching only the relevant partition table.

```sql
-- Create parent partitioned table
CREATE TABLE audit_logs (
    id BIGSERIAL,
    user_id INT NOT NULL,
    action VARCHAR(64) NOT NULL,
    created_at TIMESTAMPTZ NOT NULL,
    PRIMARY KEY (id, created_at)
) PARTITION BY RANGE (created_at);

-- Create monthly partitions
CREATE TABLE audit_logs_2026_01 PARTITION OF audit_logs
    FOR VALUES FROM ('2026-01-01') TO ('2026-02-01');

CREATE TABLE audit_logs_2026_02 PARTITION OF audit_logs
    FOR VALUES FROM ('2026-02-01') TO ('2026-03-01');
```

When you query:
```sql
SELECT * FROM audit_logs WHERE created_at >= '2026-01-15' AND created_at < '2026-01-20';
```
PostgreSQL automatically scans *only* `audit_logs_2026_01`, completely ignoring all other years of data!

