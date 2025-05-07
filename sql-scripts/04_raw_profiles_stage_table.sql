-- Bảng 1: cdp_raw_profiles_stage
-- Firehose / Event Queue sẽ đẩy dữ liệu vào bảng này. Lược đồ cần khớp với dữ liệu đầu vào.
CREATE TABLE cdp_raw_profiles_stage (
    raw_profile_id UUID PRIMARY KEY DEFAULT gen_random_uuid(), -- ID duy nhất cho mỗi bản ghi thô
    -- Các cột dữ liệu thô tương ứng với các attribute được định nghĩa trong cdp_profile_attributes
    -- Tên cột ở đây nên khớp với attribute_internal_code nếu storage_type là 'COLUMN'
    first_name VARCHAR(255),
    last_name VARCHAR(255),
    gender VARCHAR(20), -- male, female, unknown,...
    date_of_birth DATE, 

    email citext, -- Sử dụng citext cho email
    phone_number VARCHAR(50), -- Cần chuẩn hóa số điện thoại trước hoặc trong quá trình xử lý
    tenant_id VARCHAR(36), -- Tenant ID 
    zalo_user_id VARCHAR(50), -- Zalo User ID 
    web_visitor_id VARCHAR(36), -- Web Visitor ID 
    crm_id VARCHAR(50), -- CRM User ID 

    address_line1 VARCHAR(255), -- living address
    address_line2 VARCHAR(255), -- home address
    city VARCHAR(255),
    state VARCHAR(255),
    zip_code VARCHAR(10),

    -- Behavioral summary
    last_seen_at TIMESTAMPTZ,
    last_seen_touchpoint_id VARCHAR(36), -- touchpoint ID 
    last_known_channel VARCHAR(50), -- e.g., 'web', 'mobile', 'app', 'retail_store',...
    total_sessions INT, -- total web session and login session, compute from event

    -- Preferences and localization
    preferred_language VARCHAR(20), -- e.g., 'vi', 'en'
    preferred_currency VARCHAR(10), -- e.g., 'VND', 'USD'
    preferred_communication JSONB DEFAULT '{}'::jsonb, -- e.g., { "email": true, "sms": false, "zalo": true }

    -- Thêm các trường dữ liệu khác từ nguồn
    source_system VARCHAR(100), -- Hệ thống nguồn của bản ghi
    received_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    processed_at TIMESTAMP WITH TIME ZONE, -- Đánh dấu thời gian xử lý
    processing_status VARCHAR(50), -- track the state of the raw record in the identity resolution pipeline (e.g., 'new', 'in_progress', 'processed', 'error', 'ignored').
    ext_attributes JSON -- Trường dữ liệu mở rộng dưới dạng JSON
);


-- Tạo Index cho các trường quan trọng dùng cho ghép nối
-- Cần tạo index cho TẤT CẢ các thuộc tính có is_identity_resolution = TRUE và is_index = TRUE
-- Loại index (B-tree, GIN) phụ thuộc vào data_type và matching_rule

----------------- ADDITIONAL INDEXING DATA for cdp_raw_profiles_stage -----------------------

-- Main compound index on tenant_id and web_visitor_id for upsert data
DO $$
BEGIN
    -- Drop the existing non-unique index if it exists
    IF EXISTS (
        SELECT 1 FROM pg_indexes
        WHERE schemaname = 'public' AND indexname = 'idx_raw_profiles_stage_tenant_id_web_visitor_id'
    ) THEN
        EXECUTE 'DROP INDEX IF EXISTS idx_raw_profiles_stage_tenant_id_web_visitor_id';
    END IF;

    -- Add a unique constraint (this will implicitly create a unique index)
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.table_constraints
        WHERE table_schema = 'public'
          AND table_name = 'cdp_raw_profiles_stage'
          AND constraint_type = 'UNIQUE'
          AND constraint_name = 'unique_tenant_web_visitor'
    ) THEN
        ALTER TABLE cdp_raw_profiles_stage
        ADD CONSTRAINT unique_tenant_web_visitor UNIQUE (tenant_id, web_visitor_id);
    END IF;
END$$;



-- Index on web_visitor_id for efficient filtering 
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_indexes
        WHERE schemaname = 'public' AND indexname = 'idx_raw_profiles_stage_web_visitor_id'
    ) THEN
        CREATE INDEX idx_raw_profiles_stage_web_visitor_id ON cdp_raw_profiles_stage (web_visitor_id);
    END IF;
END$$;

-- Index on tenant_id for efficient filtering by tenant (essential for multi-tenancy)
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_indexes
        WHERE schemaname = 'public' AND indexname = 'idx_raw_profiles_stage_tenant_id'
    ) THEN
        CREATE INDEX idx_raw_profiles_stage_tenant_id ON cdp_raw_profiles_stage (tenant_id);
    END IF;
END$$;

-- Index on source_system for filtering data by its origin
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_indexes
        WHERE schemaname = 'public' AND indexname = 'idx_raw_profiles_stage_source_system'
    ) THEN
        CREATE INDEX idx_raw_profiles_stage_source_system ON cdp_raw_profiles_stage (source_system);
    END IF;
END$$;

-- Index on received_at for processing data chronologically by arrival time
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_indexes
        WHERE schemaname = 'public' AND indexname = 'idx_raw_profiles_stage_received_at'
    ) THEN
        CREATE INDEX idx_raw_profiles_stage_received_at ON cdp_raw_profiles_stage (received_at);
    END IF;
END$$;

-- Index on processed_at for tracking and querying processed records
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_indexes
        WHERE schemaname = 'public' AND indexname = 'idx_raw_profiles_stage_processed_at'
    ) THEN
        CREATE INDEX idx_raw_profiles_stage_processed_at ON cdp_raw_profiles_stage (processed_at);
    END IF;
END$$;

-- Index on processing_status for managing the processing pipeline
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_indexes
        WHERE schemaname = 'public' AND indexname = 'idx_raw_profiles_stage_processing_status'
    ) THEN
        CREATE INDEX idx_raw_profiles_stage_processing_status ON cdp_raw_profiles_stage (processing_status);
    END IF;
END$$;


-- Compound index on tenant_id and received_at for processing new data per tenant
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_indexes
        WHERE schemaname = 'public' AND indexname = 'idx_raw_profiles_stage_tenant_id_received_at'
    ) THEN
        CREATE INDEX idx_raw_profiles_stage_tenant_id_received_at ON cdp_raw_profiles_stage (tenant_id, received_at);
    END IF;
END$$;

-- Compound index on tenant_id and processing_status for managing queue per tenant
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_indexes
        WHERE schemaname = 'public' AND indexname = 'idx_raw_profiles_stage_tenant_id_processing_status'
    ) THEN
        CREATE INDEX idx_raw_profiles_stage_tenant_id_processing_status ON cdp_raw_profiles_stage (tenant_id, processing_status);
    END IF;
END$$;

-- Compound index on tenant_id and email for faster lookups by email within a tenant
-- You already have idx_raw_profiles_stage_email, this adds tenant context
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_indexes
        WHERE schemaname = 'public' AND indexname = 'idx_raw_profiles_stage_tenant_id_email'
    ) THEN
        CREATE INDEX idx_raw_profiles_stage_tenant_id_email ON cdp_raw_profiles_stage (tenant_id, email);
    END IF;
END$$;

-- Compound index on tenant_id and phone_number for faster lookups by phone within a tenant
-- You already have idx_raw_profiles_stage_phone, this adds tenant context
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_indexes
        WHERE schemaname = 'public' AND indexname = 'idx_raw_profiles_stage_tenant_id_phone_number'
    ) THEN
        CREATE INDEX idx_raw_profiles_stage_tenant_id_phone_number ON cdp_raw_profiles_stage (tenant_id, phone_number);
    END IF;
END$$;


-- Index on zalo_user_id if it's a frequently used identifier for matching or lookup
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_indexes
        WHERE schemaname = 'public' AND indexname = 'idx_raw_profiles_stage_zalo_user_id'
    ) THEN
        CREATE INDEX idx_raw_profiles_stage_zalo_user_id ON cdp_raw_profiles_stage (zalo_user_id);
    END IF;
END$$;

-- Compound index on tenant_id and zalo_user_id
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_indexes
        WHERE schemaname = 'public' AND indexname = 'idx_raw_profiles_stage_tenant_id_zalo_user_id'
    ) THEN
        CREATE INDEX idx_raw_profiles_stage_tenant_id_zalo_user_id ON cdp_raw_profiles_stage (tenant_id, zalo_user_id);
    END IF;
END$$;

-- Index on crm_id if it's a frequently used identifier for matching or lookup
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_indexes
        WHERE schemaname = 'public' AND indexname = 'idx_raw_profiles_stage_crm_id'
    ) THEN
        CREATE INDEX idx_raw_profiles_stage_crm_id ON cdp_raw_profiles_stage (crm_id);
    END IF;
END$$;

-- Compound index on tenant_id and crm_id
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_indexes
        WHERE schemaname = 'public' AND indexname = 'idx_raw_profiles_stage_tenant_id_crm_id'
    ) THEN
        CREATE INDEX idx_raw_profiles_stage_tenant_id_crm_id ON cdp_raw_profiles_stage (tenant_id, crm_id);
    END IF;
END$$;

