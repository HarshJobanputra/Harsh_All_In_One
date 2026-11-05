# GraphQL APIs with Strawberry & DataLoader

While REST APIs organize endpoints around fixed resource URLs (`GET /users/1`, `GET /orders`), **GraphQL** exposes a single endpoint (typically `/graphql`) allowing clients to request exactly the fields they need in a single query.

---

## 1. REST vs. GraphQL Trade-Offs

| Dimension | REST API | GraphQL |
| :--- | :--- | :--- |
| **Over-Fetching** | Common (Returns 50 fields when client only needs `name`) | Zero (Client requests only `name`) |
| **Under-Fetching** | Common (Requires 3 roundtrips: `/users/1`, `/orders`, `/products`) | Zero (Single query fetches nested relationships) |
| **HTTP Caching** | Simple & Native (URL + ETag + CDN caching) | Complex (All requests are `POST /graphql`) |
| **File Uploads** | Standard multipart/form-data | Requires GraphQL multipart spec or presigned S3 URLs |

---

## 2. Production GraphQL in Python: Strawberry GraphQL

**Strawberry GraphQL** is the modern Python standard. It uses native dataclasses and Python type annotations instead of legacy custom DSLs.

=== "FastAPI + Strawberry Integration"
    ```python
    import strawberry
    from strawberry.fastapi import GraphQLRouter
    from typing import Optional, list

    @strawberry.type
    class UserType:
        id: int
        username: str
        email: str

    @strawberry.type
    class Query:
        @strawberry.field
        async def user(self, user_id: int) -> Optional[UserType]:
            # Query database
            return UserType(id=user_id, username="alice", email="alice@example.com")

        @strawberry.field
        async def users(self, limit: int = 10) -> list[UserType]:
            return [
                UserType(id=1, username="alice", email="alice@example.com"),
                UserType(id=2, username="bob", email="bob@example.com"),
            ]

    schema = strawberry.Schema(query=Query)
    graphql_app = GraphQLRouter(schema)

    # In FastAPI main.py:
    from fastapi import FastAPI
    app = FastAPI()
    app.include_router(graphql_app, prefix="/graphql")
    ```

=== "Django REST Framework + Strawberry Integration"
    ```python
    # urls.py
    from django.urls import path
    from strawberry.django.views import GraphQLView
    from myapp.schema import schema

    urlpatterns = [
        path("graphql/", GraphQLView.as_view(schema=schema)),
    ]
    ```

---

## 3. The GraphQL N+1 Problem & DataLoader

When a GraphQL client queries:
```graphql
query {
  orders {
    id
    user {
      username # Resolving user on each order causes an N+1 query storm!
    }
  }
}
```

A **DataLoader** batches and deduplicates field lookups across an execution frame, converting 50 individual queries into a single `SELECT * FROM users WHERE id IN (...)`:

```python
from strawberry.dataloader import DataLoader

async def batch_load_users(user_ids: list[int]) -> list[UserType]:
    # Single batched SQL query
    users = await db.execute(select(User).where(User.id.in_(user_ids)))
    user_map = {u.id: u for u in users.scalars()}
    return [user_map.get(uid) for uid in user_ids]

user_loader = DataLoader(load_fn=batch_load_users)

# In resolver:
@strawberry.field
async def user(self, root: "OrderType") -> UserType:
    return await user_loader.load(root.user_id)
```

