# REST API Standards & Unified Response Envelope

A hallmark of mature enterprise APIs is **predictability**. Frontend applications, mobile clients, and external API consumers should not have to parse different response schemas depending on which endpoint they call.

---

## 1. Unified Response Envelope Schema

Every successful API response should adhere to a standard envelope structure containing payload `data` and contextual `meta`:

```json
{
  "success": true,
  "data": {
    "id": "ord_98765",
    "total_amount": "150.00",
    "status": "COMPLETED"
  },
  "meta": {
    "request_id": "req_01HX9B4P10K93A8B",
    "timestamp": "2026-11-05T14:30:00Z"
  }
}
```

For paginated collections:
```json
{
  "success": true,
  "data": [...],
  "pagination": {
    "next_cursor": "ZXlKaGJHY2lPaUpTV",
    "has_more": true,
    "limit": 20
  },
  "meta": {
    "request_id": "req_01HX9B4P10K93A8B"
  }
}
```

---

## 2. Production Code Implementations

=== "Django REST Framework (Custom Renderer & Response Helper)"
    ```python
    # core/renderers.py
    from rest_framework.renderers import JSONRenderer

    class StandardJSONRenderer(JSONRenderer):
        def render(self, data, accepted_media_type=None, renderer_context=None):
            response = renderer_context.get("response") if renderer_context else None
            status_code = response.status_code if response else 200
            request = renderer_context.get("request") if renderer_context else None
            request_id = getattr(request, "correlation_id", "unknown")

            # Do not re-wrap if already formatted or binary
            if isinstance(data, dict) and ("success" in data or "type" in data):
                return super().render(data, accepted_media_type, renderer_context)

            is_success = 200 <= status_code < 300
            envelope = {
                "success": is_success,
                "data": data if is_success else None,
                "error": None if is_success else data,
                "meta": {
                    "request_id": request_id,
                }
            }
            return super().render(envelope, accepted_media_type, renderer_context)
    ```

=== "FastAPI (Generic Generic Pydantic Envelope & Middleware)"
    ```python
    # app/schemas/envelope.py
    from typing import Generic, TypeVar, Optional, Any
    from pydantic import BaseModel
    from datetime import datetime, timezone

    T = TypeVar("T")

    class MetaInfo(BaseModel):
        request_id: str
        timestamp: datetime = datetime.now(timezone.utc)

    class APIResponse(BaseModel, Generic[T]):
        success: bool = True
        data: Optional[T] = None
        error: Optional[Any] = None
        meta: MetaInfo

    # Usage in Route:
    from fastapi import APIRouter, Request
    from app.schemas.user import UserRead

    router = APIRouter()

    @router.get("/users/{user_id}", response_model=APIResponse[UserRead])
    async def get_user(user_id: int, request: Request):
        user_data = UserRead(id=user_id, email="alice@example.com")
        return APIResponse(
            success=True,
            data=user_data,
            meta=MetaInfo(request_id=request.state.correlation_id),
        )
    ```

---

## 3. HTTP Methods & Idempotency Rules

| HTTP Method | CRUD Action | Idempotent? | Safe? | Expected Success Code |
| :--- | :--- | :--- | :--- | :--- |
| **GET** | Read | ✅ Yes | ✅ Yes | `200 OK` |
| **POST** | Create / Action | ❌ No | ❌ No | `201 Created` or `202 Accepted` |
| **PUT** | Replace (Full) | ✅ Yes | ❌ No | `200 OK` or `204 No Content` |
| **PATCH** | Partial Update | ❌ Usually (Can be) | ❌ No | `200 OK` |
| **DELETE** | Delete | ✅ Yes | ❌ No | `204 No Content` or `200 OK` |

