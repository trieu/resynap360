# 📚 Aurora Serverless v2 Setup with Cost Optimization & Monitoring

This project configures an **AWS Aurora PostgreSQL Serverless v2** database to operate efficiently at **minimal cost** while providing **real-time monitoring** and **budget protection**.

We use:
- **Serverless v2 scaling** between **0–1 ACUs**
- **AWS Budgets** for monthly cost alerts
- **AWS CloudWatch** alarms for utilization spikes

---

## 🚀 Architecture Overview

| Component | Purpose |
|:---------:|:-------:|
| **Aurora Serverless v2** | Pay-per-use PostgreSQL, autoscaling between 0–1 ACUs |
| **AWS Budgets** | Monitor monthly spend on RDS |
| **CloudWatch Alarms** | Alert on high ACU utilization or capacity saturation |
| **(Optional)** Auto-Scaling Policy | Future-proof scaling if needed |

---

## 🛠 Setup Instructions

### 1. Configure Aurora Serverless v2
- Set **Min Capacity**: `0 ACUs`
- Set **Max Capacity**: `1 ACU`
- Enable **Auto Pause** (optional, improves savings on idle).
- Use **Standard Aurora** storage unless heavy IO demands exist.

### 2. Create a Cost Budget
- Go to **Billing → Budgets** in AWS Console.
- Create a new **Cost Budget**:
  - Scope: **Service = Amazon RDS**
  - Set monthly limit, e.g., **$100**
  - Add **email notifications** at 50%, 80%, and 100% spend.

### 3. Create CloudWatch Alarms
Create two alarms on the Aurora database:

| Metric | Threshold | Action |
|:------:|:---------:|:------:|
| `ACUUtilization` | >80% for 5 minutes | Alert via SNS |
| `ServerlessDatabaseCapacity` | >=1 for 5 minutes | Alert via SNS |

- Set up an **SNS Topic** for notification delivery (email or Slack integration).

---

## 📈 Monitoring and Maintenance

- **Daily**: Review CloudWatch metrics for anomalies.
- **Monthly**: Review AWS Budgets dashboard for cost trends.
- **After Load Testing**: Adjust min/max ACUs if necessary.

---

## ⚠️ Risks and Limitations

- **Scaling Delay**: Scaling from 0 ACUs may add a 5–10s latency on first query.
- **Throttling Risk**: If load exceeds 1 ACU and auto-scaling is not enabled, queries may queue or fail under heavy bursts.
- **Cold Starts**: Infrequent queries may wake a paused cluster.

---

## 📦 Future Enhancements (Optional)

- Add **Auto-Scaling Policies** to allow growth to 2+ ACUs dynamically.
- Implement **reserved capacity** or **provisioned instances** if usage stabilizes.
- Integrate **CloudWatch dashboards** for visual monitoring.

---

## 🧠 Key Takeaways

> **“You only pay for what you use — but you must control what you *allow* to be used.”**

Optimizing Aurora Serverless v2 with budgets and monitoring ensures that serverless remains cost-effective, scalable, and predictable — not a hidden financial trap.

---

## 🔗 References
- [AWS Aurora Serverless Pricing](https://aws.amazon.com/rds/aurora/pricing/)
- [AWS Budgets Documentation](https://docs.aws.amazon.com/cost-management/latest/userguide/budgets-managing-costs.html)
- [CloudWatch Alarms Documentation](https://docs.aws.amazon.com/AmazonCloudWatch/latest/monitoring/AlarmThatSendsEmail.html)
