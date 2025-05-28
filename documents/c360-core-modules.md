# Customer 360 with Virtual Intelligent Agent Platform

![Flow Diagram](../diagram.png)

## Overview

This document provides a detailed technical specification for implementing the "Customer 360 with Virtual Intelligent Agent Platform". It includes data ingestion, processing, identity resolution, storage, and reporting, built on either AWS or an equivalent Open Source stack.

---

## 1. Key Components

### 1.1 Touchpoints

* Web, Mobile App, IoT, Chatbot
* Collect raw events and user interactions

### 1.2 Customer 360 SDK

* JavaScript SDK to collect and push events
* Interacts with API Gateway / API Proxy

### 1.3 Personalized AI Agents

* Zalo, Web, SMS, etc.
* Activated based on insights from 360 data

---

## 2. Data Flow Functions

### F0: Setup & Synch Metadata

* Lambda function to read Governance DB metadata
* Creates/updates PostgreSQL triggers, tables, profile attributes

### F1: Event Track

* Lambda receives incoming SDK events
* Push to Firehose or Kafka

### F2: Entity Persistence

* Lambda persists events to PostgreSQL and Raw Data Lake
* Push event to `c360-id-resolution` topic for matching

### F3: Customer 360 Processor

* Triggered from identity resolution or analytics engine
* Updates aggregated profile data

### F4: Notification

* Notifies other systems (CRM, ERP, AI Agents)
* Triggered when master profile is created/updated

### F5: 360 Analytics Processor

* SQL on Athena/Pinot for scoring (CLV, RFM, Engagement)
* Output to dashboard and reporting cache

---

## 3. Core Databases

### PostgreSQL 16+ (Aurora Serverless / Open Source)

* **Customer Profiles** (golden record)
* **Identity Resolution DB**
* **Metadata Configuration Tables**

### Raw Data Lake

* AWS S3 / HDFS / ClickHouse
* Stores raw events for ad-hoc querying

---

## 4. Identity Resolution

* Implemented as a stored procedure in PostgreSQL 16+
* Uses flexible matching rules (exact, trigram, metaphone)
* Updates `cdp_master_profiles` table

---

## 5. Analytics and Scoring

* Data from Raw Data Lake is queried using Athena or Apache Pinot
* Output includes:

  * Lead Score
  * Customer Lifetime Value (CLV)
  * Engagement Frequency

---

## 6. Deployment Modes

### AWS Tech Stack

* Lambda, Firehose, SNS, Athena, Aurora Serverless, S3

### Open Source Stack

* Kafka, PostgreSQL 16+, Apache Pinot, HDFS or MinIO, Airflow (optional)

---

## 7. Event Topics & Streams

| Topic Name               | Description                                        |
| ------------------------ | -------------------------------------------------- |
| `c360-id-resolution`     | Trigger identity resolution                        |
| `c360-updated-profiles`  | Notify profile update to AI Agent/CRM              |
| `c360-behavioral-events` | Raw behavioral clickstream or interaction events   |
| `c360-synch-events`      | Metadata sync and profile attribute changes        |
| `c360-activation-events` | Actions for activating AI Agents                   |

---

## 8. Notes for Developers

* All identity resolution logic must be tenant-scoped
* PostgreSQL must be the **only** database used for customer profiles
* Event-driven architecture enables modular scaling

---

## Author

Nguyễn Tấn Triều
