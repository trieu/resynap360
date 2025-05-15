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

