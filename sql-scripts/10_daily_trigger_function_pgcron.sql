CREATE OR REPLACE FUNCTION run_daily_identity_resolution()
RETURNS void AS $$
BEGIN
    RAISE NOTICE '[%] Vô hiệu hóa trigger real-time...', clock_timestamp();
    EXECUTE format('ALTER TABLE %I DISABLE TRIGGER %I', 'cdp_raw_profiles_stage', 'cdp_trigger_process_new_raw_profiles');

    -- Chờ một chút (5 giây)
    PERFORM pg_sleep(5);

    RAISE NOTICE '[%] Gọi stored procedure resolve_customer_identities_dynamic...', clock_timestamp();
    PERFORM resolve_customer_identities_dynamic();

    RAISE NOTICE '[%] Kích hoạt lại trigger real-time...', clock_timestamp();
    EXECUTE format('ALTER TABLE %I ENABLE TRIGGER %I', 'cdp_raw_profiles_stage', 'cdp_trigger_process_new_raw_profiles');

    RAISE NOTICE '[%] Quá trình lịch trình hàng ngày hoàn tất.', clock_timestamp();

EXCEPTION
    WHEN OTHERS THEN
        RAISE WARNING '[%] Lỗi trong quá trình thực thi: %', clock_timestamp(), SQLERRM;
        -- Cố gắng bật lại trigger
        BEGIN
            EXECUTE format('ALTER TABLE %I ENABLE TRIGGER %I', 'cdp_raw_profiles_stage', 'cdp_trigger_process_new_raw_profiles');
            RAISE NOTICE '[%] Đã kích hoạt lại trigger sau lỗi.', clock_timestamp();
        EXCEPTION
            WHEN OTHERS THEN
                RAISE WARNING '[%] Lỗi khi kích hoạt lại trigger sau lỗi: %', clock_timestamp(), SQLERRM;
        END;
END;
$$ LANGUAGE plpgsql;