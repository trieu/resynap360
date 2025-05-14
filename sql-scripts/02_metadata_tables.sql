-- Bảng Metadata: attribute_type (Placeholder - cần định nghĩa chi tiết nếu sử dụng FK)
-- Bảng này định nghĩa các loại control UI hoặc kiểu attribute chung.
CREATE TABLE IF NOT EXISTS cdp_attribute_type (
    id SERIAL PRIMARY KEY,
    type_name VARCHAR(100) UNIQUE NOT NULL
);

-- Bảng Metadata: objects (Placeholder - cần định nghĩa chi tiết nếu sử dụng FK)
-- Bảng này định nghĩa các loại đối tượng chính (ví dụ: Customer, Product).
CREATE TABLE IF NOT EXISTS cdp_objects (
    id SERIAL PRIMARY KEY,
    object_name VARCHAR(100) UNIQUE NOT NULL
);

-- Bảng Metadata: cdp_profile_attributes
-- Bảng này định nghĩa *meta-data* cho từng thuộc tính (attribute) của profile.
-- Đã thêm các cột giả định cho cấu hình ghép nối và tổng hợp dữ liệu.
CREATE TABLE cdp_profile_attributes (
    id BIGSERIAL PRIMARY KEY,
    attribute_internal_code VARCHAR(100) UNIQUE NOT NULL,
    name VARCHAR(255) NOT NULL,
    status VARCHAR(50) DEFAULT 'ACTIVE', -- vd: 'ACTIVE', 'INACTIVE', 'DELETED'
    attribute_type_id INT NULL REFERENCES cdp_attribute_type(id), -- FK đến bảng attribute_type
    data_type VARCHAR(50) NOT NULL, -- vd: 'VARCHAR', 'INT', 'BOOLEAN', 'DATETIME', 'JSON', 'FLOAT'
    object_id INT NULL REFERENCES cdp_objects(id), -- FK đến bảng cdp_objects (vd: 1='Customer')
    is_required BOOLEAN DEFAULT FALSE,

    is_index BOOLEAN DEFAULT FALSE, -- Có nên tạo index cho giá trị của attribute này không?
    is_masking BOOLEAN DEFAULT FALSE, -- Có cần che (masking) giá trị của attribute này khi hiển thị không? (PII)
    storage_type VARCHAR(50) NULL, -- Cách lưu trữ giá trị (vd: 'COLUMN', 'JSON_FIELD')
    attribute_size INT NULL, -- Kích thước dữ liệu (vd: max length cho VARCHAR)
    attribute_group VARCHAR(100) NULL, -- Nhóm logic trên UI
    parent_id BIGINT NULL REFERENCES cdp_profile_attributes(id), -- ID của attribute cha (cho cấu trúc lồng)
    option_value JSON NULL, -- Lưu các tùy chọn nếu là dropdown, radio button, etc.
    process_status VARCHAR(50) NULL, -- Trạng thái liên quan đến quy trình xử lý dữ liệu
    attribute_status VARCHAR(50) NULL, -- Trạng thái cụ thể khác
    last_processed_on TIMESTAMP WITH TIME ZONE NULL, -- Thời gian xử lý dữ liệu liên quan đến attribute này lần cuối
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    created_by VARCHAR(100) NULL,
    update_at TIMESTAMP WITH TIME ZONE NULL, -- Sẽ được cập nhật bởi trigger
    update_by VARCHAR(100) NULL,

    -- Cột bổ sung cho cấu hình Identity Resolution
    is_identity_resolution BOOLEAN DEFAULT FALSE, -- CÓ dùng thuộc tính này để tìm và hợp nhất profile không?
    is_synchronizable BOOLEAN DEFAULT TRUE,
    data_quality_score INT NULL, -- Điểm đánh giá chất lượng dữ liệu mặc định/tiềm năng
    matching_rule VARCHAR(50) NULL, -- vd: 'exact', 'fuzzy_trgm', 'fuzzy_dmetaphone', 'none'
    matching_threshold DECIMAL(5, 4) NULL, -- Ngưỡng cho fuzzy match (vd: 0.8)
    consolidation_rule VARCHAR(50) NULL -- Cách tổng hợp giá trị (vd: 'most_recent', 'non_null', 'concatenate', 'prefer_master', 'prefer_raw')
);

-- Clear existing attributes
DELETE FROM cdp_profile_attributes;

-- Insert default identity resolution attributes
INSERT INTO cdp_profile_attributes (
    id, name,  attribute_internal_code, data_type,
    is_identity_resolution, matching_rule, matching_threshold,
    consolidation_rule, status, is_index
) VALUES
(1, 'email', 'email', 'TEXT', TRUE, 'exact', NULL, 'non_null', 'ACTIVE', TRUE),
(2, 'phone_number','phone_number', 'TEXT', TRUE, 'exact', NULL, 'non_null', 'ACTIVE', TRUE),
(3,'social_user_id', 'social_user_id', 'TEXT', TRUE, 'exact',NULL, 'prefer_master', 'ACTIVE', TRUE),
(4,'web_visitor_id', 'web_visitor_id', 'TEXT', TRUE, 'exact',NULL, 'most_recent', 'ACTIVE', TRUE),
(5,'crm_source_id', 'crm_source_id', 'TEXT', TRUE, 'exact',NULL, 'prefer_master', 'ACTIVE', TRUE),
;
