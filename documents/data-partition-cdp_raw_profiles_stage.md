# Partition Strategy for `cdp_raw_profiles_stage`

*Last updated: 2025-05-15*

## 📌 Purpose

The `cdp_raw_profiles_stage` table ingests raw customer profile data from AWS Firehose or Kafka streams. As data volume grows rapidly, especially in real-time systems, performance and maintainability challenges arise. This document outlines the hourly partitioning strategy on the `received_at` field to optimize:

* Query performance
* Concurrent processing
* Storage management and vacuuming
* Efficient time-based data retention

---

## 🧱 Partitioning Approach

### 🔑 Partition Key

* `received_at TIMESTAMPTZ`: Timestamp of when the raw profile was received
* Partition type: **RANGE**
* Granularity: **Hourly partitions**

### 📦 Base Table Definition

```sql
CREATE TABLE cdp_raw_profiles_stage (
    raw_profile_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id VARCHAR(36),
    source_system VARCHAR(100),
    received_at TIMESTAMPTZ DEFAULT NOW(),
    status_code SMALLINT DEFAULT 1,
    email CITEXT,
    phone_number VARCHAR(50),
    web_visitor_id VARCHAR(36),
    crm_contact_id VARCHAR(100),
    crm_source_id VARCHAR(100),
    social_user_id VARCHAR(50),
    first_name VARCHAR(255),
    last_name VARCHAR(255),
    gender VARCHAR(20),
    date_of_birth DATE,
    address_line1 VARCHAR(500),
    address_line2 VARCHAR(500),
    city VARCHAR(255),
    state VARCHAR(255),
    zip_code VARCHAR(10),
    country VARCHAR(100),
    latitude DOUBLE PRECISION,
    longitude DOUBLE PRECISION,
    preferred_language VARCHAR(20),
    preferred_currency VARCHAR(10),
    preferred_communication JSONB,
    last_seen_at TIMESTAMPTZ DEFAULT NOW(),
    last_seen_observer_id VARCHAR(36),
    last_seen_touchpoint_id VARCHAR(36),
    last_seen_touchpoint_url VARCHAR(2048),
    last_known_channel VARCHAR(50),
    ext_attributes JSONB,
    updated_at TIMESTAMPTZ DEFAULT NOW()
) PARTITION BY RANGE (received_at);
```

---

## ⚙️ Auto-Partitioning Logic

### Partition Naming Convention

* `cdp_raw_profiles_stage_YYYYMMDD_HH`
* Example: `cdp_raw_profiles_stage_20250515_09`

### Partition Creation Function

```sql
CREATE OR REPLACE FUNCTION create_hourly_partition(target_time timestamptz)
RETURNS void LANGUAGE plpgsql AS $$
DECLARE
    partition_start timestamptz := date_trunc('hour', target_time);
    partition_end   timestamptz := partition_start + interval '1 hour';
    partition_name  text := 'cdp_raw_profiles_stage_' || to_char(partition_start, 'YYYYMMDD_HH');
BEGIN
    IF NOT EXISTS (
        SELECT FROM pg_class c
        JOIN pg_namespace n ON n.oid = c.relnamespace
        WHERE c.relname = partition_name AND n.nspname = 'public'
    ) THEN
        EXECUTE format(
            'CREATE TABLE %I PARTITION OF cdp_raw_profiles_stage
             FOR VALUES FROM (%L) TO (%L);',
            partition_name, partition_start, partition_end
        );

        -- Automatically create indexes
        EXECUTE format('CREATE INDEX ON %I (tenant_id, status_code);', partition_name);
        EXECUTE format('CREATE INDEX ON %I (email);', partition_name);
        EXECUTE format('CREATE INDEX ON %I (phone_number);', partition_name);
        EXECUTE format('CREATE INDEX ON %I (web_visitor_id);', partition_name);
    END IF;
END $$;
```

---

## 🕒 Scheduling with `pg_cron`

To automate partition creation hourly:

```sql
-- Install pg_cron if not already
-- Schedule to run 5 minutes before each hour
SELECT cron.schedule(
    'create_next_partition_hourly',
    '55 * * * *',
    $$SELECT create_hourly_partition(now() + interval '1 hour')$$
);
```

---

## 🧹 Old Partition Cleanup

Auto-delete partitions older than 7 days:

```sql
CREATE OR REPLACE FUNCTION drop_old_partitions()
RETURNS void LANGUAGE plpgsql AS $$
DECLARE
    r record;
    drop_before timestamptz := now() - interval '7 days';
BEGIN
    FOR r IN
        SELECT tablename
        FROM pg_tables
        WHERE tablename LIKE 'cdp_raw_profiles_stage_%'
          AND substring(tablename FROM '\d{8}_\d{2}') IS NOT NULL
    LOOP
        IF to_timestamp(substring(r.tablename FROM '\d{8}_\d{2}'), 'YYYYMMDD_HH') < drop_before THEN
            EXECUTE format('DROP TABLE IF EXISTS %I CASCADE;', r.tablename);
        END IF;
    END LOOP;
END $$;
```

```sql
-- Schedule cleanup daily at midnight
SELECT cron.schedule(
    'drop_old_partitions_daily',
    '0 0 * * *',
    $$SELECT drop_old_partitions()$$
);
```

---

## 📊 Recommended Indexes per Partition

Each hourly partition should have:

```sql
CREATE INDEX ON partition_name (tenant_id, status_code);
CREATE INDEX ON partition_name (email);
CREATE INDEX ON partition_name (phone_number);
CREATE INDEX ON partition_name (web_visitor_id);
```

These indexes are added automatically in the `create_hourly_partition()` function.

---

## 📈 When Does Partitioning Make Sense?

| Daily Volume           | Hourly Records | Recommendation                      |
| ---------------------- | -------------- | ----------------------------------- |
| < 100k                 | < 4k/h         | Partition by **day** is sufficient  |
| 100k – 1M              | 4k – 40k/h     | Partition by **hour** is beneficial |
| > 5M (real-time scale) | > 200k/h       | **Hourly partitioning is required** |

**Partitioning enables**:

* Faster queries with partition pruning
* Concurrent ETL and matching processes
* Efficient vacuum/analyze and archiving

---

## 🧪 Testing & Validation

To validate the partitioning:

```sql
EXPLAIN ANALYZE
SELECT * FROM cdp_raw_profiles_stage
WHERE received_at BETWEEN '2025-05-15 09:00:00+07' AND '2025-05-15 10:00:00+07'
AND tenant_id = 'abc' AND status_code = 1;
```

You should see the query plan accessing only the relevant partition (`cdp_raw_profiles_stage_20250515_09`).

---

## 📌 Notes

* Do **not** create indexes on the parent table — they are ignored during queries.
* Avoid too many partitions (>10k) as they slow down query planning.
* For optimal performance, limit retention window (e.g., 7–14 days) and use `DROP TABLE` for old partitions.

---

## ✅ Summary

* ✅ Efficient hourly partitioning improves performance for ingestion-heavy CDP systems.
* ✅ Automates creation and indexing using PostgreSQL 16 + pg\_cron.
* ✅ Supports time-based cleanup with retention policy.
* ✅ Scales well for concurrent identity resolution, segmentation, and analytics.

---

Khi bạn **chạy SQL query** trên một bảng đã được **PARTITION BY RANGE** (ví dụ theo `received_at`), PostgreSQL không truy vấn toàn bộ bảng cha mà sẽ **partition prune** (cắt tỉa các partition không cần thiết), nếu truy vấn của bạn đủ rõ ràng. Dưới đây là flow chi tiết về cách PostgreSQL xử lý:

---

## 🔄 PostgreSQL Query Execution Flow với `PARTITION BY RANGE`

### 1. 🗂 Query nhận vào từ client

Bạn gửi câu truy vấn ví dụ:

```sql
SELECT * FROM cdp_raw_profiles_stage
WHERE received_at BETWEEN '2025-05-15 09:00:00+07' AND '2025-05-15 10:00:00+07';
```

---

### 2. 🔍 Query Planner (giai đoạn lập kế hoạch)

#### a. PostgreSQL xác định:

* Đây là bảng **partitioned table**
* Có bao nhiêu partition con (`cdp_raw_profiles_stage_YYYYMMDD_HH`)

#### b. **Partition Pruning**

PostgreSQL kiểm tra từng partition con:

* Nếu `received_at` range **không giao nhau** với range của partition → **loại bỏ**
* Nếu có giao → giữ lại cho kế hoạch truy vấn

✅ Nếu điều kiện `WHERE` đủ rõ (với giá trị tĩnh hoặc dùng `immutable functions`) → **pruning xảy ra tại planning time**.

---

### 3. ⚙️ Query Execution

Chỉ những partition được giữ lại mới được truy vấn. PostgreSQL sẽ:

* Truy cập chỉ các partition liên quan (ví dụ: `cdp_raw_profiles_stage_20250515_09`)
* Áp dụng indexes nếu có
* Trả kết quả hợp nhất về client

---

### 4. 🧠 Optimizations áp dụng (nếu bạn làm đúng)

* **Parallel scan**: nếu bạn truy vấn range lớn (nhiều partition), Postgres có thể phân phối truy vấn qua nhiều worker.
* **Bitmap index scan**: nếu index trên các partition đủ tốt
* **Constraint exclusion / Partition pruning**: tiết kiệm IO cực lớn.

---

## 💥 Anti-patterns khiến partition không phát huy tác dụng

| Tình huống                                                             | Hậu quả                                                                            |
| ---------------------------------------------------------------------- | ---------------------------------------------------------------------------------- |
| `WHERE received_at = NOW()`                                            | ❌ Postgres không prune được partition tại planning time vì `NOW()` là **volatile** |
| Không có `received_at` trong `WHERE`                                   | ❌ Toàn bộ partitions sẽ bị scan                                                    |
| Join giữa partitioned table và bảng khác mà không lọc rõ `received_at` | ⚠ Có thể bị full scan hoặc inefficient join                                        |
| Index chỉ tạo ở bảng cha                                               | ❌ Bị **bỏ qua** trong partition (phải index từng partition con)                    |

---

## ✅ Mẫu truy vấn hiệu quả

```sql
SELECT email, phone_number
FROM cdp_raw_profiles_stage
WHERE received_at >= '2025-05-15 00:00:00+07'
  AND received_at <  '2025-05-16 00:00:00+07'
  AND tenant_id = 'abc'
  AND status_code = 1;
```

* Điều kiện time range rõ ràng ✅
* Lọc theo indexable fields ✅
* Prune được đúng các partition ✅

---

## 🧪 Xem kế hoạch thực tế

```sql
EXPLAIN ANALYZE
SELECT * FROM cdp_raw_profiles_stage
WHERE received_at BETWEEN '2025-05-15 09:00:00+07' AND '2025-05-15 10:00:00+07';
```

Output sẽ cho biết partition nào được truy cập. Nếu bạn thấy dòng như:

```
->  Seq Scan on cdp_raw_profiles_stage_20250515_09
```

là đã prune đúng partition.

---

## 📌 Tóm tắt flow

```text
[SQL Query]
     ↓
[Query Planner]
     ↓
[Partition Pruning]  ← ⛔ Bỏ qua nếu WHERE không rõ ràng
     ↓
[Choose Access Path: Seq Scan / Index Scan / Parallel Scan]
     ↓
[Execute on Matched Partitions Only]
     ↓
[Return Unified Results]
```

---

Nếu bạn muốn mình vẽ một sơ đồ hoặc cung cấp query benchmark test cho từng bước, mình có thể hỗ trợ.
