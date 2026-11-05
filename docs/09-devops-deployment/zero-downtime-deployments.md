# Zero-Downtime Deployment Strategies: Rolling, Blue-Green & Canary

Deploying code updates should never require maintenance windows or scheduled downtime (*"Site will be down Sunday 2 AM to 4 AM"*).

Modern cloud engineering relies on three zero-downtime release strategies:

---

## 1. The Three Release Strategies Compared

```mermaid
flowchart TD
    subgraph Rolling["1. Rolling Deployment"]
        R1["Pod 1 (New) & Pod 2 (Old) & Pod 3 (Old)"]
        NoteR["Gradually replaces instances one-by-one. Low infrastructure cost."]
    end

    subgraph BlueGreen["2. Blue-Green Deployment"]
        BG_LB["Load Balancer"] -->|100% Traffic| Blue["Blue Environment (Active v1)"]
        Green["Green Environment (Idle v2 - Deployed & Tested)"]
        NoteBG["Instant atomic cutover via DNS or Load Balancer switch!"]
    end

    subgraph Canary["3. Canary Release"]
        C_LB["Router"] -->|95% Traffic| Stable["v1 (Stable)"]
        C_LB -->|5% Traffic| CanaryPod["v2 (Canary Probe)"]
        NoteC["Test on 5% of real users; auto-rollback if error rate spikes!"]
    end
```

| Strategy | Speed of Rollback | Infrastructure Cost | Risk Level |
| :--- | :--- | :--- | :--- |
| **Rolling Update** | Moderate (Roll backward pod-by-pod) | **Lowest** (Reuses same cluster) | Low |
| **Blue-Green** | **Instant** (Flip router back to Blue) | **High** (Requires 2x identical environments) | **Lowest** |
| **Canary** | Instant | Low to Moderate | **Lowest user impact** |

---

## 2. Automated Rollback Mechanisms
In any CI/CD pipeline, an automated rollback must trigger if:
1. HTTP 5xx error rate exceeds `1%` within 5 minutes of deployment.
2. The `/health/ready` probe fails 3 consecutive attempts on new containers.
3. Database connection pool errors spike.

