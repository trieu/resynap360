-- Trigger để tự động cập nhật cột update_at
CREATE OR REPLACE FUNCTION update_profile_attributes_timestamp()
RETURNS TRIGGER AS $$
BEGIN
    NEW.update_at = NOW();
    -- update_by có thể được set bởi ứng dụng trước khi UPDATE,
    -- hoặc bạn có thể thử lấy user hiện tại nếu phù hợp với ngữ cảnh
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER before_profile_attributes_update
BEFORE UPDATE ON cdp_profile_attributes
FOR EACH ROW
EXECUTE FUNCTION update_profile_attributes_timestamp();