# 🎓 **5-Day Bootcamp: Customer 360 with Real-time Identity Resolution**

---

## 📅 Day 1: Ingest + Store Raw Profiles

### 🎯 Goal: Pull & store raw profiles into `cdp_raw_profiles_stage`

#### 🧠 Morning

* ✅ Tổng quan kiến trúc Customer 360
* ✅ Thiết kế schema `cdp_raw_profiles_stage`
* ✅ Setup AWS S3 + PostgreSQL 16

#### 💻 Lab 1:

* [ ] Ingest data từ:

  * S3 (JSON, CSV)
  * CRM API (HubSpot, Salesforce)
* [ ] Insert batch bằng `psycopg2.extras.execute_values()`
* [ ] Gán `status_code`: `1 = active`, `-1 = delete`

---

## 📅 Day 2: Identity Resolution Engine (PostgreSQL)

### 🎯 Goal: Match & link raw profiles to golden `cdp_master_profiles`

#### 🧠 Morning

* ✅ Logic match: exact, fuzzy, phonetic
* ✅ Stored procedure `resolve_customer_identities_dynamic()`
* ✅ Generate embeddings via **AWS Bedrock** (multi-language)

#### 💻 Lab 2:

* [ ] Build rules: email/phone match, fuzzy name
* [ ] Create `cdp_profile_links`
* [ ] Generate persona embeddings using AWS Bedrock models (e.g., Cohere or Titan Embeddings)
* [ ] Insert/update `cdp_master_profiles`

---

## 📅 Day 3: Batch Data Enrichment with AWS Glue + S3

### 🎯 Goal: Enrich profiles using AWS Glue jobs and external data

#### 🧠 Morning

* ✅ ETL kiến trúc với Glue + S3
* ✅ Glue Crawler, Job, Partitioning
* ✅ Enrichment dataset design

#### 💻 Lab 3:

* [ ] Glue Job enrich từ external interest/CRM lookup tables
* [ ] Ghi kết quả về:

  * `cdp_enriched_profiles` (PostgreSQL)
  * `cdp_master_profiles.enriched_json`
* [ ] Lập lịch Glue Job hàng ngày

---

## 📅 Day 4: Real-time Enrichment + Final Project

### 🎯 Goal: Real-time ingestion → identity resolution → enrichment

#### 🧠 Morning

* ✅ Real-time pipeline: Lambda → Firehose → PostgreSQL
* ✅ Streaming vs Batch trade-offs
* ✅ Fields: `lead_score`, `persona_embedding`, `event_summary`

#### 💻 Final Project:

* [ ] Gửi 50 profiles → stage → match → enrich
* [ ] Generate embeddings via **AWS Bedrock**
* [ ] Query & export segments:

  ```sql
  SELECT * FROM cdp_master_profiles 
  WHERE churn_probability < 0.2 AND lead_score > 80;
  ```

---

## 📅 Day 5: Build Customer 360 Reports using Apache Superset

### 🎯 Goal: Visualize segments, personas, and lead funnel using Superset

#### 🧠 Morning

* ✅ Setup Superset: connect to PostgreSQL
* ✅ Define virtual datasets: `cdp_master_profiles`, `cdp_profile_links`, enriched views
* ✅ Build Dashboards:

  * 👤 Top personas by region
  * 🔄 Lead funnel & stage conversion
  * ⚠️ Churn risk heatmap
  * 📊 Segment performance (campaign\_id, source, device)

#### 💻 Lab 5:

* [ ] Build charts: Pie, Time-series, Filterable Table
* [ ] Export dashboard to PDF/Share link
* [ ] Add role-based access (marketing vs sales)

---

## 🏁 Final Deliverables

* ✅ Batch & Real-time pipelines
* ✅ PostgreSQL identity resolution logic
* ✅ Glue Enrichment Jobs
* ✅ Superset Dashboards
* ✅ SQL Queries for Segmentation
* ✅ **Persona embeddings từ AWS Bedrock (đa ngôn ngữ)**