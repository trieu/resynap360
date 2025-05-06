-- Bảng 2: cdp_master_profiles
-- Lưu trữ các hồ sơ khách hàng đã được giải quyết (unique identities)
CREATE TABLE cdp_master_profiles (
    master_profile_id UUID PRIMARY KEY DEFAULT gen_random_uuid(), -- ID duy nhất cho hồ sơ master
    -- Các trường dữ liệu tổng hợp hoặc đáng tin cậy nhất từ các hồ sơ thô liên quan
    -- Tên cột ở đây nên khớp với attribute_internal_code nếu storage_type là 'COLUMN'
    first_name VARCHAR(255),
    last_name VARCHAR(255),
    email citext,
    phone_number VARCHAR(50),
    address_line1 VARCHAR(255),
    city VARCHAR(255),
    state VARCHAR(255),
    zip_code VARCHAR(10),
    -- Thêm các trường tổng hợp khác
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    -- Các trường metadata về quá trình giải quyết
    first_seen_raw_profile_id UUID, -- ID của bản ghi thô đầu tiên liên kết với master này
    source_systems TEXT[], -- Danh sách các hệ thống nguồn liên quan đến master này
    web_visitor_ids TEXT[], -- Danh sách các ID web visitor liên quan đến master này
    tenant_id VARCHAR(36), -- Tenant ID 
    ext_attributes JSONB DEFAULT '{}'::jsonb, -- dynamic attributes for cdp_master_profiles
    event_summary JSONB DEFAULT '{}'::jsonb -- dynamic attributes for event summary, e.g: page-view: 10, click: 5, purchase: 2,..
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



-- Thêm các index khác dựa trên cấu hình cdp_profile_attributes