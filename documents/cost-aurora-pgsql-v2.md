### 🎯 Use Case: **Customer Identity Resolution**

In a **Customer Identity Resolution** scenario, you are merging or deduplicating customer profiles using different identifiers. 
This is typically done by matching on fields like:

* **Email**
* **Phone Number**
* **Name** (with fuzzy matching)
* **Zalo User ID**, **CRM ID**, **Address** (optional)

Your schema already supports this with attributes marked for matching, such as **email**, **phone number**, and **name** (for fuzzy matching with GIN index).

---

### 📊 Data Modeling Impact on Storage and Performance

In terms of **schema design**, you will be dealing with:

1. **Raw Data Profiles**:

   * A raw customer profile will likely contain all the core customer data, which will be used in the identity resolution process.
   * Your schema is well-structured for various matching criteria, especially with the use of indexes and GIN for fuzzy matching of **first\_name** and **last\_name**.
2. **Profile Comparison and Resolution**:

   * Identity resolution usually requires running multiple join queries to compare attributes like email, phone, and name across potentially millions of profiles.
   * This will put significant load on **indexing** and **query optimization**. Indexes are critical for speed, especially for **exact matches** (B-tree for `email`, `phone_number`) and **fuzzy matches** (GIN for `first_name` and `last_name`).

---

### 🧮 Updated Estimated Profile Capacity

Let’s now estimate capacity considering the profile size, query patterns, and index overhead.

#### **Key Assumptions:**

* **Raw profile size**: \~30–50 KB per profile (for attributes and their variants like name, email, address)
* **Index overhead**: Indexes for **email**, **phone\_number**, and **name** could add \~10–20% overhead per profile.
* **Identity resolution load**: This involves running complex queries for matching profiles, especially for fuzzy matching. Each query will involve **multiple joins**, potentially involving full table scans for non-indexed columns.
* **Query volume**: Identity resolution typically involves more frequent reads/writes, especially for new data ingestion and deduplication tasks.

---

### 🧩 Estimated Profile Load Per Aurora Serverless v2 (2 ACUs)

#### 1. **Low Load Use Case (Small to Medium Data Set)**

* **Profile Size**: 30 KB (with index overhead)
* **Queries per profile/month**: \~10 (basic comparison and occasional updates)
* **Capacity**: \~800K to 1 million profiles, assuming batch processes for identity resolution and minimal real-time resolution

#### 2. **Medium Load Use Case (Moderate Data Set)**

* **Profile Size**: 40 KB (with index overhead)
* **Queries per profile/month**: \~50 (regular comparison and enrichment processes)
* **Capacity**: \~400K profiles, with reasonable performance for medium-size customer bases and moderate query load

#### 3. **High Load Use Case (Large Data Set, Real-Time Matching)**

* **Profile Size**: 50 KB (with index overhead)
* **Queries per profile/month**: \~100–200 (real-time matching, frequent deduplication)
* **Capacity**: \~150K to 250K profiles, where every profile undergoes real-time or near-real-time resolution, which is the most resource-intensive

---

### 📈 Performance Optimizations

To maximize the capacity of your Aurora Serverless v2 cluster, here are some key considerations:

1. **Indexing**:

   * Index your most critical columns (e.g., `email`, `phone_number`, `first_name`, `last_name`) to speed up matching. Ensure you have the right index types (e.g., **B-tree** for exact matches and **GIN** for fuzzy matches).
   * Consider **partial indexes** to optimize specific query patterns (e.g., indexing profiles that are frequently updated).

2. **Partitioning**:

   * If profile data grows large, consider **table partitioning** on `received_at` or `processed_at` to distribute data across partitions, improving query performance.

3. **Query Optimization**:

   * Make sure that joins and identity resolution queries are optimized. For fuzzy matching, GIN indexes on `first_name` and `last_name` are great, but be cautious of overusing them in very large datasets.
   * Use **materialized views** for frequently accessed, precomputed resolution results. This will reduce the load of recalculating identity resolutions on every query.

4. **Batch Processing**:

   * Batch updates for identity resolution can help manage the load. For instance, use an ETL process to resolve identities once a day rather than doing it in real-time, depending on the use case.

---

### 🚀 Capacity Table (Updated for Identity Resolution Use Case)

| Load Type       | Estimated Profiles | Query Ops per Profile | Storage per Profile | Index Impact |
| --------------- | ------------------ | --------------------- | ------------------- | ------------ |
| **Low Load**    | 800K – 1M          | \~10/month            | 30–50 KB            | Minimal      |
| **Medium Load** | 400K – 500K        | \~50/month            | 40–50 KB            | Moderate     |
| **High Load**   | 150K – 250K        | \~100–200/month       | 50–60 KB            | High         |

---

With this schema and use case, you're balancing storage, processing time, and query optimization. This should give you a clear picture of how to scale and maintain performance, especially in **identity resolution** tasks. Would you like to dive deeper into any of these optimizations?

## Estimate summary

| Upfront cost | Monthly cost        | Total 12 months cost | Currency |
|--------------|---------------------|----------------------|----------|
| 0            | 895.6499999999999   | 10747.80             | USD      |
|              |                     | * Includes upfront cost |          |

## Detailed Estimate

| Group hierarchy | Region               | Description | Service                       | Upfront | Monthly | First 12 months total | Currency | Status | Configuration summary                                                               |
|-----------------|----------------------|-------------|-------------------------------|---------|---------|-----------------------|----------|--------|-------------------------------------------------------------------------------------|
| Number of Aurora Capacity Units (ACUs) = 1     | Asia Pacific (Singapore) |             | Amazon Aurora PostgreSQL-Compatible DB | 0       | 338.39  | 4060.68               | USD      |        | Aurora PostgreSQL Cluster Configuration Option (Aurora Standard), Storage amount (100 GB), Additional backup storage (100 GB) |
| Number of Aurora Capacity Units (ACUs) = 2   | Asia Pacific (Singapore) |             | Amazon Aurora PostgreSQL-Compatible DB | 0       | 557.26  | 6687.12               | USD      |        | Aurora PostgreSQL Cluster Configuration Option (Aurora I/O-optimized), Storage amount (100 GB), Additional backup storage (100 GB) |