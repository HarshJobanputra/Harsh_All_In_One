# Dependency & Configuration Management: Pydantic Settings & Modern Tooling

Hardcoding configuration in code, using loose untyped environment variable lookups (`os.getenv("SECRET")`), or deploying without locked dependencies leads to the infamous *"it worked on my machine"* disaster.

---

## 1. Modern Python Packaging: `uv` & `poetry`

| Tool | Speed | Lockfile Standard | Recommended Use |
| :--- | :--- | :--- | :--- |
| **`uv`** (Astral) | **10-100x faster** (Rust-based) | `uv.lock` | **Modern Standard for 2026 production builds & CI/CD** |
| **`poetry`** | Moderate | `poetry.lock` | Comprehensive library authoring & packaging |
| **`pip` + `pip-tools`** | Slow | `requirements.txt` | Legacy environments |

### Using `uv` in Production:
```bash
# 1. Install uv
curl -LsSf https://astral.sh/uv/install.sh | sh

# 2. Add dependencies with instant lockfile generation
uv add fastapi uvicorn pydantic-settings sqlalchemy asyncpg

# 3. Compile reproducible frozen requirements for Docker
uv pip compile pyproject.toml -o requirements.txt
```

---

## 2. Type-Safe Configuration with Pydantic Settings

The industry standard for application settings across both FastAPI and modern Django projects is **`pydantic-settings`**.

It automatically reads environment variables, converts types (strings to ints, booleans, or lists), validates ranges, and crashes immediately at startup with an informative error if a required secret is missing.

```python
# app/core/config.py
from typing import Literal
from pydantic import Field, PostgresDsn, RedisDsn
from pydantic_settings import BaseSettings, SettingsConfigDict

class AppSettings(BaseSettings):
    model_config = SettingsConfigDict(
        env_file=".env",
        env_file_encoding="utf-8",
        case_sensitive=False,
        extra="ignore",
    )

    # Application
    ENVIRONMENT: Literal["development", "staging", "production"] = "development"
    PROJECT_NAME: str = "All In One Backend API"
    DEBUG: bool = False

    # Security
    SECRET_KEY: str = Field(..., min_length=32, description="Application cryptographic secret")
    ACCESS_TOKEN_EXPIRE_MINUTES: int = 15

    # Databases
    DATABASE_URL: PostgresDsn = Field(..., description="PostgreSQL connection URI")
    REDIS_URL: RedisDsn = Field(default="redis://localhost:6379/0")

    @property
    def is_production(self) -> bool:
        return self.ENVIRONMENT == "production"

# Instantiate singleton settings instance
settings = AppSettings()
```

---

## 3. Environment Separation Strategy

```
project/
├── .env.example            # Committed to Git: Template with dummy keys
├── .env.local              # Git-ignored: Local developer machine settings
├── .env.staging            # Managed via AWS Secrets Manager / CI variables
└── .env.production         # Injected directly into container at runtime
```

### The 12-Factor App Rules for Config:
1. **Never commit `.env` to Git**: Always maintain an up-to-date `.env.example` with clear documentation.
2. **Fail Fast at Startup**: If `DATABASE_URL` is malformed, the app must abort before binding to the HTTP port.
3. **Strict Type Casting**: `DEBUG=False` in bash is a string `"False"`, which standard Python evaluates as truthy (`bool("False") == True`)! `pydantic-settings` correctly converts `"false"` to the boolean `False`.

