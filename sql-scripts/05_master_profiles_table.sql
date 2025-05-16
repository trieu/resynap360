-- Bảng 2: cdp_master_profiles: Master profile table: golden record per resolved identity
CREATE TABLE cdp_master_profiles (
    master_profile_id UUID PRIMARY KEY DEFAULT gen_random_uuid(), -- ID duy nhất cho hồ sơ master
    tenant_id VARCHAR(36), -- ID của Tenant (khách hàng sử dụng CDP)

    -- Core identity fields of master profile
    email CITEXT,               -- primary email
    secondary_emails TEXT[],    -- Capture multiple verified emails
    phone_number VARCHAR(50),       -- primary phone
    secondary_phone_numbers TEXT[], -- Capture multiple verified phones
    web_visitor_ids TEXT[], -- Web visitor IDs associated with this profile
    national_ids TEXT[], -- CCCD/CMND, SSN...
    crm_contact_ids JSONB DEFAULT '{}'::jsonb, -- e.g., { "salesforce_crm": "123", "hubspot_mkt_crm": "456" }
    social_user_ids JSONB DEFAULT '{}'::jsonb, -- e.g., { "facebook": "xxx", "zalo": "yyy" }

    -- Personal information
    first_name VARCHAR(255), -- VD: 'Nguyen Van An' hay 'Van An'
    last_name VARCHAR(255),  -- theo chuẩn quốc tế 
    gender VARCHAR(20),      -- ví dụ: 'male', 'female', 'unknown',...
    date_of_birth DATE,
    marital_status VARCHAR(50),
    has_children BOOLEAN, -- Có con hay không (phục vụ nhóm gia đình)
    income_range VARCHAR(100), -- e.g., "under_10M", "10M_to_30M", "30M_plus"
    occupation VARCHAR(255),
    industry VARCHAR(255),
    education_level VARCHAR(100), -- e.g., 'Bachelor', 'High School'

    -- Address and location
    address_line1 VARCHAR(500), -- tạm trú
    address_line2 VARCHAR(500), -- thường trú
    city VARCHAR(255),
    state VARCHAR(255),
    zip_code VARCHAR(10),
    country VARCHAR(100),
    latitude DOUBLE PRECISION,
    longitude DOUBLE PRECISION,

    -- Preferences & persona details
    lifestyle TEXT, -- e.g., 'digital nomad', 'corporate traveler'
    pain_points TEXT[], -- e.g., ['hard to plan trips', 'language barriers']
    interests TEXT[], -- e.g., ['history', 'beach', 'street food']
    goals TEXT[], -- e.g., ['explore new cultures', 'find affordable hotels']
    motivations TEXT[], -- e.g., ['self-expression', 'family bonding']
    personal_values TEXT[], -- e.g., ['sustainability', 'authenticity']
    spending_behavior TEXT, -- e.g., 'price-sensitive', 'premium-first'
    favorite_brands TEXT[], -- e.g., ['Nike', 'MUJI']

    -- Localization & communication
    preferred_language VARCHAR(20), -- e.g., 'vi', 'en'
    preferred_currency VARCHAR(10), -- e.g., 'VND', 'USD'
    preferred_communication JSONB DEFAULT '{}'::jsonb, -- e.g., { "email": true, "sms": false, "zalo": true }
    preferred_shopping_channels TEXT[], -- e.g., ['online', 'retail_store', 'mobile_app']
    preferred_locations TEXT[],         -- e.g., ['Saigon Centre', 'Aeon Mall Tan Phu']
    preferred_contents TEXT[] -- e.g., ['videos', 'reviews']

    -- Behavioral summary
    last_seen_at TIMESTAMPTZ DEFAULT NOW(), -- Thời gian sự kiện cuối cùng được ghi nhận
    last_seen_observer_id VARCHAR(36), -- ID của event observer cuối cùng
    last_seen_touchpoint_id VARCHAR(36), -- ID điểm chạm cuối cùng
    last_seen_touchpoint_url VARCHAR(2048), -- URL điểm chạm cuối cùng
    last_known_channel VARCHAR(50), -- Kênh tương tác cuối cùng

    -- Scoring data
    total_sessions INT DEFAULT 1, -- tổng khối lượng phiên truy cập/tương tác)
    total_purchases INT, -- tổng số lần mua hàng
    avg_order_value NUMERIC(12, 2), -- Giá trị mua trung bình
    last_purchase_date DATE,
    data_quality_score INT,
    lead_score INT, -- can range from 0 to 100
    lead_score_model_version VARCHAR(20),
    lead_score_last_updated TIMESTAMPTZ,
    engagement_score INT, -- Composite metric from events (pageviews, time on site, etc.)
    recency_score INT,    -- Last seen recency score (e.g., 1–100 scale)
    churn_probability NUMERIC(5, 4), -- e.g., 0.8765 (87.65%) Xác suất churn
    customer_lifetime_value NUMERIC(12, 2) -- e.g., 10250000.00 VND, Long-term ROI
    loyalty_tier VARCHAR(50), -- e.g., 'Gold', 'Silver'

    -- AI/ML segmentation
    customer_segments TEXT[], -- e.g., ['frequent_traveler', 'high_value']
    persona_tags TEXT[], -- e.g., ['history_lover', 'luxury_traveler']
    data_labels TEXT[], -- e.g., ['internal_test_profile', 'email_opt_out']
    customer_journeys JSONB DEFAULT '{}'::jsonb, -- e.g., {"onboarding_series": {"status": "active"}}
    next_best_actions JSONB DEFAULT '{}'::jsonb, -- e.g., {"campaign": "luxury_summer_deals", "product_recommendation": ["P123", "P456"], "cta": "buy_now"}

    -- Metadata & origin
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    first_seen_raw_profile_id UUID,
    source_systems TEXT[], -- Các hệ thống đóng góp vào hồ sơ

    -- Flexible attributes
    ext_attributes JSONB DEFAULT '{}'::jsonb, -- Cho phép mở rộng theo domain

    -- Behavioral event summary
    event_summary JSONB DEFAULT '{}'::jsonb, -- e.g., {"page_view": 5, "click": 2}

    -- Embedding fields for AI
    identity_embedding VECTOR(384), -- Cho fuzzy identity resolution
    persona_embedding VECTOR(384)   -- Cho gợi ý nội dung, sản phẩm, hành vi
);

------------------------------------------------------------------------------------

-- FUNCTION để tự động cập nhật trường updated_at trong cdp_master_profiles
CREATE OR REPLACE FUNCTION set_master_profile_updated_at()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$ language 'plpgsql';

-- Add a trigger for auto-updating updated_at field to avoid relying on app logic.
CREATE TRIGGER trigger_set_master_profile_updated_at
BEFORE UPDATE ON cdp_master_profiles
FOR EACH ROW
EXECUTE FUNCTION set_master_profile_updated_at();

-----------------------------------------------------------------------------------------------------------------
---------------------------------- INDEXING DATA for cdp_master_profiles ----------------------------------------
-----------------------------------------------------------------------------------------------------------------

-- Index cơ bản cho tenant_id (nếu các truy vấn chỉ lọc theo tenant_id mà không có trường nào khác)
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_indexes
        WHERE schemaname = 'public' AND indexname = 'idx_master_profiles_tenant_id'
    ) THEN
        CREATE INDEX idx_master_profiles_tenant_id ON cdp_master_profiles (tenant_id);
    END IF;
END$$;

--------------------------------------------------------------------------------
-- Indexes cho các Trường Định danh Chính (Primary Identifiers)
--------------------------------------------------------------------------------

-- Index cho email chính (CITEXT) kết hợp với tenant_id
-- (Sửa đổi từ ví dụ của bạn để bao gồm tenant_id cho hiệu suất tốt hơn trong môi trường multi-tenant)
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_indexes
        WHERE schemaname = 'public' AND indexname = 'idx_master_profiles_tenant_email'
    ) THEN
        -- Truy vấn theo email cụ thể trong một tenant là rất phổ biến.
        CREATE INDEX idx_master_profiles_tenant_email ON cdp_master_profiles (tenant_id, email);
    END IF;
END$$;

-- Index cho số điện thoại chính kết hợp với tenant_id (Như ví dụ của bạn, rất tốt)
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_indexes
        WHERE schemaname = 'public' AND indexname = 'idx_master_profiles_tenant_id_phone'
    ) THEN
        CREATE INDEX idx_master_profiles_tenant_id_phone ON cdp_master_profiles (tenant_id, phone_number);
    END IF;
END$$;

--------------------------------------------------------------------------------
-- Indexes GIN cho các Trường Định danh dạng Mảng (Array-based Identifiers)
--------------------------------------------------------------------------------

-- Index GIN cho secondary_emails (mảng TEXT)
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_indexes
        WHERE schemaname = 'public' AND indexname = 'idx_master_profiles_secondary_emails_gin'
    ) AND EXISTS (
        SELECT 1 FROM cdp_master_profiles WHERE cardinality(secondary_emails) > 0 LIMIT 1
    ) THEN
        -- Hữu ích khi tìm kiếm một email cụ thể trong mảng secondary_emails.
        -- Ví dụ: WHERE tenant_id = '...' AND secondary_emails @> ARRAY['some_email@example.com']
        CREATE INDEX idx_master_profiles_secondary_emails_gin ON cdp_master_profiles USING gin (secondary_emails);
    END IF;
END$$;

-- Index GIN cho secondary_phone_numbers (mảng TEXT) (Như ví dụ của bạn, rất tốt)
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_indexes
        WHERE schemaname = 'public' AND indexname = 'idx_master_profiles_secondary_phone_numbers_gin'
    ) AND EXISTS (
        SELECT 1 FROM cdp_master_profiles WHERE cardinality(secondary_phone_numbers) > 0 LIMIT 1
    ) THEN
        CREATE INDEX idx_master_profiles_secondary_phone_numbers_gin ON cdp_master_profiles USING gin (secondary_phone_numbers);
    END IF;
END$$;

-- Index GIN cho web_visitor_ids (mảng TEXT)
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_indexes
        WHERE schemaname = 'public' AND indexname = 'idx_master_profiles_web_visitor_ids_gin'
    ) AND EXISTS (
        SELECT 1 FROM cdp_master_profiles WHERE cardinality(web_visitor_ids) > 0 LIMIT 1
    ) THEN
        -- Hữu ích khi tìm kiếm một web_visitor_id cụ thể.
        -- Ví dụ: WHERE tenant_id = '...' AND web_visitor_ids @> ARRAY['visitor_id_xyz']
        CREATE INDEX idx_master_profiles_web_visitor_ids_gin ON cdp_master_profiles USING gin (web_visitor_ids);
    END IF;
END$$;

-- Index GIN cho national_ids (mảng TEXT)
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_indexes
        WHERE schemaname = 'public' AND indexname = 'idx_master_profiles_national_ids_gin'
    ) AND EXISTS (
        SELECT 1 FROM cdp_master_profiles WHERE cardinality(national_ids) > 0 LIMIT 1
    ) THEN
        -- Hữu ích khi tìm kiếm một national_id cụ thể.
        CREATE INDEX idx_master_profiles_national_ids_gin ON cdp_master_profiles USING gin (national_ids);
    END IF;
END$$;

-- Index GIN cho source_systems (mảng TEXT)
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_indexes
        WHERE schemaname = 'public' AND indexname = 'idx_master_profiles_source_systems_gin'
    ) AND EXISTS (
        SELECT 1 FROM cdp_master_profiles WHERE cardinality(source_systems) > 0 LIMIT 1
    ) THEN
        -- Hữu ích để tìm hồ sơ được đóng góp bởi một hoặc nhiều hệ thống nguồn cụ thể.
        -- Ví dụ: WHERE tenant_id = '...' AND source_systems @> ARRAY['Salesforce_CRM']
        CREATE INDEX idx_master_profiles_source_systems_gin ON cdp_master_profiles USING gin (source_systems);
    END IF;
END$$;

--------------------------------------------------------------------------------
-- Indexes GIN cho các Trường Định danh dạng JSONB (JSONB-based Identifiers)
--------------------------------------------------------------------------------

-- Index GIN cho crm_contact_ids (JSONB)
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_indexes
        WHERE schemaname = 'public' AND indexname = 'idx_master_profiles_crm_contact_ids_gin'
    ) AND EXISTS (
        SELECT 1 FROM cdp_master_profiles WHERE crm_contact_ids <> '{}'::jsonb LIMIT 1
    ) THEN
        -- Hữu ích khi tìm kiếm hồ sơ có một ID CRM cụ thể từ một hệ thống CRM nhất định.
        -- Ví dụ: WHERE tenant_id = '...' AND crm_contact_ids @> '{"salesforce_crm": "123"}'::jsonb
        CREATE INDEX idx_master_profiles_crm_contact_ids_gin ON cdp_master_profiles USING gin (crm_contact_ids);
    END IF;
END$$;

-- Index GIN cho social_user_ids (JSONB)
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_indexes
        WHERE schemaname = 'public' AND indexname = 'idx_master_profiles_social_user_ids_gin'
    ) AND EXISTS (
        SELECT 1 FROM cdp_master_profiles WHERE social_user_ids <> '{}'::jsonb LIMIT 1
    ) THEN
        -- Hữu ích khi tìm kiếm hồ sơ có một ID mạng xã hội cụ thể.
        -- Ví dụ: WHERE tenant_id = '...' AND social_user_ids @> '{"zalo": "user_zalo_id"}'::jsonb
        CREATE INDEX idx_master_profiles_social_user_ids_gin ON cdp_master_profiles USING gin (social_user_ids);
    END IF;
END$$;

--------------------------------------------------------------------------------
-- Indexes cho các Trường Thông tin Cá nhân (Personal Information)
--------------------------------------------------------------------------------
-- (Thường ít được dùng để lookup trực tiếp trên master table trừ khi có UI tìm kiếm cụ thể)
-- Cân nhắc sử dụng lower() cho tìm kiếm không phân biệt chữ hoa/thường nếu không dùng citext.

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_indexes
        WHERE schemaname = 'public' AND indexname = 'idx_master_profiles_tenant_lastname_firstname'
    ) THEN
        -- Hữu ích nếu có chức năng tìm kiếm theo họ và tên.
        CREATE INDEX idx_master_profiles_tenant_lastname_firstname ON cdp_master_profiles (tenant_id, last_name, first_name);
    END IF;
END$$;

--------------------------------------------------------------------------------
-- Indexes cho các Trường Tính điểm (Scoring Fields) - Thường dùng cho Segmentation
--------------------------------------------------------------------------------

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_indexes
        WHERE schemaname = 'public' AND indexname = 'idx_master_profiles_tenant_lead_score'
    ) THEN
        CREATE INDEX idx_master_profiles_tenant_lead_score ON cdp_master_profiles (tenant_id, lead_score DESC NULLS LAST);
    END IF;
END$$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_indexes
        WHERE schemaname = 'public' AND indexname = 'idx_master_profiles_tenant_clv'
    ) THEN
        CREATE INDEX idx_master_profiles_tenant_clv ON cdp_master_profiles (tenant_id, customer_lifetime_value DESC NULLS LAST);
    END IF;
END$$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_indexes
        WHERE schemaname = 'public' AND indexname = 'idx_master_profiles_tenant_churn_prob'
    ) THEN
        CREATE INDEX idx_master_profiles_tenant_churn_prob ON cdp_master_profiles (tenant_id, churn_probability ASC NULLS LAST);
    END IF;
END$$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_indexes
        WHERE schemaname = 'public' AND indexname = 'idx_master_profiles_tenant_data_quality'
    ) THEN
        CREATE INDEX idx_master_profiles_tenant_data_quality ON cdp_master_profiles (tenant_id, data_quality_score DESC NULLS LAST);
    END IF;
END$$;

--------------------------------------------------------------------------------
-- Indexes GIN cho các Trường Phân khúc AI/ML (AI/ML Segmentation - Arrays)
--------------------------------------------------------------------------------

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_indexes
        WHERE schemaname = 'public' AND indexname = 'idx_master_profiles_customer_segments_gin'
    ) AND EXISTS (
        SELECT 1 FROM cdp_master_profiles WHERE cardinality(customer_segments) > 0 LIMIT 1
    ) THEN
        -- Tìm kiếm hồ sơ thuộc một hoặc nhiều phân khúc khách hàng.
        -- Ví dụ: WHERE tenant_id = '...' AND customer_segments @> ARRAY['high_value']
        CREATE INDEX idx_master_profiles_customer_segments_gin ON cdp_master_profiles USING gin (customer_segments);
    END IF;
END$$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_indexes
        WHERE schemaname = 'public' AND indexname = 'idx_master_profiles_persona_tags_gin'
    ) AND EXISTS (
        SELECT 1 FROM cdp_master_profiles WHERE cardinality(persona_tags) > 0 LIMIT 1
    ) THEN
        CREATE INDEX idx_master_profiles_persona_tags_gin ON cdp_master_profiles USING gin (persona_tags);
    END IF;
END$$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_indexes
        WHERE schemaname = 'public' AND indexname = 'idx_master_profiles_data_labels_gin'
    ) AND EXISTS (
        SELECT 1 FROM cdp_master_profiles WHERE cardinality(data_labels) > 0 LIMIT 1
    ) THEN
        CREATE INDEX idx_master_profiles_data_labels_gin ON cdp_master_profiles USING gin (data_labels);
    END IF;
END$$;

--------------------------------------------------------------------------------
-- Indexes GIN cho các Trường JSONB khác (Preferences, Journeys, Attributes, Summary)
--------------------------------------------------------------------------------

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_indexes
        WHERE schemaname = 'public' AND indexname = 'idx_master_profiles_preferred_communication_gin'
    ) AND EXISTS (
        SELECT 1 FROM cdp_master_profiles WHERE preferred_communication <> '{}'::jsonb LIMIT 1
    ) THEN
        -- Tìm hồ sơ có tùy chọn liên lạc cụ thể, ví dụ: những người muốn nhận email.
        -- Ví dụ: WHERE tenant_id = '...' AND preferred_communication @> '{"email": true}'::jsonb
        CREATE INDEX idx_master_profiles_preferred_communication_gin ON cdp_master_profiles USING gin (preferred_communication);
    END IF;
END$$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_indexes
        WHERE schemaname = 'public' AND indexname = 'idx_master_profiles_customer_journeys_gin'
    ) AND EXISTS (
        SELECT 1 FROM cdp_master_profiles WHERE customer_journeys <> '{}'::jsonb LIMIT 1
    ) THEN
        -- Tìm hồ sơ đang ở một giai đoạn cụ thể của một hành trình khách hàng.
        CREATE INDEX idx_master_profiles_customer_journeys_gin ON cdp_master_profiles USING gin (customer_journeys);
    END IF;
END$$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_indexes
        WHERE schemaname = 'public' AND indexname = 'idx_master_profiles_ext_attributes_gin'
    ) AND EXISTS (
        SELECT 1 FROM cdp_master_profiles WHERE ext_attributes <> '{}'::jsonb LIMIT 1
    ) THEN
        -- Tìm kiếm dựa trên các thuộc tính mở rộng.
        CREATE INDEX idx_master_profiles_ext_attributes_gin ON cdp_master_profiles USING gin (ext_attributes);
    END IF;
END$$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_indexes
        WHERE schemaname = 'public' AND indexname = 'idx_master_profiles_event_summary_gin'
    ) AND EXISTS (
        SELECT 1 FROM cdp_master_profiles WHERE event_summary <> '{}'::jsonb LIMIT 1
    ) THEN
        -- Tìm kiếm dựa trên tóm tắt sự kiện, ví dụ: số lần xem trang.
        CREATE INDEX idx_master_profiles_event_summary_gin ON cdp_master_profiles USING gin (event_summary);
    END IF;
END$$;

--------------------------------------------------------------------------------
-- Indexes cho Metadata và Timestamps
--------------------------------------------------------------------------------

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_indexes
        WHERE schemaname = 'public' AND indexname = 'idx_master_profiles_tenant_updated_at'
    ) THEN
        -- Tìm các hồ sơ được cập nhật gần đây.
        CREATE INDEX idx_master_profiles_tenant_updated_at ON cdp_master_profiles (tenant_id, updated_at DESC);
    END IF;
END$$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_indexes
        WHERE schemaname = 'public' AND indexname = 'idx_master_profiles_tenant_created_at'
    ) THEN
        CREATE INDEX idx_master_profiles_tenant_created_at ON cdp_master_profiles (tenant_id, created_at DESC);
    END IF;
END$$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_indexes
        WHERE schemaname = 'public' AND indexname = 'idx_master_profiles_tenant_last_seen_at'
    ) THEN
        -- Tìm các hồ sơ có hoạt động gần đây.
        CREATE INDEX idx_master_profiles_tenant_last_seen_at ON cdp_master_profiles (tenant_id, last_seen_at DESC);
    END IF;
END$$;

-- Index cho first_seen_raw_profile_id (nếu thường xuyên dùng để lookup)
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_indexes
        WHERE schemaname = 'public' AND indexname = 'idx_master_profiles_tenant_first_seen_raw_id'
    ) THEN
        CREATE INDEX idx_master_profiles_tenant_first_seen_raw_id ON cdp_master_profiles (tenant_id, first_seen_raw_profile_id);
    END IF;
END$$;

--------------------------------------------------------------------------------
-- Indexes cho Vector Embeddings (YÊU CẦU EXTENSION pgvector)
--------------------------------------------------------------------------------
-- Cần cài đặt: CREATE EXTENSION IF NOT EXISTS vector;
-- Chọn loại index (HNSW hoặc IVFFlat) và toán tử phù hợp (vector_l2_ops, vector_ip_ops, vector_cosine_ops)
-- tùy thuộc vào cách embedding được tạo và cách bạn muốn đo lường sự tương đồng.
-- Ví dụ dưới đây sử dụng HNSW và L2 distance (vector_l2_ops).

 -- cho identity_embedding (Bỏ comment và điều chỉnh nếu bạn dùng pgvector)
DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'vector') AND NOT EXISTS (
        SELECT 1 FROM pg_indexes
        WHERE schemaname = 'public' AND indexname = 'idx_master_profiles_identity_embedding_hnsw'
    ) THEN
        CREATE INDEX idx_master_profiles_identity_embedding_hnsw ON cdp_master_profiles
        USING HNSW (identity_embedding vector_l2_ops);
    END IF;
END$$;


-- cho persona_embedding (Bỏ comment và điều chỉnh nếu bạn dùng pgvector)
DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'vector') AND NOT EXISTS (
        SELECT 1 FROM pg_indexes
        WHERE schemaname = 'public' AND indexname = 'idx_master_profiles_persona_embedding_hnsw'
    ) THEN
        CREATE INDEX idx_master_profiles_persona_embedding_hnsw ON cdp_master_profiles
        USING HNSW (persona_embedding vector_l2_ops);
    END IF;
END$$;

--------------------------------------------------------------------------------
-- Index cho Dữ liệu Vị trí (Location Data) - Tùy chọn
--------------------------------------------------------------------------------
-- Nếu thường xuyên có các truy vấn tìm kiếm theo vị trí địa lý (ví dụ: tìm trong bán kính).
-- Yêu cầu extension cube và earthdistance.

/* -- Ví dụ cho GiST index trên latitude, longitude (Bỏ comment và điều chỉnh nếu cần)
-- Cần cài đặt:
-- CREATE EXTENSION IF NOT EXISTS cube;
-- CREATE EXTENSION IF NOT EXISTS earthdistance;
DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'earthdistance') AND NOT EXISTS (
        SELECT 1 FROM pg_indexes
        WHERE schemaname = 'public' AND indexname = 'idx_master_profiles_location_gist'
    ) THEN
        CREATE INDEX idx_master_profiles_location_gist
        ON cdp_master_profiles
        USING GIST (ll_to_earth(latitude, longitude));
    END IF;
END$$;
*/