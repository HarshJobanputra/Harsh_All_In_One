# AWS Cloud Infrastructure for Backend Engineers

A backend developer must understand how cloud infrastructure is architected to ensure network security, database isolation, and high availability.

---

## 1. Production AWS Network Topology (VPC & Subnets)

```mermaid
flowchart TD
    subgraph Internet["Public Internet"]
        Users["Client Devices"]
    end

    subgraph VPC["AWS Virtual Private Cloud (VPC: 10.0.0.0/16)"]
        subgraph PublicSubnets["Public Subnets (us-east-1a & 1b)"]
            ALB["Application Load Balancer (ALB)"]
            NAT["NAT Gateway (Outbound Internet for Private Nodes)"]
        end

        subgraph PrivateAppSubnets["Private Application Subnets (No Public IPs!)"]
            App1["ECS / EKS Pods (us-east-1a)"]
            App2["ECS / EKS Pods (us-east-1b)"]
        end

        subgraph IsolatedDataSubnets["Isolated Database Subnets (Zero Internet Access!)"]
            RDS_Primary[("AWS RDS PostgreSQL (Primary)")]
            RDS_Standby[("AWS RDS PostgreSQL (Multi-AZ Standby)")]
            Redis[("AWS ElastiCache Redis Cluster")]
        end
    end

    Users -->|HTTPS :443| ALB
    ALB -->|Port 8000| App1 & App2
    App1 & App2 -->|Port 5432| RDS_Primary
    RDS_Primary -.->|Synchronous Replication| RDS_Standby
    App1 & App2 -->|Port 6379| Redis
    App1 & App2 -->|Outbound API calls| NAT
```

---

## 2. Security Group Chaining (Least Privilege)

Never open database ports (`5432`) to `0.0.0.0/0`! Use **Security Group Chaining**:

1. **ALB Security Group**:
   * Inbound: Port `80` & `443` from `0.0.0.0/0` (Entire internet).
2. **Application (ECS/EC2) Security Group**:
   * Inbound: Port `8000` **ONLY from `sg-alb`**.
3. **Database (RDS) Security Group**:
   * Inbound: Port `5432` **ONLY from `sg-app`**.
   * Outbound: None.

Even if an attacker gains the database password, they cannot connect over the internet because the database subnet has zero public routing!

