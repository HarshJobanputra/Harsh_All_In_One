# Distributed Locks (Redlock) & The Saga Pattern

In distributed microservices, standard database transactions cannot span across independent database boundaries. 

Two critical patterns solve this:
1. **Distributed Locks**: Coordinating access to shared resources across multiple API server instances.
2. **The Saga Pattern**: Executing multi-step business transactions across distributed services with automated compensating rollbacks.

---

## 1. Distributed Locking with Redis (Redlock & Fencing Tokens)

To prevent two worker instances from running the same scheduled cron job or billing the same customer at once:

```mermaid
sequenceDiagram
    autonumber
    participant Worker1 as Worker Node 1
    participant Redis as Redis
    participant Worker2 as Worker Node 2

    Worker1->>Redis: SET lock:payout:2026 "unique_uuid_1" NX EX 30
    Redis-->>Worker1: OK (Lock acquired!)
    Worker2->>Redis: SET lock:payout:2026 "unique_uuid_2" NX EX 30
    Redis-->>Worker2: (nil) (Lock busy! Worker 2 aborts or waits)

    Note over Worker1: Executes batch payout...
    Worker1->>Redis: Atomic Lua Script: Delete lock ONLY if value == "unique_uuid_1"
```

### The Critical Safe Release Lua Script:
Never use plain `redis.delete(key)` to release a lock! If Worker 1 ran slowly and its lock expired, a naive delete will accidentally delete Worker 2's new lock! Use an atomic Lua script:

```lua
if redis.call("get", KEYS[1]) == ARGV[1] then
    return redis.call("del", KEYS[1])
else
    return 0
end
```

---

## 2. The Saga Pattern & Compensating Transactions

Suppose a customer checks out:
1. **Order Service**: Creates order.
2. **Payment Service**: Charges credit card.
3. **Inventory Service**: Deducts warehouse stock.

If **Step 3 (Inventory) fails** because the item is out of stock, how do we rollback Step 2 (Payment)? We cannot execute an SQL `ROLLBACK` on an external credit card!

The solution is a **Compensating Transaction**: an explicit business action that undoes the forward step (e.g., executing a **Refund**).

```mermaid
sequenceDiagram
    autonumber
    participant Saga as Saga Orchestrator
    participant Order as Order Service
    participant Pay as Payment Service
    participant Inv as Inventory Service

    Saga->>Order: 1. Create Pending Order (Success)
    Saga->>Pay: 2. Charge Card $100 (Success)
    Saga->>Inv: 3. Reserve Stock (FAILED: Out of Stock!)
    
    Note over Saga: Triggering Compensating Rollbacks!
    Saga->>Pay: 4. COMPENSATE: Refund Card $100
    Saga->>Order: 5. COMPENSATE: Mark Order as CANCELLED
```

