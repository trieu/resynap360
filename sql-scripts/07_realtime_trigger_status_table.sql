-- Bảng Metadata: cdp_id_resolution_status
-- Bảng này dùng để theo dõi trạng thái và thời gian cuối cùng chạy của stored procedure chính
DROP TABLE IF EXISTS cdp_id_resolution_status;

CREATE TABLE cdp_id_resolution_status (
    id BOOLEAN PRIMARY KEY DEFAULT TRUE, -- Chỉ cho phép một bản ghi duy nhất
    last_successful_execution_completed_at TIMESTAMP WITH TIME ZONE, -- Thời gian stored procedure chính chạy thành công gần nhất
    is_processing BOOLEAN DEFAULT FALSE, -- Cờ lock toàn cục: TRUE nếu SP đang được xử lý hoặc đang trong thời gian chờ 5s
    processing_started_at TIMESTAMP WITH TIME ZONE, -- Thời điểm trigger bắt đầu quá trình xử lý (bao gồm cả delay)
    CONSTRAINT enforce_one_row CHECK (id = TRUE) -- Đảm bảo chỉ có một bản ghi
);

-- Chèn bản ghi duy nhất ban đầu nếu chưa tồn tại
INSERT INTO cdp_id_resolution_status (id, last_successful_execution_completed_at, is_processing, processing_started_at)
VALUES (TRUE, NULL, FALSE, NULL)
ON CONFLICT (id) DO NOTHING;