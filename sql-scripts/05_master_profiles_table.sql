-- Bảng 2: cdp_master_profiles: Master profile table: golden record per resolved identity
CREATE TABLE cdp_master_profiles (
    master_profile_id UUID PRIMARY KEY DEFAULT gen_random_uuid(), -- ID duy nhất cho hồ sơ master
    tenant_id VARCHAR(36), -- Tenant/organization ID

    -- Core identity fields
    email CITEXT,               -- primary email
    secondary_emails TEXT[],    -- Capture multiple verified emails
    phone_number VARCHAR(50),       --  primary phone
    secondary_phone_numbers TEXT[], -- Capture multiple verified phones
    web_visitor_ids TEXT[], -- Web visitor IDs associated with this profile
    national_ids TEXT[], -- Vietnam (CCCD/CMND): Often 9 or 12 digits. United States: (Social Security Number - SSN): 9 digits,
    crm_contact_ids JSONB DEFAULT '{}'::jsonb, -- e.g., { "salesforce_crm": "123", "hubspot_mkt_crm": "456" }
    social_user_ids JSONB DEFAULT '{}'::jsonb, -- e.g., { "facebook": "xxx", "zalo": "yyy" }
    
    -- personal information
    first_name VARCHAR(255), -- field mặc định name của profile. VD: 'Nguyen Van An hay 'Van An' đều OK
    last_name VARCHAR(255), -- theo chuẩn quốc tế 
    gender VARCHAR(20), -- ví dụ: 'male', 'female', 'unknown',...
    date_of_birth DATE, 

    -- Address and location for real-time personalization and shipping
    address_line1 VARCHAR(500), -- temporary residence address (tạm trú)
    address_line2 VARCHAR(500), -- permanent address (Địa chỉ thướng trú)
    city VARCHAR(255),
    state VARCHAR(255),
    zip_code VARCHAR(10),
    country VARCHAR(100),
    latitude DOUBLE PRECISION,
    longitude DOUBLE PRECISION,

    -- Preferences and localization
    preferred_language VARCHAR(20), -- e.g., 'vi', 'en'
    preferred_currency VARCHAR(10), -- e.g., 'VND', 'USD'
    preferred_communication JSONB DEFAULT '{}'::jsonb, -- e.g., { "email": true, "sms": false, "zalo": true }

    -- Behavioral summary
    last_seen_at TIMESTAMPTZ DEFAULT NOW(), -- Thời gian sự kiện cuối cùng được ghi nhận
    last_seen_observer_id VARCHAR(36), -- ID của event observer cuối cùng khi quan sát hành vi user
    last_seen_touchpoint_id VARCHAR(36), -- ID của điểm chạm (touchpoint) cuối cùng
    last_seen_touchpoint_url VARCHAR(2048), -- URL của điểm chạm (touchpoint) cuối cùng
    last_known_channel VARCHAR(50), -- Kênh tương tác cuối cùng, ví dụ: 'web', 'mobile', 'app', 'retail_store',...
   

    -- scoring data fields
    total_sessions INT DEFAULT 1, -- Tổng số phiên truy cập web và phiên đăng nhập, tính toán từ sự kiện
    total_purchases INT, -- total count of purchased product or service  
    data_quality_score INT,
    lead_score INT, -- lead score for marketing analytics
    churn_probability NUMERIC, --  a predictive metric that estimates the likelihood of a customer discontinuing their relationship with your business within a defined future period
    customer_lifetime_value NUMERIC,

    -- AI/ML Segmentation fields
    -- Customer segmentation (multi-tag support)
    customer_segments TEXT[],       -- e.g., ['frequent_traveler', 'high_value']
    persona_tags TEXT[], -- e.g., ['history_lover', 'luxury_traveler']
    data_labels TEXT[], -- e.g., ['internal_test_profile', 'email_opt_out', 'web_signup_campaign_q4']
    customer_journeys JSONB DEFAULT '{}'::jsonb, -- e.g., {"onboarding_series": {"status": "active", "current_stage": "Email 3 Sent"}

    -- Metadata about profile and 
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    first_seen_raw_profile_id UUID, -- ID of first raw profile that matched this master
    source_systems TEXT[], -- List of systems contributing to this profile

     -- Flexible attributes FOR MULTI-DOMAIN: Store domain-specific data here
     -- e.g., {"retail": {"loyalty_tier": "Gold", "last_purchase_date": "2024-10-26"}, "travel": {"preferred_airline": "VN", "passport_number": "..."}}
    ext_attributes JSONB DEFAULT '{}'::jsonb, 

    -- Behavioral summary from event aggregation
    event_summary JSONB DEFAULT '{}'::jsonb, -- e.g., {"page_view": 5, "click": 2}

    -- ML/AI-ready Embeddings
    identity_embedding VECTOR(384), -- For fuzzy identity matching (e.g., name + email + phone)
    persona_embedding VECTOR(384)   -- For semantic similarity (e.g., interest, behavior, content match)
);

----------------- INDEXING DATA for cdp_master_profiles -----------------------

-- Email index (citext, exact match)
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_indexes
        WHERE schemaname = 'public' AND indexname = 'idx_master_profiles_email'
    ) THEN
        CREATE INDEX idx_master_profiles_email ON cdp_master_profiles (email);
    END IF;
END$$;

-- Phone number index (exact match)
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_indexes
        WHERE schemaname = 'public' AND indexname = 'idx_master_profiles_phone'
    ) THEN
        CREATE INDEX idx_master_profiles_phone ON cdp_master_profiles (phone_number);
    END IF;
END$$;

-- GIN index on secondary_emails array, create only if at least one profile has secondary emails
DO $$
BEGIN
    -- Check if the index already exists AND if there is at least one row where secondary_emails array is not empty
    IF NOT EXISTS (
        SELECT 1 FROM pg_indexes
        WHERE schemaname = 'public' AND indexname = 'idx_master_profiles_secondary_emails_gin'
    ) AND EXISTS (
        SELECT 1 FROM cdp_master_profiles WHERE array_length(secondary_emails, 1) > 0 LIMIT 1
    ) THEN
        -- This index is useful if you frequently search for specific emails within the secondary_emails array
        CREATE INDEX idx_master_profiles_secondary_emails_gin ON cdp_master_profiles
        USING gin (secondary_emails);
    END IF;
END$$;

-- GIN index on secondary_phone_numbers array, create only if at least one profile has secondary phone numbers
DO $$
BEGIN
    -- Check if the index already exists AND if there is at least one row where secondary_phone_numbers array is not empty
    IF NOT EXISTS (
        SELECT 1 FROM pg_indexes
        WHERE schemaname = 'public' AND indexname = 'idx_master_profiles_secondary_phone_numbers_gin'
    ) AND EXISTS (
        SELECT 1 FROM cdp_master_profiles WHERE array_length(secondary_phone_numbers, 1) > 0 LIMIT 1
    ) THEN
        -- This index is useful if you frequently search for specific phone numbers within the secondary_phone_numbers array
        CREATE INDEX idx_master_profiles_secondary_phone_numbers_gin ON cdp_master_profiles
        USING gin (secondary_phone_numbers);
    END IF;
END$$;

-- Fuzzy match on first and last name
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_indexes
        WHERE schemaname = 'public' AND indexname = 'idx_master_profiles_name_trgm'
    ) THEN
        CREATE INDEX idx_master_profiles_name_trgm ON cdp_master_profiles
        USING gin (first_name gin_trgm_ops, last_name gin_trgm_ops);
    END IF;
END$$;

-- GIN index on source_systems array
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_indexes
        WHERE schemaname = 'public' AND indexname = 'idx_master_profiles_source_systems_gin'
    ) THEN
        CREATE INDEX idx_master_profiles_source_systems_gin ON cdp_master_profiles
        USING gin (source_systems);
    END IF;
END$$;

-- GIN index on web_visitor_ids array
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_indexes
        WHERE schemaname = 'public' AND indexname = 'idx_master_profiles_web_visitor_ids_gin'
    ) THEN
        CREATE INDEX idx_master_profiles_web_visitor_ids_gin ON cdp_master_profiles
        USING gin (web_visitor_ids);
    END IF;
END$$;

-- Index on created_at
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_indexes
        WHERE schemaname = 'public' AND indexname = 'idx_master_profiles_created_at'
    ) THEN
        CREATE INDEX idx_master_profiles_created_at ON cdp_master_profiles (created_at);
    END IF;
END$$;

-- Index on updated_at
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_indexes
        WHERE schemaname = 'public' AND indexname = 'idx_master_profiles_updated_at'
    ) THEN
        CREATE INDEX idx_master_profiles_updated_at ON cdp_master_profiles (updated_at);
    END IF;
END$$;

-- Index on tenant_id for filtering by tenant
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_indexes
        WHERE schemaname = 'public' AND indexname = 'idx_master_profiles_tenant_id'
    ) THEN
        CREATE INDEX idx_master_profiles_tenant_id ON cdp_master_profiles (tenant_id);
    END IF;
END$$;

-- Compound index on tenant_id and email for queries filtering by tenant and searching by email
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_indexes
        WHERE schemaname = 'public' AND indexname = 'idx_master_profiles_tenant_id_email'
    ) THEN
        CREATE INDEX idx_master_profiles_tenant_id_email ON cdp_master_profiles (tenant_id, email);
    END IF;
END$$;

-- Compound index on tenant_id and phone_number for queries filtering by tenant and searching by phone
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_indexes
        WHERE schemaname = 'public' AND indexname = 'idx_master_profiles_tenant_id_phone'
    ) THEN
        CREATE INDEX idx_master_profiles_tenant_id_phone ON cdp_master_profiles (tenant_id, phone_number);
    END IF;
END$$;



-- Index on first_seen_raw_profile_id if used for lookup or tracing lineage
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_indexes
        WHERE schemaname = 'public' AND indexname = 'idx_master_profiles_first_seen_raw_profile_id'
    ) THEN
        CREATE INDEX idx_master_profiles_first_seen_raw_profile_id ON cdp_master_profiles (first_seen_raw_profile_id);
    END IF;
END$$;

-- GIN index on customer_segments array for filtering by segment
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_indexes
        WHERE schemaname = 'public' AND indexname = 'idx_master_profiles_customer_segments_gin'
    ) THEN
        CREATE INDEX idx_master_profiles_customer_segments_gin ON cdp_master_profiles
        USING gin (customer_segments);
    END IF;
END$$;

-- GIN index on persona_tags array for filtering by persona
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_indexes
        WHERE schemaname = 'public' AND indexname = 'idx_master_profiles_persona_tags_gin'
    ) THEN
        CREATE INDEX idx_master_profiles_persona_tags_gin ON cdp_master_profiles
        USING gin (persona_tags);
    END IF;
END$$;

-- GIN index on customer_journeys for querying within the JSONB structure
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_indexes
        WHERE schemaname = 'public' AND indexname = 'idx_master_profiles_customer_journeys_gin'
    ) THEN
        CREATE INDEX idx_master_profiles_customer_journeys_gin ON cdp_master_profiles
        USING gin (customer_journeys);
    END IF;
END$$;

-- Index on total_purchases for filtering/sorting by purchase count
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_indexes
        WHERE schemaname = 'public' AND indexname = 'idx_master_profiles_total_purchases'
    ) THEN
        CREATE INDEX idx_master_profiles_total_purchases ON cdp_master_profiles (total_purchases);
    END IF;
END$$;

-- Index on customer_lifetime_value for filtering/sorting by CLV
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_indexes
        WHERE schemaname = 'public' AND indexname = 'idx_master_profiles_customer_lifetime_value'
    ) THEN
        CREATE INDEX idx_master_profiles_customer_lifetime_value ON cdp_master_profiles (customer_lifetime_value);
    END IF;
END$$;

-- Index on churn_probability for filtering and sorting high-risk customers
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_indexes
        WHERE schemaname = 'public' AND indexname = 'idx_master_profiles_churn_probability'
    ) THEN
        CREATE INDEX idx_master_profiles_churn_probability ON cdp_master_profiles (churn_probability);
    END IF;
END$$;


-- ANN index for fuzzy identity resolution (only for profiles with an identity embedding)
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_indexes
        WHERE schemaname = 'public' AND indexname = 'idx_identity_embedding_ann'
    ) THEN
        CREATE INDEX idx_identity_embedding_ann
        ON cdp_master_profiles
        USING ivfflat (identity_embedding vector_l2_ops)
        WITH (lists = 100)
        WHERE identity_embedding IS NOT NULL; 
    END IF;
END$$;

-- ANN index for persona-based semantic search (only for profiles with a persona embedding)
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_indexes
        WHERE schemaname = 'public' AND indexname = 'idx_persona_embedding_ann'
    ) THEN
        CREATE INDEX idx_persona_embedding_ann
        ON cdp_master_profiles
        USING ivfflat (persona_embedding vector_l2_ops)
        WITH (lists = 100)
        WHERE persona_embedding IS NOT NULL; 
    END IF;
END$$;

-- Compound indexes with tenant_id for common filtering patterns

-- Tenant and creation date
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_indexes
        WHERE schemaname = 'public' AND indexname = 'idx_master_profiles_tenant_id_created_at'
    ) THEN
        CREATE INDEX idx_master_profiles_tenant_id_created_at ON cdp_master_profiles (tenant_id, created_at);
    END IF;
END$$;

-- Tenant and update date
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_indexes
        WHERE schemaname = 'public' AND indexname = 'idx_master_profiles_tenant_id_updated_at'
    ) THEN
        CREATE INDEX idx_master_profiles_tenant_id_updated_at ON cdp_master_profiles (tenant_id, updated_at);
    END IF;
END$$;

-- Tenant and last seen date
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_indexes
        WHERE schemaname = 'public' AND indexname = 'idx_master_profiles_tenant_id_last_seen_at'
    ) THEN
        CREATE INDEX idx_master_profiles_tenant_id_last_seen_at ON cdp_master_profiles (tenant_id, last_seen_at);
    END IF;
END$$;

-- Tenant and total purchases
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_indexes
        WHERE schemaname = 'public' AND indexname = 'idx_master_profiles_tenant_id_total_purchases'
    ) THEN
        CREATE INDEX idx_master_profiles_tenant_id_total_purchases ON cdp_master_profiles (tenant_id, total_purchases);
    END IF;
END$$;

-- Tenant and lead score
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_indexes
        WHERE schemaname = 'public' AND indexname = 'idx_master_profiles_tenant_id_lead_score'
    ) THEN
        CREATE INDEX idx_master_profiles_tenant_id_lead_score ON cdp_master_profiles (tenant_id, lead_score);
    END IF;
END$$;

-- Tenant and CLV
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_indexes
        WHERE schemaname = 'public' AND indexname = 'idx_master_profiles_tenant_id_clv'
    ) THEN
        CREATE INDEX idx_master_profiles_tenant_id_clv ON cdp_master_profiles (tenant_id, customer_lifetime_value);
    END IF;
END$$;

-- Compound index on tenant_id and churn_probability for multi-tenant filtering
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_indexes
        WHERE schemaname = 'public' AND indexname = 'idx_master_profiles_tenant_id_churn_probability'
    ) THEN
        CREATE INDEX idx_master_profiles_tenant_id_churn_probability ON cdp_master_profiles (tenant_id, churn_probability);
    END IF;
END$$;