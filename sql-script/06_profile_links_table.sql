-- Bảng 3: cdp_profile_links
-- Liên kết các hồ sơ thô với hồ hồ sơ master tương ứng
CREATE TABLE cdp_profile_links (
    link_id BIGSERIAL PRIMARY KEY,
    raw_profile_id UUID NOT NULL REFERENCES cdp_raw_profiles_stage(raw_profile_id),
    master_profile_id UUID NOT NULL REFERENCES cdp_master_profiles(master_profile_id),
    linked_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    match_rule VARCHAR(100) -- Ghi lại quy tắc nào đã dẫn đến việc liên kết (ví dụ: 'ExactEmailMatch', 'FuzzyNamePhone', 'DynamicMatch')
);

-- Tạo Index để tra cứu nhanh các link
CREATE INDEX idx_profile_links_raw_id ON cdp_profile_links (raw_profile_id);
CREATE INDEX idx_profile_links_master_id ON cdp_profile_links (master_profile_id);

-- Ràng buộc duy nhất để tránh liên kết một raw_profile_id với nhiều master_profile_id
ALTER TABLE cdp_profile_links ADD CONSTRAINT uk_profile_links_raw_id UNIQUE (raw_profile_id);