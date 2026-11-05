# ACID Transactions & Database Isolation Levels

Relational databases like PostgreSQL guarantee **ACID properties**: **Atomicity**, **Consistency**, **Isolation**, and **Durability**.

However, under concurrent traffic, database engines balance data correctness against query performance using **Isolation Levels**. Choosing the wrong isolation level leads to subtle bugs like **Phantom Reads**, **Non-Repeatable Reads**, and **Deadlocks**.

---

## 1. Concurrency Anomalies Explained Simply

```mermaid
flowchart TD
    Anomalies["Concurrency Read Phenomena"]
    Anomalies --> A1["1. Dirty Read:<br/>Reading uncommitted data from another transaction that might rollback."]
    Anomalies --> A2["2. Non-Repeatable Read:<br/>Querying the same row twice in one transaction yields different values because another transaction committed an update."]
    Anomalies --> A3["3. Phantom Read:<br/>Executing a range query twice returns different sets of rows because another transaction inserted or deleted records."]
    Anomalies --> A4["4. Serialization Anomaly:<br/>A group of concurrent transactions results in a state impossible to achieve by running them sequentially."]
```

---

## 2. Standard SQL Isolation Levels vs. PostgreSQL Reality

| Isolation Level | Dirty Read? | Non-Repeatable Read? | Phantom Read? | PostgreSQL Implementation |
| :--- | :--- | :--- | :--- | :--- |
| **Read Uncommitted** | Possible in standard SQL | Possible | Possible | *(PostgreSQL automatically upgrades this to Read Committed)* |
| **Read Committed** (Default) | ❌ Prevented | Possible | Possible | Each query in a transaction sees a snapshot of data committed *before that specific query began*. |
| **Repeatable Read** | ❌ Prevented | ❌ Prevented | ❌ Prevented *(in PG)* | Entire transaction sees a consistent snapshot taken *at the start of the transaction*. |
| **Serializable** (Strict) | ❌ Prevented | ❌ Prevented | ❌ Prevented | Full serializable isolation via SSI (Serializable Snapshot Isolation). Aborts on conflicts. |

---

## 3. Production Code: Setting Isolation Levels

=== "Django REST Framework"
    ```python
    from django.db import transaction

    # Using atomic with standard Read Committed
    with transaction.atomic():
        # Code here executes in single atomic block
        ...

    # For strict Serializable transactions in PostgreSQL:
    from django.db import connection

    def execute_serializable_transfer(source_id: int, dest_id: int, amount: float):
        with transaction.atomic():
            with connection.cursor() as cursor:
                # Set transaction isolation for this transaction block
                cursor.execute("SET TRANSACTION ISOLATION LEVEL SERIALIZABLE;")

            # Execute transfer
            ...
    ```

=== "FastAPI + SQLAlchemy 2.0 Async"
    ```python
    from sqlalchemy.ext.asyncio import create_async_engine, AsyncSession
    from sqlalchemy import text

    # Global engine level isolation config:
    engine = create_async_engine(
        "postgresql+asyncpg://user:pass@localhost:5432/db",
        isolation_level="REPEATABLE READ", # Can set engine default
    )

    # Per-transaction execution options in FastAPI:
    async def run_strict_transaction(session: AsyncSession):
        async with session.begin():
            # Override for this specific critical transaction
            await session.connection(
                execution_options={"isolation_level": "SERIALIZABLE"}
            )
            # Transaction logic here...
    ```

---

## 4. Deadlock Detection & Prevention

A **Deadlock** occurs when:
* Transaction A locks Row 1, and wants to lock Row 2.
* Transaction B locks Row 2, and wants to lock Row 1.
* Neither transaction can proceed; both wait forever.

```mermaid
sequenceDiagram
    autonumber
    participant T1 as Transaction 1
    participant DB as PostgreSQL Lock Manager
    participant T2 as Transaction 2

    T1->>DB: Locks Row A
    T2->>DB: Locks Row B
    T1->>DB: Tries to lock Row B (Blocked! Waits for T2)
    T2->>DB: Tries to lock Row A (Blocked! Waits for T1)
    Note over DB: Deadlock detected! PostgreSQL terminates one transaction with ERROR 40P01.
```

### The Universal Rule to Eliminate Deadlocks:
> **Always acquire locks in a consistent, deterministic order.** If modifying multiple items, sort their IDs ascending (`ORDER BY id ASC`) before locking.

