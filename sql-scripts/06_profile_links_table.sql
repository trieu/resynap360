-- Bảng 3: cdp_profile_links
-- Liên kết các hồ sơ thô với hồ hồ sơ master tương ứng
-- YÊU CẦU: Extension pgcrypto phải được cài đặt và kích hoạt để sử dụng hàm digest() cho SHA256.
-- Chạy lệnh này một lần cho database nếu chưa có: CREATE EXTENSION IF NOT EXISTS pgcrypto;

CREATE TABLE cdp_profile_links (
    raw_profile_id UUID NOT NULL REFERENCES cdp_raw_profiles_stage(raw_profile_id),
    master_profile_id UUID NOT NULL REFERENCES cdp_master_profiles(master_profile_id),
    link_id VARCHAR(64) GENERATED ALWAYS AS (
        encode(digest(raw_profile_id::text || ':' || master_profile_id::text, 'sha256'), 'hex')
    ) STORED PRIMARY KEY, -- Hashed string (SHA256) làm khóa chính
    linked_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    match_rule VARCHAR(100) -- Ghi lại quy tắc nào đã dẫn đến việc liên kết (ví dụ: 'ExactEmailMatch', 'FuzzyNamePhone', 'DynamicMatch')
);

-- 1. Đảm bảo có Ràng buộc UNIQUE (và do đó là Index UNIQUE) trên raw_profile_id
-- Ràng buộc này đảm bảo một raw_profile chỉ liên kết với một master_profile.
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint
        WHERE conname = 'uk_profile_links_raw_id' AND conrelid = 'cdp_profile_links'::regclass
    ) THEN
        ALTER TABLE cdp_profile_links ADD CONSTRAINT uk_profile_links_raw_id UNIQUE (raw_profile_id);
        RAISE NOTICE 'Constraint uk_profile_links_raw_id on cdp_profile_links (raw_profile_id) created.';
    ELSE
        RAISE NOTICE 'Constraint uk_profile_links_raw_id on cdp_profile_links (raw_profile_id) already exists.';
    END IF;
END$$;

-- 2. Index trên master_profile_id để tra cứu nhanh các raw_profiles liên kết với một master_profile
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_indexes
        WHERE schemaname = 'public' AND indexname = 'idx_profile_links_master_id'
           AND tablename = 'cdp_profile_links'
    ) THEN
        CREATE INDEX idx_profile_links_master_id ON cdp_profile_links (master_profile_id);
        RAISE NOTICE 'Index idx_profile_links_master_id on cdp_profile_links (master_profile_id) created.';
    ELSE
        RAISE NOTICE 'Index idx_profile_links_master_id on cdp_profile_links (master_profile_id) already exists.';
    END IF;
END$$;

-- 3. Index trên linked_at: khi thường xuyên lọc hoặc sắp xếp các liên kết dựa trên thời gian chúng được tạo.
 DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_indexes
        WHERE schemaname = 'public' AND indexname = 'idx_profile_links_linked_at'
        AND tablename = 'cdp_profile_links'
    ) THEN
    CREATE INDEX idx_profile_links_linked_at ON cdp_profile_links (linked_at);
        RAISE NOTICE 'Index idx_profile_links_linked_at on cdp_profile_links (linked_at) created.';
    ELSE
    RAISE NOTICE 'Index idx_profile_links_linked_at on cdp_profile_links (linked_at) already exists.';
    END IF;
END$$;