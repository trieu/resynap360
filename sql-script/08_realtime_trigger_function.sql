-- Hàm trigger sẽ được gọi sau khi Firehose chèn dữ liệu vào cdp_raw_profiles_stage
-- Hàm này kiểm tra tần suất và chỉ gọi stored procedure nhận dạng danh tính chính nếu đủ điều kiện.
CREATE OR REPLACE FUNCTION process_new_raw_profiles_trigger_func()
RETURNS TRIGGER AS $$
DECLARE
    -- Khoảng thời gian tối thiểu giữa các lần gọi stored procedure chính từ trigger
    -- Điều chỉnh giá trị này dựa trên tần suất dữ liệu đến và khả năng xử lý của database.
    -- Ví dụ: '5 seconds' (mỗi phút), '5 seconds' (mỗi 5 giây).
    min_interval INTERVAL := '5 seconds'; -- Mặc định: 5 giây

    last_exec_time TIMESTAMP WITH TIME ZONE;
    current_time TIMESTAMP WITH TIME ZONE := NOW();
BEGIN
    -- Sử dụng khối transaction và FOR UPDATE để đảm bảo chỉ một trigger có thể kiểm tra và cập nhật trạng thái tại một thời điểm.
    BEGIN
        -- Khóa bản ghi trạng thái và đọc thời gian chạy gần nhất
        -- Lệnh SELECT FOR UPDATE sẽ chờ nếu bản ghi đang bị khóa bởi trigger khác.
        PERFORM 1 FROM cdp_id_resolution_status WHERE id = TRUE FOR UPDATE;
        SELECT last_executed_at INTO last_exec_time FROM cdp_id_resolution_status WHERE id = TRUE;

        -- Kiểm tra xem đã đủ khoảng thời gian tối thiểu kể từ lần chạy gần nhất chưa
        IF last_exec_time IS NULL OR current_time - last_exec_time >= min_interval THEN
            -- Đã đủ điều kiện, cập nhật thời gian chạy gần nhất trong bảng trạng thái
            UPDATE cdp_id_resolution_status SET last_executed_at = current_time WHERE id = TRUE;

            -- Gọi stored procedure nhận dạng danh tính chính để xử lý các bản ghi processed_at IS NULL.
            -- Lệnh PERFORM thực thi hàm nhưng bỏ qua kết quả trả về.
            -- LƯU Ý: Stored procedure chính sẽ chạy trong cùng transaction block này.
            -- Nếu SP chạy lâu, nó sẽ giữ lock trên bảng cdp_id_resolution_status và có thể
            -- chặn các trigger khác hoặc các thao tác ghi vào bảng status/cdp_raw_profiles_stage.
            -- Đây là hạn chế của cách gọi trực tiếp từ trigger.
            -- Mô hình queue table + scheduler riêng biệt (Option 2 thảo luận trước) sẽ tránh được vấn đề blocking này.
            PERFORM resolve_customer_identities_dynamic();

        ELSE
            -- Chưa đủ khoảng thời gian tối thiểu, bỏ qua việc gọi stored procedure chính từ trigger này.
            -- Dữ liệu mới sẽ được xử lý bởi trigger tiếp theo (khi đủ điều kiện) hoặc bởi lịch trình hàng ngày.
            RAISE DEBUG 'Bỏ qua gọi SP từ trigger. Lần chạy gần nhất: %, Khoảng thời gian tối thiểu: %', last_exec_time, min_interval;
        END IF;

    EXCEPTION
        -- Xử lý lỗi trong quá trình kiểm tra trạng thái hoặc gọi SP
        WHEN OTHERS THEN
            RAISE WARNING 'Lỗi trong hàm trigger process_new_raw_profiles_trigger_func: %', SQLERRM;
            -- Mặc định, lỗi trong trigger sẽ rollback transaction gây ra nó (INSERT/UPDATE của Firehose).
            -- Nếu bạn muốn cho phép INSERT/UPDATE thành công ngay cả khi trigger lỗi,
            -- bạn cần thêm khối EXCEPTION và trả về NULL ở đây. Tuy nhiên, điều này có nghĩa
            -- dữ liệu mới có thể không được xử lý ngay lập tức.
            -- Với mục đích ngăn quá tải, việc cho phép INSERT/UPDATE thành công và bỏ qua trigger lỗi
            -- có thể là chấp nhận được, dựa vào lịch trình hàng ngày để xử lý lại.
            -- Để cho phép INSERT/UPDATE thành công, thêm RETURN NULL; trong khối EXCEPTION.
            RETURN NULL; -- Cho phép transaction gốc thành công ngay cả khi trigger lỗi
    END; -- Kết thúc khối transaction (lock được giải phóng khi khối kết thúc)

    RETURN NULL; -- Giá trị trả về bắt buộc cho AFTER trigger FOR EACH STATEMENT

END;
$$ LANGUAGE plpgsql;