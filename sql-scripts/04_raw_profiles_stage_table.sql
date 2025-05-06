-- Bảng 1: cdp_raw_profiles_stage
-- Firehose sẽ đẩy dữ liệu vào bảng này. Lược đồ cần khớp với dữ liệu đầu vào của bạn.
CREATE TABLE cdp_raw_profiles_stage (
    raw_profile_id UUID PRIMARY KEY DEFAULT gen_random_uuid(), -- ID duy nhất cho mỗi bản ghi thô
    -- Các cột dữ liệu thô tương ứng với các attribute được định nghĩa trong cdp_profile_attributes
    -- Tên cột ở đây nên khớp với attribute_internal_code nếu storage_type là 'COLUMN'
    first_name VARCHAR(255),
    last_name VARCHAR(255),
    email citext, -- Sử dụng citext cho email
    phone_number VARCHAR(50), -- Cần chuẩn hóa số điện thoại trước hoặc trong quá trình xử lý
    tenant_id VARCHAR(36), -- Tenant ID 
    zalo_user_id VARCHAR(50), -- Zalo User ID 
    web_visitor_id VARCHAR(36), -- Web Visitor ID 
    crm_id VARCHAR(50), -- CRM User ID 
    address_line1 VARCHAR(255),
    city VARCHAR(255),
    state VARCHAR(255),
    zip_code VARCHAR(10),
    -- Thêm các trường dữ liệu khác từ nguồn
    source_system VARCHAR(100), -- Hệ thống nguồn của bản ghi
    received_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    processed_at TIMESTAMP WITH TIME ZONE, -- Đánh dấu thời gian xử lý
    ext_attributes JSON -- Trường dữ liệu mở rộng dưới dạng JSON
);


-- Tạo Index cho các trường quan trọng dùng cho ghép nối
-- Cần tạo index cho TẤT CẢ các thuộc tính có is_identity_resolution = TRUE và is_index = TRUE
-- Loại index (B-tree, GIN) phụ thuộc vào data_type và matching_rule
CREATE INDEX IF NOT EXISTS idx_raw_profiles_stage_email ON cdp_raw_profiles_stage (email); -- B-tree cho citext exact match
CREATE INDEX IF NOT EXISTS idx_raw_profiles_stage_phone ON cdp_raw_profiles_stage (phone_number); -- B-tree cho VARCHAR exact match

-- a unique index on web_visitor_id and tenant_id
CREATE UNIQUE INDEX IF NOT EXISTS idx_raw_profiles_web_visitor_tenant
ON public.cdp_raw_profiles_stage (web_visitor_id, tenant_id)
WHERE web_visitor_id IS NOT NULL;

-- a unique index on phone_number and tenant_id
CREATE INDEX IF NOT EXISTS idx_raw_profiles_phone_tenant
ON public.cdp_raw_profiles_stage (phone_number, tenant_id)
WHERE phone_number IS NOT NULL;

-- GIN cho fuzzy_trgm using first_name and last_name
CREATE INDEX IF NOT EXISTS idx_raw_profiles_stage_name_trgm ON cdp_raw_profiles_stage USING gin (first_name gin_trgm_ops, last_name gin_trgm_ops); 
-- Thêm các index khác dựa trên cấu hình cdp_profile_attributes