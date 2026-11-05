# Mocking External Services & HTTP Calls (`respx` & `unittest.mock`)

Your automated test suite should **never send real network requests** to third-party providers (Stripe, Twilio, OpenAI, AWS SES).

If third-party APIs have network blips, your tests fail randomly (flaky tests), you consume paid API credits, and your CI pipeline takes 20 minutes instead of 1 minute.

---

## 1. Mocking HTTP Calls with `respx` (For `httpx` in FastAPI)

**`respx`** is an HTTP mocking library for `httpx` that intercepts outbound network calls in-memory:

```python
# tests/test_payment_integration.py
import pytest
import respx
import httpx
from app.services.stripe_service import charge_card

@pytest.mark.asyncio
@respx.mock
async def test_successful_stripe_charge():
    # Intercept outbound POST to Stripe API and return simulated JSON response
    mock_route = respx.post("https://api.stripe.com/v1/charges").mock(
        return_value=httpx.Response(
            status_code=200,
            json={"id": "ch_mock_12345", "status": "succeeded", "amount": 5000},
        )
    )

    # Call your internal service function
    result = await charge_card(amount=50.0, token="tok_visa")

    assert result["id"] == "ch_mock_12345"
    assert result["status"] == "succeeded"
    assert mock_route.called  # Verifies the request actually occurred!
```

---

## 2. Mocking Time & Celery Tasks with `unittest.mock.patch`

```python
from unittest.mock import patch

# Mock out slow background tasks during view tests
@patch("myapp.tasks.send_welcome_email.delay")
def test_user_signup_dispatches_email_task(mock_task, client):
    resp = client.post("/api/v1/signup/", {"email": "alice@example.com", "password": "pass"})
    assert resp.status_code == 201

    # Verify task was enqueued with proper arguments
    mock_task.assert_called_once_with(email="alice@example.com")
```

---

## 3. The 3 Rules of Mocking:
1. **Mock at the Boundary**: Mock the HTTP transport client or external SDK, not your own internal business domain logic.
2. **Always Assert Invocations**: Use `.assert_called_once()` or check payload arguments to verify that your code sent the expected data.
3. **Simulate Errors**: Write tests for network failure modes:
   ```python
   # Test how your system recovers when Stripe times out
   respx.post("https://api.stripe.com/v1/charges").mock(side_effect=httpx.ReadTimeout("Timeout"))
   ```

