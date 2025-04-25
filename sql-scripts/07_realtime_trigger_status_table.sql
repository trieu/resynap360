-- Bảng Metadata: cdp_id_resolution_status
-- Bảng này dùng để theo dõi trạng thái và thời gian cuối cùng chạy của stored procedure chính
DROP TABLE IF EXISTS cdp_id_resolution_status;

CREATE TABLE cdp_id_resolution_status (
    id BOOLEAN PRIMARY KEY DEFAULT TRUE, -- Chỉ cho phép một bản ghi duy nhất
    last_executed_at TIMESTAMP WITH TIME ZONE, -- Thời gian stored procedure chính chạy gần nhất
    -- Có thể thêm các trường khác nếu cần theo dõi trạng thái (ví dụ: is_running BOOLEAN)
    CONSTRAINT enforce_one_row CHECK (id = TRUE) -- Đảm bảo chỉ có một bản ghi
);

-- Chèn bản ghi duy nhất ban đầu nếu chưa tồn tại
INSERT INTO cdp_id_resolution_status (id, last_executed_at) VALUES (TRUE, NULL) ON CONFLICT (id) DO NOTHING;