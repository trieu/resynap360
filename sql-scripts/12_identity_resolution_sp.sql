
-- helper function link_or_create_master_profile:
CREATE OR REPLACE FUNCTION link_or_create_master_profile(
    p_raw_profile cdp_raw_profiles_stage,
    p_matched_master_id UUID,
    p_match_rule VARCHAR -- e.g., 'DynamicMatch', 'NewMaster'
)
RETURNS UUID AS $$ -- Returns the master_profile_id (existing or new)
DECLARE
    v_final_master_id UUID;
    v_master_current_last_seen_at TIMESTAMPTZ;
    v_is_raw_event_newer BOOLEAN;
BEGIN
    IF p_matched_master_id IS NOT NULL THEN
        v_final_master_id := p_matched_master_id;
        -- RAISE NOTICE '[LINK_OR_CREATE] Match found for raw_profile_id %: Linking to master_profile_id % (tenant_id: %)', p_raw_profile.raw_profile_id, v_final_master_id, p_raw_profile.tenant_id;

        -- Get current last_seen_at from master to decide on updating related behavioral fields
        SELECT last_seen_at INTO v_master_current_last_seen_at FROM cdp_master_profiles WHERE master_profile_id = v_final_master_id;

        v_is_raw_event_newer := p_raw_profile.last_seen_at IS NOT NULL AND
                                p_raw_profile.last_seen_at >= COALESCE(v_master_current_last_seen_at, '1970-01-01'::TIMESTAMPTZ);

        -- Update master profile
        UPDATE cdp_master_profiles mp
        SET
            -- Personal Info (prefer raw if not null)
            first_name = COALESCE(p_raw_profile.first_name, mp.first_name),
            last_name = COALESCE(p_raw_profile.last_name, mp.last_name),
            gender = COALESCE(p_raw_profile.gender, mp.gender),
            date_of_birth = COALESCE(p_raw_profile.date_of_birth, mp.date_of_birth),

            -- Primary Email Info
            email = CASE
                WHEN (mp.email IS NULL OR mp.email = '')
                    AND (p_raw_profile.email IS NOT NULL AND p_raw_profile.email <> '')
                THEN p_raw_profile.email
                ELSE mp.email
            END,

            -- Secondary Emails
            -- Rule: (if (mp.email is not null) and (p_raw_profile.email is not null) and (mp.email is not p_raw_profile.email) )
            secondary_emails = CASE
                WHEN mp.email IS NOT NULL AND p_raw_profile.email IS NOT NULL AND mp.email <> p_raw_profile.email THEN
                    ARRAY(SELECT DISTINCT elem FROM unnest(COALESCE(mp.secondary_emails, '{}'::TEXT[]) || ARRAY[p_raw_profile.email]) AS elem
                        WHERE elem IS NOT NULL AND elem <> '' AND elem <> mp.email)
                ELSE mp.secondary_emails
            END,
            
            -- Primary phone_number Info
            phone_number = CASE
                WHEN (mp.phone_number IS NULL OR mp.phone_number = '')
                    AND (p_raw_profile.phone_number IS NOT NULL AND p_raw_profile.phone_number <> '')
                THEN p_raw_profile.phone_number
                ELSE mp.phone_number
            END,

            -- Secondary Phone Numbers
            -- Rule: (if (mp.phone_number is not null) and (p_raw_profile.phone_number is not null) and (mp.phone_number is not p_raw_profile.phone_number) )
            secondary_phone_numbers = CASE
                WHEN mp.phone_number IS NOT NULL AND p_raw_profile.phone_number IS NOT NULL AND mp.phone_number <> p_raw_profile.phone_number THEN
                    ARRAY(SELECT DISTINCT elem FROM unnest(COALESCE(mp.secondary_phone_numbers, '{}'::TEXT[]) || ARRAY[p_raw_profile.phone_number]) AS elem
                        WHERE elem IS NOT NULL AND elem <> '' AND elem <> mp.phone_number)
                ELSE mp.secondary_phone_numbers
            END,

            -- Address (prefer raw if not null)
            address_line1 = COALESCE(p_raw_profile.address_line1, mp.address_line1),
            address_line2 = COALESCE(p_raw_profile.address_line2, mp.address_line2),
            city = COALESCE(p_raw_profile.city, mp.city),
            state = COALESCE(p_raw_profile.state, mp.state),
            zip_code = COALESCE(p_raw_profile.zip_code, mp.zip_code),
            country = COALESCE(p_raw_profile.country, mp.country),
            latitude = COALESCE(p_raw_profile.latitude, mp.latitude),
            longitude = COALESCE(p_raw_profile.longitude, mp.longitude),

            -- Preferences (prefer raw if not null)
            preferred_language = COALESCE(p_raw_profile.preferred_language, mp.preferred_language),
            preferred_currency = COALESCE(p_raw_profile.preferred_currency, mp.preferred_currency),
            preferred_communication = COALESCE(p_raw_profile.preferred_communication, mp.preferred_communication),

            -- Behavioral summary (update if raw event is newer, ensure last_seen_at is always the latest)
            last_seen_at = GREATEST(mp.last_seen_at, p_raw_profile.last_seen_at), -- GREATEST handles NULLs correctly
            last_seen_observer_id = CASE WHEN v_is_raw_event_newer THEN p_raw_profile.last_seen_observer_id ELSE mp.last_seen_observer_id END,
            last_seen_touchpoint_id = CASE WHEN v_is_raw_event_newer THEN p_raw_profile.last_seen_touchpoint_id ELSE mp.last_seen_touchpoint_id END,
            last_seen_touchpoint_url = CASE WHEN v_is_raw_event_newer THEN p_raw_profile.last_seen_touchpoint_url ELSE mp.last_seen_touchpoint_url END,
            last_known_channel = CASE WHEN v_is_raw_event_newer THEN p_raw_profile.last_known_channel ELSE mp.last_known_channel END,

            -- Identifiers & System (merge/append)
            source_systems = (
                SELECT array_agg(DISTINCT elem)
                FROM unnest(COALESCE(mp.source_systems, '{}'::TEXT[]) || ARRAY[p_raw_profile.source_system]) AS elem
                WHERE elem IS NOT NULL AND elem <> ''
            ),
            web_visitor_ids = (
                SELECT array_agg(DISTINCT elem)
                FROM unnest(COALESCE(mp.web_visitor_ids, '{}'::TEXT[]) || ARRAY[p_raw_profile.web_visitor_id]) AS elem
                WHERE elem IS NOT NULL AND elem <> ''
            ),
            crm_contact_ids = CASE
                WHEN p_raw_profile.source_system IS NOT NULL AND p_raw_profile.crm_source_id IS NOT NULL THEN
                    COALESCE(mp.crm_contact_ids, '{}'::jsonb) || jsonb_build_object(p_raw_profile.source_system, p_raw_profile.crm_source_id)
                ELSE mp.crm_contact_ids
            END,
            social_user_ids = CASE 
                WHEN p_raw_profile.social_user_id IS NOT NULL AND p_raw_profile.source_system IS NOT NULL THEN
                     COALESCE(mp.social_user_ids, '{}'::jsonb) || jsonb_build_object(p_raw_profile.source_system, p_raw_profile.social_user_id)
                ELSE mp.social_user_ids
            END,
            ext_attributes = COALESCE(mp.ext_attributes, '{}'::jsonb) || COALESCE(p_raw_profile.ext_attributes, '{}'::jsonb),
            updated_at = NOW(),
            status_code = 10 
        WHERE mp.master_profile_id = v_final_master_id;
        -- RAISE NOTICE '[LINK_OR_CREATE] Updated master_profile_id % with raw_profile_id % data', v_final_master_id, p_raw_profile.raw_profile_id;

    ELSE
        -- RAISE NOTICE '[LINK_OR_CREATE] No match found for raw_profile_id % (tenant_id: %): Creating new master profile', p_raw_profile.raw_profile_id, p_raw_profile.tenant_id;
        INSERT INTO cdp_master_profiles (
            master_profile_id, tenant_id,
            email, phone_number, -- primary contacts
            web_visitor_ids, crm_contact_ids, social_user_ids, -- other identifiers
            first_name, last_name, gender, date_of_birth, -- personal info
            address_line1, address_line2, city, state, zip_code, country, latitude, longitude, -- address and geolocation 
            preferred_language, preferred_currency, preferred_communication, -- preferences
            last_seen_at, last_seen_observer_id, last_seen_touchpoint_id, last_seen_touchpoint_url, last_known_channel, -- behavioral
            source_systems, first_seen_raw_profile_id, -- metadata
            ext_attributes, -- extended data
            created_at, updated_at
            -- Fields like secondary_emails/phones, national_ids, scores, segments, embeddings, event_summary use defaults or are populated by other processes
        )
        VALUES (
            gen_random_uuid(), p_raw_profile.tenant_id,
            p_raw_profile.email, p_raw_profile.phone_number,
            CASE WHEN p_raw_profile.web_visitor_id IS NOT NULL AND p_raw_profile.web_visitor_id <> '' THEN ARRAY[p_raw_profile.web_visitor_id] ELSE '{}'::TEXT[] END,
            CASE WHEN p_raw_profile.source_system IS NOT NULL AND p_raw_profile.crm_source_id IS NOT NULL THEN jsonb_build_object(p_raw_profile.source_system, p_raw_profile.crm_source_id) ELSE '{}'::jsonb END,
            CASE WHEN p_raw_profile.social_user_id IS NOT NULL AND p_raw_profile.source_system IS NOT NULL THEN jsonb_build_object(p_raw_profile.source_system, p_raw_profile.social_user_id) ELSE '{}'::jsonb END,
            p_raw_profile.first_name, p_raw_profile.last_name, p_raw_profile.gender, p_raw_profile.date_of_birth,
            p_raw_profile.address_line1, p_raw_profile.address_line2, p_raw_profile.city, p_raw_profile.state, p_raw_profile.zip_code, p_raw_profile.country, p_raw_profile.latitude, p_raw_profile.longitude,
            p_raw_profile.preferred_language, p_raw_profile.preferred_currency, p_raw_profile.preferred_communication,
            p_raw_profile.last_seen_at, p_raw_profile.last_seen_observer_id, p_raw_profile.last_seen_touchpoint_id, p_raw_profile.last_seen_touchpoint_url, p_raw_profile.last_known_channel,
            CASE WHEN p_raw_profile.source_system IS NOT NULL AND p_raw_profile.source_system <> '' THEN ARRAY[p_raw_profile.source_system] ELSE '{}'::TEXT[] END,
            p_raw_profile.raw_profile_id,
            p_raw_profile.ext_attributes,
            NOW(), NOW()
        )
        RETURNING master_profile_id INTO v_final_master_id;
        -- RAISE NOTICE '[LINK_OR_CREATE] Created new master_profile_id % for raw_profile_id %', v_final_master_id, p_raw_profile.raw_profile_id;
    END IF;

    -- Link raw profile to master profile (either existing or new)
    BEGIN
        INSERT INTO cdp_profile_links (raw_profile_id, master_profile_id, match_rule)
        VALUES (p_raw_profile.raw_profile_id, v_final_master_id, p_match_rule);
        -- RAISE NOTICE '[LINK_OR_CREATE] Inserted link for raw_profile_id % to master_profile_id % with rule %', p_raw_profile.raw_profile_id, v_final_master_id, p_match_rule;
    EXCEPTION
        WHEN unique_violation THEN
            RAISE NOTICE '[LINK_OR_CREATE] Duplicate link skipped: raw_profile_id % already linked to master_profile_id %.', p_raw_profile.raw_profile_id, v_final_master_id;
        WHEN OTHERS THEN
            RAISE WARNING '[LINK_OR_CREATE] Failed to insert link for raw_profile_id % to master % (Rule: %): %', p_raw_profile.raw_profile_id, v_final_master_id, p_match_rule, SQLERRM;
    END;

    RETURN v_final_master_id;
END;
$$ LANGUAGE plpgsql;


----------------- identity_config_type -----------------------
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
    WHEN duplicate_object THEN NULL; -- Skip if TYPE already exists
END $$;


----------------- resolve_customer_identities_dynamic -----------------------
-- Main Logic Function (can be run manually)
CREATE OR REPLACE FUNCTION resolve_customer_identities_dynamic(
    batch_size INT DEFAULT 100,
    from_ts TIMESTAMPTZ DEFAULT NULL,
    to_ts TIMESTAMPTZ DEFAULT NULL
)
RETURNS VOID AS $$
DECLARE
    r_profile cdp_raw_profiles_stage;
    matched_master_id UUID;
    identity_configs_array identity_config_type[];
    v_where_conditions TEXT[] := '{}';
    v_condition_text TEXT;
    v_identity_config_rec identity_config_type;
    v_raw_value_text TEXT;
    v_master_col_name TEXT;
    v_dynamic_select_query TEXT;
    v_start_time TIMESTAMPTZ;
BEGIN
    v_start_time := NOW(); 
    RAISE NOTICE '[RESOLVE_IDENTITIES] Bắt đầu xử lý với batch_size % tại thời điểm %', batch_size, v_start_time;

    -- Bước 1: Đánh dấu trước batch
    -- Use FOR UPDATE SKIP LOCKED to avoid locking conflicts and deadlocks between concurrent workers
    WITH picked_rows AS (
        SELECT raw_profile_id
        FROM cdp_raw_profiles_stage
        WHERE status_code = 1
          AND NOT EXISTS (
              SELECT 1 FROM cdp_profile_links WHERE raw_profile_id = cdp_raw_profiles_stage.raw_profile_id
          )
          AND (from_ts IS NULL OR received_at >= from_ts)
          AND (to_ts IS NULL OR received_at <= to_ts)
        LIMIT batch_size
        FOR UPDATE SKIP LOCKED
    )
    UPDATE cdp_raw_profiles_stage r
    SET status_code = 2,
        updated_at = NOW()
    FROM picked_rows p
    WHERE r.raw_profile_id = p.raw_profile_id;

    -- Bước 2: Load các bản ghi đã đánh dấu
    FOR r_profile IN
        SELECT * FROM cdp_raw_profiles_stage
        WHERE status_code = 2
          AND (from_ts IS NULL OR received_at >= from_ts)
          AND (to_ts IS NULL OR received_at <= to_ts)
        ORDER BY updated_at
        LIMIT batch_size
    LOOP
        -- RAISE NOTICE '[RESOLVE_IDENTITIES] Đang xử lý raw_profile_id: % (tenant_id: %)', r_profile.raw_profile_id, r_profile.tenant_id;

        matched_master_id := NULL;
        v_where_conditions := '{}';

        -- Bước 3: Load cấu hình IR nếu chưa có
        IF identity_configs_array IS NULL THEN
            SELECT array_agg(
                ROW(id, attribute_internal_code, data_type, matching_rule, matching_threshold, consolidation_rule)::identity_config_type
            )
            INTO identity_configs_array
            FROM cdp_profile_attributes
            WHERE is_identity_resolution = TRUE
              AND status = 'ACTIVE'
              AND matching_rule IS NOT NULL
              AND matching_rule <> 'none';

            IF identity_configs_array IS NULL OR array_length(identity_configs_array, 1) = 0 THEN
                RAISE WARNING '[RESOLVE_IDENTITIES] Không có cấu hình IR đang hoạt động!';
                RETURN;
            END IF;
        END IF;

        -- Bước 4: Build điều kiện
        FOREACH v_identity_config_rec IN ARRAY identity_configs_array LOOP
            v_raw_value_text := NULL;

            CASE v_identity_config_rec.attr_code
                WHEN 'phone_number' THEN v_raw_value_text := r_profile.phone_number::TEXT;
                WHEN 'crm_source_id' THEN v_raw_value_text := r_profile.crm_source_id::TEXT;
                WHEN 'social_user_id' THEN v_raw_value_text := r_profile.social_user_id::TEXT;
                WHEN 'email' THEN v_raw_value_text := r_profile.email::TEXT;
                ELSE
                    BEGIN
                        SELECT r_profile.ext_attributes ->> v_identity_config_rec.attr_code
                        INTO v_raw_value_text;
                    EXCEPTION
                        WHEN OTHERS THEN
                            RAISE WARNING '[RESOLVE_IDENTITIES] Lỗi lấy ext_attr %: %', v_identity_config_rec.attr_code, SQLERRM;
                    END;
            END CASE;

            IF v_raw_value_text IS NOT NULL AND (
                (v_identity_config_rec.data_type IN ('VARCHAR', 'citext', 'TEXT') AND v_raw_value_text <> '')
                OR v_identity_config_rec.data_type NOT IN ('VARCHAR', 'citext', 'TEXT')
            ) THEN
                v_master_col_name := v_identity_config_rec.attr_code;

                -- Compose matching condition based on the matching rule
                CASE v_identity_config_rec.match_rule
                    WHEN 'exact' THEN
                        v_condition_text := format('mp.%I = %L', v_master_col_name, v_raw_value_text);
                    WHEN 'fuzzy_trgm' THEN
                        IF v_identity_config_rec.threshold IS NOT NULL THEN
                            v_condition_text := format('similarity(mp.%I, %L) >= %s', v_master_col_name, v_raw_value_text, v_identity_config_rec.threshold);
                        ELSE
                            RAISE WARNING '[RESOLVE_IDENTITIES] fuzzy_trgm thiếu threshold cho attr %', v_master_col_name;
                            CONTINUE;
                        END IF;
                    WHEN 'fuzzy_dmetaphone' THEN
                        v_condition_text := format('dmetaphone(mp.%I) = dmetaphone(%L)', v_master_col_name, v_raw_value_text);
                    ELSE
                        RAISE WARNING '[RESOLVE_IDENTITIES] match_rule không hợp lệ: %', v_identity_config_rec.match_rule;
                        CONTINUE;
                END CASE;

                v_where_conditions := array_append(v_where_conditions, v_condition_text);
            END IF;
        END LOOP;

        -- Bước 5: Dynamic SQL sử dụng UNION ALL
        IF array_length(v_where_conditions, 1) > 0 THEN
            v_dynamic_select_query := '';

            FOR i IN 1..array_length(v_where_conditions, 1) LOOP
                IF i > 1 THEN
                    v_dynamic_select_query := v_dynamic_select_query || ' UNION ALL ';
                END IF;

                v_dynamic_select_query := v_dynamic_select_query || format(
                    'SELECT mp.master_profile_id FROM cdp_master_profiles mp WHERE mp.tenant_id = %L AND %s',
                    r_profile.tenant_id,
                    v_where_conditions[i]
                );
            END LOOP;

            -- Lấy 1 bản ghi đầu tiên sau khi UNION
            v_dynamic_select_query := format(
                'SELECT master_profile_id FROM (%s) AS unioned LIMIT 1',
                v_dynamic_select_query
            );

            -- RAISE NOTICE '[RESOLVE_IDENTITIES] Query động (UNION): %', v_dynamic_select_query;

            BEGIN
                EXECUTE v_dynamic_select_query INTO matched_master_id;
            EXCEPTION
                WHEN OTHERS THEN
                    RAISE WARNING '[RESOLVE_IDENTITIES] Lỗi khi chạy query động: %', SQLERRM;
                    matched_master_id := NULL;
            END;
        END IF;

        -- Bước 6: Gọi hàm liên kết
        IF matched_master_id IS NOT NULL THEN
            matched_master_id := link_or_create_master_profile(r_profile, matched_master_id, 'DynamicMatch');
        ELSE
            matched_master_id := link_or_create_master_profile(r_profile, NULL, 'NewMaster');
        END IF;

       

        -- Bước 7: Cập nhật trạng thái đã xử lý
        UPDATE cdp_raw_profiles_stage
        SET status_code = 3,
            updated_at = NOW()
        WHERE raw_profile_id = r_profile.raw_profile_id;
    END LOOP;

    RAISE NOTICE '[RESOLVE_IDENTITIES] Kết thúc xử lý lúc %, tổng thời gian: %', NOW(), NOW() - v_start_time;
END;
$$ LANGUAGE plpgsql;


-- update (set status_code is 1 ) and return all master_profile_id need to be notified (WHERE status_code = 10)
CREATE OR REPLACE FUNCTION update_master_profiles_status(batch_size INT DEFAULT 10000)
RETURNS SETOF UUID
LANGUAGE plpgsql
AS $$
BEGIN
    RETURN QUERY
    WITH cte AS (
        SELECT ctid, master_profile_id
        FROM cdp_master_profiles
        WHERE status_code = 10
        LIMIT batch_size
        FOR UPDATE
    ),
    updated AS (
        UPDATE cdp_master_profiles p
        SET status_code = 1
        FROM cte
        WHERE p.ctid = cte.ctid
        RETURNING p.master_profile_id
    )
    SELECT master_profile_id FROM updated;
END;
$$;