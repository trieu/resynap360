-- Bảng 2: cdp_master_profiles: Master profile table: golden record per resolved identity
-- Lưu trữ các hồ sơ khách hàng đã được giải quyết (unique identities)
CREATE TABLE cdp_master_profiles (
    master_profile_id UUID PRIMARY KEY DEFAULT gen_random_uuid(), -- ID duy nhất cho hồ sơ master

    -- Core identity fields
    first_name VARCHAR(255),
    last_name VARCHAR(255),

    email CITEXT,
    secondary_emails TEXT[], -- Capture multiple verified emails

    phone_number VARCHAR(50),
    secondary_phone_numbers TEXT[], -- Capture multiple verified phones
    

    -- Enriched identity and demographic info
    date_of_birth DATE,
    gender VARCHAR(20),
    national_id VARCHAR(50),
    social_ids JSONB, -- e.g., { "facebook": "xxx", "zalo": "yyy" }

    -- Address and location
    address_line1 VARCHAR(255),
    city VARCHAR(255),
    state VARCHAR(255),
    zip_code VARCHAR(10),
    country VARCHAR(100),
    latitude DOUBLE PRECISION,
    longitude DOUBLE PRECISION,

    -- Preferences and localization
    preferred_language VARCHAR(20), -- e.g., 'vi', 'en'
    preferred_currency VARCHAR(10), -- e.g., 'VND', 'USD'

    -- Behavioral summary
    last_seen_at TIMESTAMPTZ,
    last_known_channel VARCHAR(50), -- e.g., 'web', 'mobile'
    total_sessions INT,
    total_purchases INT,

    -- scoring data fields
    data_quality_score INT,
    lead_score INT,
    customer_lifetime_value NUMERIC,

    -- AI/ML Segmentation fields
    -- Customer segmentation (multi-tag support)
    customer_segments TEXT[],       -- e.g., ['frequent_traveler', 'high_value']
    persona_tags TEXT[], -- e.g., ['history_lover', 'luxury_traveler']

    -- Metadata
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),

    first_seen_raw_profile_id UUID, -- ID of first raw profile that matched this master
    source_systems TEXT[], -- List of systems contributing to this profile
    web_visitor_ids TEXT[], -- Web visitor IDs associated with this profile
    tenant_id VARCHAR(36), -- Tenant/organization ID

     -- Flexible attributes that don’t warrant a dedicated column
    ext_attributes JSONB DEFAULT '{}'::jsonb, -- e.g., {"preferred_language": "vi", "age_group": "25-34"}

    -- Behavioral summary from event aggregation
    event_summary JSONB DEFAULT '{}'::jsonb, -- e.g., {"page_view": 5, "click": 2}

    -- ML/AI-ready Embeddings
    identity_embedding VECTOR(384), -- For fuzzy identity matching (e.g., name + email + phone)
    persona_embedding VECTOR(384)   -- For semantic similarity (e.g., interest, behavior, content match)
);


-- Tạo Index cho các trường quan trọng dùng cho tìm kiếm master
-- Cần tạo index cho TẤT CẢ các thuộc tính có is_identity_resolution = TRUE và is_index = TRUE


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


-- ANN index for fuzzy identity resolution
CREATE INDEX idx_identity_embedding_ann
ON cdp_master_profiles
USING ivfflat (identity_embedding vector_l2_ops)
WITH (lists = 100);

-- ANN index for persona-based semantic search
CREATE INDEX idx_persona_embedding_ann
ON cdp_master_profiles
USING ivfflat (persona_embedding vector_l2_ops)
WITH (lists = 100);


-- Thêm các index khác dựa trên cấu hình cdp_profile_attributes