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
    source_systems TEXT[] -- Danh sách các hệ thống nguồn liên quan đến master này
);

-- Tạo Index cho các trường quan trọng dùng cho tìm kiếm master
-- Cần tạo index cho TẤT CẢ các thuộc tính có is_identity_resolution = TRUE và is_index = TRUE
-- Loại index (B-tree, GIN) phụ thuộc vào data_type và matching_rule
CREATE INDEX idx_master_profiles_email ON cdp_master_profiles (email); -- B-tree cho citext exact match
CREATE INDEX idx_master_profiles_phone ON cdp_master_profiles (phone_number); -- B-tree cho VARCHAR exact match
CREATE INDEX idx_master_profiles_name_trgm ON cdp_master_profiles USING gin (first_name gin_trgm_ops, last_name gin_trgm_ops); -- GIN cho fuzzy_trgm
-- Thêm các index khác dựa trên cấu hình cdp_profile_attributes