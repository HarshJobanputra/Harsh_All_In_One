# Pytest Masterclass: Fixtures, Async Tests & Test Pyramids

Writing backend tests gives you the confidence to refactor code, deploy to production on Friday afternoon, and upgrade Python or framework versions without fear.

---

## 1. The Backend Test Pyramid

```mermaid
flowchart TD
    E2E["1. End-to-End Tests (10%)<br/>Full flow across real DB, Redis, and network."]
    Integration["2. Integration Tests (30%)<br/>API routes hitting real PostgreSQL test database with transactions."]
    Unit["3. Unit Tests (60%)<br/>Pure Python business logic, calculations, and domain services. Zero DB/network. Sub-millisecond!"]

    Unit --> Integration --> E2E
```

---

## 2. Pytest Fixture Architecture (`conftest.py`)

A fixture provides a reproducible, isolated baseline for tests (e.g. creating a test user, authenticating an HTTP client, or setting up a database session).

=== "FastAPI Test Setup with `httpx.AsyncClient` & `ASGITransport`"
    ```python
    # tests/conftest.py
    import pytest
    from httpx import AsyncClient, ASGITransport
    from sqlalchemy.ext.asyncio import create_async_engine, async_sessionmaker, AsyncSession
    from app.main import app
    from app.core.database import Base, get_db

    TEST_DB_URL = "postgresql+asyncpg://test_user:pass@localhost:5432/test_db"

    @pytest.fixture(scope="session")
    async def engine():
        engine = create_async_engine(TEST_DB_URL)
        async with engine.begin() as conn:
            await conn.run_sync(Base.metadata.create_all)
        yield engine
        async with engine.begin() as conn:
            await conn.run_sync(Base.metadata.drop_all)
        await engine.dispose()

    @pytest.fixture
    async def db_session(engine):
        connection = await engine.connect()
        trans = await connection.begin()
        session_factory = async_sessionmaker(connection, class_=AsyncSession, expire_on_commit=False)
        session = session_factory()

        yield session

        # Roll back transaction after each test -> Zero test pollution!
        await session.close()
        await trans.rollback()
        await connection.close()

    @pytest.fixture
    async def client(db_session):
        # Override get_db dependency with test database session
        app.dependency_overrides[get_db] = lambda: db_session
        transport = ASGITransport(app=app)
        async with AsyncClient(transport=transport, base_url="http://test") as ac:
            yield ac
        app.dependency_overrides.clear()
    ```

=== "Django REST Framework Test Setup"
    ```python
    # tests/conftest.py
    import pytest
    from rest_framework.test import APIClient
    from myapp.models import User

    @pytest.fixture
    def api_client():
        return APIClient()

    @pytest.fixture
    def authenticated_client(api_client, db):
        user = User.objects.create_user(username="testuser", email="test@example.com", password="password123")
        api_client.force_authenticate(user=user)
        api_client.user = user
        return api_client
    ```

---

## 3. Parametrized Testing: Testing Multiple Cases Cleanly

Never copy-paste identical tests with different inputs. Use `@pytest.mark.parametrize`:

```python
import pytest

@pytest.mark.parametrize(
    "email, password, expected_status",
    [
        ("valid@example.com", "StrongPassword123!", 201),
        ("invalid-email", "StrongPassword123!", 422),
        ("valid@example.com", "short", 422), # Too short password
        ("", "", 422),                       # Empty inputs
    ],
)
async def test_user_registration_validation(client, email, password, expected_status):
    resp = await client.post("/api/v1/auth/register", json={"email": email, "password": password})
    assert resp.status_code == expected_status
```

