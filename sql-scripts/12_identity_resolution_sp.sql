-- 1. Define the TYPE used for dynamic identity resolution config
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

-- 2. Main function for dynamic identity resolution
CREATE OR REPLACE FUNCTION resolve_customer_identities_dynamic(batch_size INT DEFAULT 1000)
RETURNS VOID AS $$
DECLARE
    -- Row variable for raw profile records
    r_profile cdp_raw_profiles_stage%ROWTYPE;

    -- ID of matched master profile (if found)
    matched_master_id UUID;

    -- Array of identity resolution configurations
    identity_configs_array identity_config_type[];

    -- Dynamic WHERE conditions for matching query
    v_where_conditions TEXT[] := '{}';
    v_condition_text TEXT;

    -- Loop variables for config
    v_identity_config_rec identity_config_type;
    v_raw_value_text TEXT;
    v_master_col_name TEXT;

    -- Final dynamic SQL query for matching
    v_dynamic_select_query TEXT;

    -- Unused dynamic consolidation placeholders
    v_update_set_clauses TEXT[] := '{}';
    v_insert_cols TEXT[] := '{}';
    v_insert_values TEXT[] := '{}';
    v_consolidate_config_rec RECORD;

BEGIN
    -- 1. Fetch active IR configs from attribute config table
    SELECT array_agg(
        ROW(id, attribute_internal_code, data_type, matching_rule, matching_threshold, consolidation_rule)::identity_config_type
    )
    INTO identity_configs_array
    FROM cdp_profile_attributes
    WHERE is_identity_resolution = TRUE
      AND status = 'ACTIVE'
      AND matching_rule IS NOT NULL
      AND matching_rule != 'none';

    -- If no config found, skip
    IF identity_configs_array IS NULL OR array_length(identity_configs_array, 1) IS NULL THEN
        RAISE WARNING 'Config table cdp_profile_attributes is empty. Skipping resolve_customer_identities_dynamic. Exiting';
        RETURN;
    END IF;

    -- 2. Iterate through raw profiles that haven't been processed
    FOR r_profile IN
        SELECT *
        FROM cdp_raw_profiles_stage
        WHERE processed_at IS NULL
        LIMIT batch_size
    LOOP
        matched_master_id := NULL;
        v_where_conditions := '{}';

        -- 3. Iterate over identity resolution configs
        FOREACH v_identity_config_rec IN ARRAY identity_configs_array
        LOOP
            v_raw_value_text := NULL;

            -- 3.1 Map attribute code to actual column values in raw profile
            CASE v_identity_config_rec.attr_code
                WHEN 'web_visitor_id' THEN v_raw_value_text := r_profile.web_visitor_id::TEXT;
                WHEN 'phone_number' THEN v_raw_value_text := r_profile.phone_number::TEXT;
                WHEN 'crm_id' THEN v_raw_value_text := r_profile.crm_id::TEXT;
                WHEN 'zalo_user_id' THEN v_raw_value_text := r_profile.zalo_user_id::TEXT;
                WHEN 'email' THEN v_raw_value_text := r_profile.email::TEXT;                
                ELSE
                    -- Attempt to fetch from ext_attributes JSONB
                    BEGIN
                        SELECT ext_attributes ->> v_identity_config_rec.attr_code
                        INTO v_raw_value_text;
                    EXCEPTION
                        WHEN OTHERS THEN
                            RAISE WARNING 'Unsupported attribute or ext_attributes missing: "%" - Error: %', v_identity_config_rec.attr_code, SQLERRM;
                    END;
            END CASE;

            -- 3.2 Validate the raw value before creating match conditions
            IF v_raw_value_text IS NOT NULL AND (
                v_identity_config_rec.data_type NOT IN ('VARCHAR', 'citext', 'TEXT') OR v_raw_value_text != ''
            ) THEN
                v_master_col_name := v_identity_config_rec.attr_code;
                v_condition_text := '';

                -- 3.3 Build match condition based on configured match_rule
                CASE v_identity_config_rec.match_rule
                    WHEN 'exact' THEN
                        v_condition_text := format('mp.%I = %L', v_master_col_name, v_raw_value_text);

                    WHEN 'fuzzy_trgm' THEN
                        IF v_identity_config_rec.data_type IN ('VARCHAR', 'citext', 'TEXT') AND v_identity_config_rec.threshold IS NOT NULL THEN
                            v_condition_text := format('similarity(mp.%I, %L) >= %s', v_master_col_name, v_raw_value_text, v_identity_config_rec.threshold);
                        ELSE
                            RAISE WARNING 'Invalid fuzzy_trgm config for "%".', v_identity_config_rec.attr_code;
                        END IF;

                    WHEN 'fuzzy_dmetaphone' THEN
                        IF v_identity_config_rec.data_type IN ('VARCHAR', 'citext', 'TEXT') THEN
                            v_condition_text := format('dmetaphone(mp.%I) = dmetaphone(%L)', v_master_col_name, v_raw_value_text);
                        ELSE
                            RAISE WARNING 'Invalid fuzzy_dmetaphone config for "%".', v_identity_config_rec.attr_code;
                        END IF;

                    ELSE
                        RAISE WARNING 'Unknown match_rule: %', v_identity_config_rec.match_rule;
                        CONTINUE;
                END CASE;

                IF v_condition_text != '' THEN
                    v_where_conditions := array_append(v_where_conditions, '(' || v_condition_text || ')');
                END IF;
            END IF;
        END LOOP;

        -- 4. Execute dynamic match query against master profile table
        IF array_length(v_where_conditions, 1) IS NOT NULL THEN
            v_dynamic_select_query := 'SELECT master_profile_id FROM cdp_master_profiles mp WHERE ' ||
                                      array_to_string(v_where_conditions, ' OR ') || ' LIMIT 1';

            BEGIN
                EXECUTE v_dynamic_select_query INTO matched_master_id;
            EXCEPTION
                WHEN OTHERS THEN
                    RAISE WARNING 'Query execution failed: % - SQL: %', SQLERRM, v_dynamic_select_query;
                    matched_master_id := NULL;
            END;
        END IF;

        -- 5. Link raw to matched or insert new master
        IF matched_master_id IS NOT NULL THEN
            -- 5.1 Match found: update master profile and insert link
            BEGIN
                INSERT INTO cdp_profile_links (raw_profile_id, master_profile_id, match_rule)
                VALUES (r_profile.raw_profile_id, matched_master_id, 'DynamicMatch');
            EXCEPTION WHEN unique_violation THEN
                CONTINUE; -- Skip duplicate links
            END;

            UPDATE cdp_master_profiles mp
            SET
                first_name = COALESCE(mp.first_name, r_profile.first_name),
                last_name = COALESCE(mp.last_name, r_profile.last_name),
                email = COALESCE(mp.email, r_profile.email),
                phone_number = COALESCE(mp.phone_number, r_profile.phone_number),
                address_line1 = COALESCE(mp.address_line1, r_profile.address_line1),
                city = COALESCE(mp.city, r_profile.city),
                state = COALESCE(mp.state, r_profile.state),
                zip_code = COALESCE(mp.zip_code, r_profile.zip_code),
                source_systems = (
                    SELECT array_agg(DISTINCT elem)
                    FROM unnest(mp.source_systems || r_profile.source_system) AS elem
                ),
                web_visitor_ids = (
                    SELECT array_agg(DISTINCT elem)
                    FROM unnest(mp.web_visitor_ids || r_profile.web_visitor_id) AS elem
                ),
                tenant_id = COALESCE(mp.tenant_id, r_profile.tenant_id),
                updated_at = NOW()
            WHERE mp.master_profile_id = matched_master_id;

        ELSE
            -- 5.2 No match found: create new master profile and link
            INSERT INTO cdp_master_profiles (
                first_name, last_name, email, phone_number,
                address_line1, city, state, zip_code,
                source_systems, first_seen_raw_profile_id, web_visitor_ids, tenant_id
            )
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
                r_profile.raw_profile_id,
                ARRAY[r_profile.web_visitor_id],
                r_profile.tenant_id
            )
            RETURNING master_profile_id INTO matched_master_id;

            BEGIN
                INSERT INTO cdp_profile_links (raw_profile_id, master_profile_id, match_rule)
                VALUES (r_profile.raw_profile_id, matched_master_id, 'NewMaster');
            EXCEPTION WHEN unique_violation THEN
                CONTINUE;
            END;
        END IF;

        -- 6. Mark raw profile as processed
        UPDATE cdp_raw_profiles_stage
        SET processed_at = NOW(), processing_status = 'processed'
        WHERE raw_profile_id = r_profile.raw_profile_id;

    END LOOP;

END;
$$ LANGUAGE plpgsql;
