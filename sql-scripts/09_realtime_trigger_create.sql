-- Trigger sẽ kích hoạt hàm process_new_raw_profiles_trigger_func
-- sau mỗi lần INSERT hoặc UPDATE trên bảng cdp_raw_profiles_stage.
-- FOR EACH STATEMENT: Trigger chỉ chạy một lần cho mỗi lệnh INSERT/UPDATE,
-- hiệu quả hơn FOR EACH ROW khi Firehose chèn nhiều bản ghi cùng lúc.
CREATE TRIGGER cdp_trigger_process_new_raw_profiles
AFTER INSERT OR UPDATE ON cdp_raw_profiles_stage
FOR EACH STATEMENT
EXECUTE FUNCTION process_new_raw_profiles_trigger_func();

-- Lưu ý: Bạn cần VÔ HIỆU HÓA trigger này khi thực hiện tải dữ liệu lịch sử lớn
-- để tránh gọi stored procedure quá nhiều lần.
-- ALTER TABLE cdp_raw_profiles_stage DISABLE TRIGGER cdp_trigger_process_new_raw_profiles;
-- ALTER TABLE cdp_raw_profiles_stage ENABLE TRIGGER cdp_trigger_process_new_raw_profiles;