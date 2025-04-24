-- 1. Tạo TYPE dùng cho identity resolution config
DO $$ BEGIN
    CREATE TYPE identity_config_type AS (
        id INT,
        attr_code VARCHAR,
        data_type VARCHAR,
        match_rule VARCHAR,
        threshold DECIMAL,
        cons_rule VARCHAR
    );
EXCEPTION
    WHEN duplicate_object THEN NULL; -- Nếu type đã tồn tại thì bỏ qua
END $$;

-- 2. Hàm chính với logic dynamic identity resolution
CREATE OR REPLACE FUNCTION resolve_customer_identities_dynamic(batch_size INT DEFAULT 1000)
RETURNS VOID AS $$
DECLARE
    r_profile cdp_raw_profiles_stage%ROWTYPE; -- Biến cho bản ghi thô hiện tại
    matched_master_id UUID; -- ID của master profile tìm thấy khớp

    identity_configs_array identity_config_type[]; -- Mảng chứa cấu hình IR từ bảng cấu hình

    v_where_conditions TEXT[] := '{}'; -- Danh sách điều kiện WHERE động
    v_condition_text TEXT;

    v_identity_config_rec identity_config_type; -- Biến duyệt từng cấu hình trong mảng
    v_raw_value_text TEXT;
    v_master_col_name TEXT;

    v_dynamic_select_query TEXT;

    -- Các biến tổng hợp chưa được dùng đầy đủ
    v_update_set_clauses TEXT[] := '{}';
    v_insert_cols TEXT[] := '{}';
    v_insert_values TEXT[] := '{}';
    v_consolidate_config_rec RECORD;

BEGIN
    -- 1. Lấy các cấu hình IR
    SELECT array_agg(ROW(id, attribute_internal_code, data_type, matching_rule, matching_threshold, consolidation_rule)::identity_config_type)
    INTO identity_configs_array
    FROM cdp_profile_attributes
    WHERE is_identity_resolution = TRUE AND status = 'ACTIVE'
    AND matching_rule IS NOT NULL AND matching_rule != 'none';

    IF identity_configs_array IS NULL OR array_length(identity_configs_array, 1) IS NULL THEN
        RAISE WARNING 'Không có thuộc tính identity resolution hoạt động được cấu hình.';
        RETURN;
    END IF;

    -- 2. Duyệt qua các bản ghi thô chưa xử lý
    FOR r_profile IN
        SELECT *
        FROM cdp_raw_profiles_stage
        WHERE processed_at IS NULL
        LIMIT batch_size
    LOOP
        matched_master_id := NULL;
        v_where_conditions := '{}';

        -- 3. Lặp qua các cấu hình IR
        FOREACH v_identity_config_rec IN ARRAY identity_configs_array
        LOOP
            v_raw_value_text := NULL;

            -- 3.1 Lấy giá trị thuộc tính từ bản ghi thô
            CASE v_identity_config_rec.attr_code
                WHEN 'first_name' THEN v_raw_value_text := r_profile.first_name::TEXT;
                WHEN 'last_name' THEN v_raw_value_text := r_profile.last_name::TEXT;
                WHEN 'email' THEN v_raw_value_text := r_profile.email::TEXT;
                WHEN 'phone_number' THEN v_raw_value_text := r_profile.phone_number::TEXT;
                WHEN 'address_line1' THEN v_raw_value_text := r_profile.address_line1::TEXT;
                ELSE
                    RAISE WARNING 'Thuộc tính IR "%" không được hỗ trợ.', v_identity_config_rec.attr_code;
                    CONTINUE;
            END CASE;

            -- 3.2 Kiểm tra giá trị hợp lệ
            IF v_raw_value_text IS NOT NULL AND (v_identity_config_rec.data_type NOT IN ('VARCHAR', 'citext', 'TEXT') OR v_raw_value_text != '') THEN
                v_master_col_name := v_identity_config_rec.attr_code;
                v_condition_text := '';

                CASE v_identity_config_rec.match_rule
                    WHEN 'exact' THEN
                        v_condition_text := format('mp.%I = %L', v_master_col_name, v_raw_value_text);

                    WHEN 'fuzzy_trgm' THEN
                        IF v_identity_config_rec.data_type IN ('VARCHAR', 'citext', 'TEXT') AND v_identity_config_rec.threshold IS NOT NULL THEN
                            v_condition_text := format('similarity(mp.%I, %L) >= %s', v_master_col_name, v_raw_value_text, v_identity_config_rec.threshold);
                        ELSE
                            RAISE WARNING 'Fuzzy_trgm không hợp lệ với "%".', v_identity_config_rec.attr_code;
                        END IF;

                    WHEN 'fuzzy_dmetaphone' THEN
                        IF v_identity_config_rec.data_type IN ('VARCHAR', 'citext', 'TEXT') THEN
                            v_condition_text := format('dmetaphone(mp.%I) = dmetaphone(%L)', v_master_col_name, v_raw_value_text);
                        ELSE
                            RAISE WARNING 'Fuzzy_dmetaphone không hợp lệ với "%".', v_identity_config_rec.attr_code;
                        END IF;

                    ELSE
                        RAISE WARNING 'match_rule không xác định: %', v_identity_config_rec.match_rule;
                        CONTINUE;
                END CASE;

                IF v_condition_text != '' THEN
                    v_where_conditions := array_append(v_where_conditions, '(' || v_condition_text || ')');
                END IF;
            END IF;
        END LOOP;

        -- 4. Thực thi truy vấn tìm khớp
        IF array_length(v_where_conditions, 1) IS NOT NULL THEN
            v_dynamic_select_query := 'SELECT master_profile_id FROM cdp_master_profiles mp WHERE ' || array_to_string(v_where_conditions, ' OR ') || ' LIMIT 1';

            BEGIN
                EXECUTE v_dynamic_select_query INTO matched_master_id;
            EXCEPTION
                WHEN OTHERS THEN
                    RAISE WARNING 'Lỗi truy vấn: % - SQL: %', SQLERRM, v_dynamic_select_query;
                    matched_master_id := NULL;
            END;
        END IF;

        -- 5. Xử lý kết quả khớp
        IF matched_master_id IS NOT NULL THEN
            BEGIN
                INSERT INTO cdp_profile_links (raw_profile_id, master_profile_id, match_rule)
                VALUES (r_profile.raw_profile_id, matched_master_id, 'DynamicMatch');
            EXCEPTION WHEN unique_violation THEN
                CONTINUE;
            END;

            UPDATE cdp_master_profiles mp
            SET
                first_name = COALESCE(mp.first_name, r_profile.first_name),
                email = COALESCE(mp.email, r_profile.email),
                phone_number = COALESCE(mp.phone_number, r_profile.phone_number),
                address_line1 = COALESCE(mp.address_line1, r_profile.address_line1),
                city = COALESCE(mp.city, r_profile.city),
                state = COALESCE(mp.state, r_profile.state),
                zip_code = COALESCE(mp.zip_code, r_profile.zip_code),
                source_systems = array_append(mp.source_systems, r_profile.source_system),
                updated_at = NOW()
            WHERE mp.master_profile_id = matched_master_id;

        ELSE
            -- Không khớp, tạo mới
            INSERT INTO cdp_master_profiles (first_name, last_name, email, phone_number, address_line1, city, state, zip_code, source_systems, first_seen_raw_profile_id)
            VALUES (
                r_profile.first_name,
                r_profile.last_name,
                r_profile.email,
                r_profile.phone_number,
                r_profile.address_line1,
                r_profile.city,
                r_profile.state,
                r_profile.zip_code,
                ARRAY[r_profile.source_system],
                r_profile.raw_profile_id
            )
            RETURNING master_profile_id INTO matched_master_id;

            BEGIN
                INSERT INTO cdp_profile_links (raw_profile_id, master_profile_id, match_rule)
                VALUES (r_profile.raw_profile_id, matched_master_id, 'NewMaster');
            EXCEPTION WHEN unique_violation THEN
                CONTINUE;
            END;
        END IF;

        -- 6. Đánh dấu đã xử lý
        UPDATE cdp_raw_profiles_stage
        SET processed_at = NOW()
        WHERE raw_profile_id = r_profile.raw_profile_id;

    END LOOP;

END;
$$ LANGUAGE plpgsql;