-- Bảng Metadata: cdp_id_resolution_status
-- Bảng này dùng để theo dõi trạng thái và thời gian chạy của stored procedure chính,
-- giúp kiểm soát tần suất kích hoạt từ trigger real-time.
CREATE TABLE cdp_id_resolution_status (
    id BOOLEAN PRIMARY KEY DEFAULT TRUE, -- Chỉ cho phép một bản ghi duy nhất
    last_executed_at timestamp with time zone, -- Thời gian stored procedure chính chạy gần nhất
    -- Có thể thêm các trường khác nếu cần theo dõi trạng thái (ví dụ: is_running BOOLEAN)
    CONSTRAINT cdp_id_resolution_status_pkey PRIMARY KEY (id),
    CONSTRAINT enforce_one_row CHECK (id = TRUE) -- Đảm bảo chỉ có một bản ghi
);

-- Chèn bản ghi duy nhất ban đầu nếu chưa tồn tại
INSERT INTO cdp_id_resolution_status (id, last_executed_at) VALUES (TRUE, NULL) ON CONFLICT (id) DO NOTHING;