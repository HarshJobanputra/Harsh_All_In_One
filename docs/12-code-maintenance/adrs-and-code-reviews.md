# Architecture Decision Records (ADRs) & Code Review Standards

Six months after an architect leaves the team, why is the database structured this way? Why did we pick Kafka instead of RabbitMQ? Why did we introduce an outbox pattern?

Without **Architecture Decision Records (ADRs)**, software teams suffer from collective amnesia, repeatedly arguing over settled decisions or accidentally undoing intentional design choices.

---

## 1. What is an ADR?

An **Architecture Decision Record (ADR)** is a lightweight markdown document capturing an architectural decision, the business context that motivated it, and the trade-offs accepted.

### Standard ADR Template (stored in `/docs/adrs/`):
```markdown
# ADR 004: Adoption of PostgreSQL Row-Level Security for Multi-Tenancy

## Status
Accepted (Date: 2026-11-05)

## Context
Our B2B SaaS application requires strict tenant isolation. In the current setup, developers must manually add `.filter(tenant_id=...)` to every ORM query. If an engineer forgets this filter, tenant data is leaked. We evaluated:
1. Separate Database per Tenant (High cloud cost, complex migrations).
2. Schema-per-Tenant (Max 2,000 tenants before PostgreSQL performance degrades).
3. Shared Schema with Row-Level Security (RLS).

## Decision
We will use PostgreSQL Row-Level Security (RLS) on all tenant-owned tables. The tenant context will be set on the database session via middleware (`SET LOCAL app.current_tenant = :id`).

## Consequences
### Positive:
* Data isolation is enforced at the database engine level; forgotten ORM filters cannot cause data leaks.
* Single database and single migration run for all tenants.
### Negative:
* Developers must test that custom SQL queries and raw database connections properly set the session variable.
```

---

## 2. Code Review & Pull Request Standards

To maintain industry-standard code quality, enforce these rules in team PRs:

1. **Max PR Size**: Pull requests should be under **300 lines of code**. Large PRs (1,000+ lines) receive superficial reviews and introduce 80% of production regressions.
2. **Automated Gates Must Pass First**: A senior engineer should never spend time pointing out missing types or formatting issues. CI must verify `ruff check` and `mypy` before human review.
3. **The 5-Point Review Checklist**:
   - [ ] Are database queries free of N+1 problems?
   - [ ] Are new database mutations wrapped in transactions?
   - [ ] Is error handling structured with standardized error codes?
   - [ ] Are new endpoints covered by Pytest unit/integration tests?
   - [ ] Are sensitive values redacted from logs?

