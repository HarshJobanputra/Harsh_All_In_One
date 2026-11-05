# CI/CD Automation with GitHub Actions

A production backend repository should never rely on manual deployments. Every pull request must pass automated quality gates (linting, type checking, unit tests, security scans), and merges to `main` should trigger automated container builds and zero-downtime deployments.

---

## 1. CI Pipeline Architecture

```mermaid
flowchart LR
    GitPush["Git Push / PR"] --> Lint["1. Ruff Lint & Format"]
    Lint --> Types["2. Mypy Strict Typecheck"]
    Types --> Tests["3. Pytest with Postgres & Redis Services"]
    Tests --> Security["4. Trivy / Bandit Security Audit"]
    Security --> Deploy["5. Build & Push Docker Image to ECR / GHCR"]
```

---

## 2. Production GitHub Actions Workflow

```yaml
# .github/workflows/ci.yml
name: Backend Production CI

on:
  push:
    branches: [main]
  pull_request:
    branches: [main]

jobs:
  test:
    runs-on: ubuntu-latest

    services:
      postgres:
        image: postgres:16-alpine
        env:
          POSTGRES_DB: test_db
          POSTGRES_USER: test_user
          POSTGRES_PASSWORD: secret_password
        ports:
          - 5432:5432
        options: >-
          --health-cmd pg_isready
          --health-interval 10s
          --health-timeout 5s
          --health-retries 5

      redis:
        image: redis:7-alpine
        ports:
          - 6379:6379
        options: >-
          --health-cmd "redis-cli ping"
          --health-interval 10s
          --health-timeout 5s
          --health-retries 5

    steps:
      - name: Checkout Code
        uses: actions/checkout@v4

      - name: Set up Python 3.12
        uses: actions/setup-python@v5
        with:
          python-version: "3.12"
          cache: "pip"

      - name: Install Dependencies
        run: |
          python -m pip install --upgrade pip
          pip install ruff mypy pytest pytest-asyncio pytest-cov
          pip install -r requirements.txt

      - name: Run Ruff (Linter & Formatter)
        run: ruff check .

      - name: Run Mypy (Type Safety)
        run: mypy app/

      - name: Run Pytest with Coverage
        env:
          DATABASE_URL: postgresql+asyncpg://test_user:secret_password@localhost:5432/test_db
          REDIS_URL: redis://localhost:6379/0
        run: |
          pytest --cov=app --cov-report=xml --cov-fail-under=85
```

---

## 3. Production Deployment Rules
* **Enforce Branch Protection**: Nobody pushes directly to `main`. Require at least 1 approving code review and all green CI checks.
* **Database Migrations First**: In rolling deployments, ensure database migrations are **backward-compatible** (e.g. adding columns as nullable first before populating them in code).

