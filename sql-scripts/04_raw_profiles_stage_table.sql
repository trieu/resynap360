-- Bảng 1: cdp_raw_profiles_stage
-- Firehose / Event Queue sẽ đẩy dữ liệu vào bảng này. Lược đồ cần matching với JSONB dữ liệu đầu vào
CREATE TABLE cdp_raw_profiles_stage (
    raw_profile_id UUID PRIMARY KEY DEFAULT gen_random_uuid(), -- ID duy nhất cho raw profile
   
    -- metadata of profile source
    tenant_id VARCHAR(36), -- ID của Tenant (khách hàng sử dụng CDP)
    source_system VARCHAR(100), -- Hệ thống nguồn của bản ghi
    received_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),

    -- valid value: 3 = processed, 2 = in-progress, 1: unprocessed 
    --              0: deactivated, -1:  must delete
    status_code SMALLINT DEFAULT 1, 

    -- core ID fields for identity resolution 
    email citext, -- Sử dụng kiểu citext cho email để tìm kiếm không phân biệt chữ hoa/thường
    phone_number VARCHAR(50), -- Cần chuẩn hóa số điện thoại trước hoặc trong quá trình xử lý   
    web_visitor_id VARCHAR(36), -- Web Visitor ID (từ cookie hoặc tracking script)
    crm_contact_id VARCHAR(100), -- ID contact CRM chính hoặc đã được hợp nhất (nếu có)
    crm_source_id VARCHAR(100), -- ID của bản ghi hồ sơ gốc từ hệ thống CRM nguồn cụ thể
    social_user_id VARCHAR(50), -- Zalo User ID, Facebook User ID, Google User ID,...

    -- personal information
    first_name VARCHAR(255), -- field mặc định name của profile. VD: 'Nguyen Van An hay 'Van An' đều OK
    last_name VARCHAR(255), -- theo chuẩn quốc tế 
    gender VARCHAR(20), -- ví dụ: 'male', 'female', 'unknown',...
    date_of_birth DATE, 
    
    -- Address and location for shipping and real-time personalization (recommend products in specific location)
    address_line1 VARCHAR(500), -- temporary residence address (tạm trú)
    address_line2 VARCHAR(500), -- permanent address (Địa chỉ thướng trú)
    city VARCHAR(255),
    state VARCHAR(255),
    zip_code VARCHAR(10),
    country VARCHAR(100),
    latitude DOUBLE PRECISION, -- get from mobile app geolocation API
    longitude DOUBLE PRECISION,-- get from mobile app geolocation API

    -- Tùy chọn và bản địa hóa theo ngôn ngữ, kênh giao tiếp và hệ thống tiền tệ
    preferred_language VARCHAR(20), -- Ngôn ngữ ưa thích, ví dụ: 'vi', 'en'
    preferred_currency VARCHAR(10), -- Tiền tệ ưa thích, ví dụ: 'VND', 'USD'
    preferred_communication JSONB, -- Tùy chọn liên lạc ưa thích, ví dụ: { "email": true, "sms": false, "zalo": true }

    -- Behavioral summary
    last_seen_at TIMESTAMPTZ DEFAULT NOW(), -- Thời gian sự kiện cuối cùng được ghi nhận
    last_seen_observer_id VARCHAR(36), -- ID của event observer cuối cùng khi quan sát hành vi user
    last_seen_touchpoint_id VARCHAR(36), -- ID của điểm chạm (touchpoint) cuối cùng
    last_seen_touchpoint_url VARCHAR(2048), -- URL của điểm chạm (touchpoint) cuối cùng
    last_known_channel VARCHAR(50), -- Kênh tương tác cuối cùng, ví dụ: 'web', 'mobile', 'app', 'retail_store',... 

    -- Trường dữ liệu mở rộng dưới dạng JSONB
    ext_attributes JSONB,

    -- thời gian cuối cùng mà profile đã được xử lý
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW() 
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

-- gender validation
ALTER TABLE cdp_raw_profiles_stage
ADD CONSTRAINT chk_gender_valid CHECK (gender IN ('male', 'female', 'unknown', 'other'));

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

-- Index on email for faster lookups 
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_indexes
        WHERE schemaname = 'public' AND indexname = 'idx_raw_profiles_stage_email'
    ) THEN
        CREATE INDEX idx_raw_profiles_stage_email ON cdp_raw_profiles_stage (email);
    END IF;
END$$;

-- Compound index on tenant_id and email for faster lookups by email within a tenant
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_indexes
        WHERE schemaname = 'public' AND indexname = 'idx_raw_profiles_stage_tenant_id_email'
    ) THEN
        CREATE INDEX idx_raw_profiles_stage_tenant_id_email ON cdp_raw_profiles_stage (tenant_id, email);
    END IF;
END$$;


-- Index on phone_number for faster lookups 
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_indexes
        WHERE schemaname = 'public' AND indexname = 'idx_raw_profiles_stage_phone_number'
    ) THEN
        CREATE INDEX idx_raw_profiles_stage_phone_number ON cdp_raw_profiles_stage (phone_number);
    END IF;
END$$;

-- Compound index on tenant_id and phone_number for faster lookups by phone within a tenant
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_indexes
        WHERE schemaname = 'public' AND indexname = 'idx_raw_profiles_stage_tenant_id_phone_number'
    ) THEN
        CREATE INDEX idx_raw_profiles_stage_tenant_id_phone_number ON cdp_raw_profiles_stage (tenant_id, phone_number);
    END IF;
END$$;

-- Index on social_user_id for efficient filtering
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_indexes
        WHERE schemaname = 'public' AND indexname = 'idx_raw_profiles_stage_social_user_id' 
    ) THEN
        CREATE INDEX idx_raw_profiles_stage_social_user_id ON cdp_raw_profiles_stage (social_user_id); 
    END IF;
END$$;

-- Compound index on tenant_id and social_user_id
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_indexes
        WHERE schemaname = 'public' AND indexname = 'idx_raw_profiles_stage_tenant_id_social_user_id' 
    ) THEN
        CREATE INDEX idx_raw_profiles_stage_tenant_id_social_user_id ON cdp_raw_profiles_stage (tenant_id, social_user_id); 
    END IF;
END$$;


-- Index on crm_contact_id if it's a frequently used identifier for matching or lookup
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_indexes
        WHERE schemaname = 'public' AND indexname = 'idx_raw_profiles_stage_crm_contact_id'
    ) THEN
        CREATE INDEX idx_raw_profiles_stage_crm_contact_id ON cdp_raw_profiles_stage (crm_contact_id);
    END IF;
END$$;

-- Compound index on tenant_id and crm_contact_id
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_indexes
        WHERE schemaname = 'public' AND indexname = 'idx_raw_profiles_stage_tenant_id_crm_contact_id'
    ) THEN
        CREATE INDEX idx_raw_profiles_stage_tenant_id_crm_contact_id ON cdp_raw_profiles_stage (tenant_id, crm_contact_id);
    END IF;
END$$;

-- Index tổng hợp cho tra cứu crm_source_id cụ thể từ một source_system trong một tenant
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_indexes
        WHERE schemaname = 'public' AND indexname = 'idx_raw_profiles_stage_tenant_ss_crm_source_id'
    ) THEN
        CREATE INDEX idx_raw_profiles_stage_tenant_ss_crm_source_id ON cdp_raw_profiles_stage (tenant_id, source_system, crm_source_id);
    END IF;
END$$;

-- (Tùy chọn) Index nếu thường xuyên tra cứu crm_source_id chỉ với tenant_id
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_indexes
        WHERE schemaname = 'public' AND indexname = 'idx_raw_profiles_stage_tenant_crm_source_id'
    ) THEN
        CREATE INDEX idx_raw_profiles_stage_tenant_crm_source_id ON cdp_raw_profiles_stage (tenant_id, crm_source_id);
    END IF;
END$$;

-- Index cho việc lọc theo status_code trong một tenant
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_indexes
        WHERE schemaname = 'public' AND indexname = 'idx_raw_profiles_stage_tenant_status'
    ) THEN
        CREATE INDEX idx_raw_profiles_stage_tenant_status ON cdp_raw_profiles_stage (tenant_id, status_code);
    END IF;
END$$;

-- (Nâng cao hơn) Index cho việc xử lý các bản ghi theo status và thời gian nhận, tối ưu cho việc lấy "các bản ghi cần xóa cũ nhất"
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_indexes
        WHERE schemaname = 'public' AND indexname = 'idx_raw_profiles_stage_tenant_status_received'
    ) THEN
        CREATE INDEX idx_raw_profiles_stage_tenant_status_received ON cdp_raw_profiles_stage (tenant_id, status_code, received_at);
    END IF;
END$$;

-- Index cho last_seen_at (Quan trọng cho Phân tích Hành vi hoặc Xử lý Gần đây):
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_indexes
        WHERE schemaname = 'public' AND indexname = 'idx_raw_profiles_stage_tenant_last_seen_at'
    ) THEN
        CREATE INDEX idx_raw_profiles_stage_tenant_last_seen_at ON cdp_raw_profiles_stage (tenant_id, last_seen_at DESC); -- DESC nếu thường xuyên lấy mới nhất
    END IF;
END$$;

-- Trigger sẽ kích hoạt hàm process_new_raw_profiles_trigger_func
-- sau mỗi lần INSERT hoặc UPDATE trên bảng cdp_raw_profiles_stage.
-- FOR EACH STATEMENT: Trigger chỉ chạy một lần cho mỗi lệnh INSERT/UPDATE,
-- hiệu quả hơn FOR EACH ROW khi Firehose chèn nhiều bản ghi cùng lúc.

-- CREATE TRIGGER cdp_trigger_process_new_raw_profiles 
-- AFTER INSERT OR UPDATE ON cdp_raw_profiles_stage
-- FOR EACH STATEMENT
-- EXECUTE FUNCTION process_new_raw_profiles_trigger_func();

-- Lưu ý: Bạn cần VÔ HIỆU HÓA trigger này khi thực hiện tải dữ liệu lịch sử lớn
-- để tránh gọi stored procedure quá nhiều lần.
-- ALTER TABLE cdp_raw_profiles_stage DISABLE TRIGGER cdp_trigger_process_new_raw_profiles;
-- ALTER TABLE cdp_raw_profiles_stage ENABLE TRIGGER cdp_trigger_process_new_raw_profiles;