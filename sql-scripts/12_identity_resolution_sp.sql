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

CREATE OR REPLACE FUNCTION resolve_customer_identities_dynamic(batch_size INT DEFAULT 1000)
RETURNS VOID AS $$
DECLARE
    r_profile cdp_raw_profiles_stage%ROWTYPE;
    matched_master_id UUID;
    identity_configs_array identity_config_type[];
    v_where_conditions TEXT[] := '{}';
    v_condition_text TEXT;
    v_identity_config_rec identity_config_type;
    v_raw_value_text TEXT;
    v_master_col_name TEXT;
    v_dynamic_select_query TEXT;
    v_update_set_clauses TEXT[] := '{}';
    v_insert_cols TEXT[] := '{}';
    v_insert_values TEXT[] := '{}';
    v_consolidate_config_rec RECORD;
    v_start_time TIMESTAMPTZ := NOW();
BEGIN
    -- Log function start
    RAISE NOTICE 'Starting resolve_customer_identities_dynamic at % with batch_size %', v_start_time, batch_size;

    -- 1. Fetch active IR configs
    RAISE NOTICE 'Fetching identity resolution configurations from cdp_profile_attributes';
    SELECT array_agg(
        ROW(id, attribute_internal_code, data_type, matching_rule, matching_threshold, consolidation_rule)::identity_config_type
    )
    INTO identity_configs_array
    FROM cdp_profile_attributes
    WHERE is_identity_resolution = TRUE
    AND status = 'ACTIVE'
    AND matching_rule IS NOT NULL
    AND matching_rule != 'none';

    -- Log config details
    IF identity_configs_array IS NOT NULL THEN
        RAISE NOTICE 'Found % active identity configs', array_length(identity_configs_array, 1);
        FOREACH v_identity_config_rec IN ARRAY identity_configs_array
        LOOP
            RAISE NOTICE 'Config ID: %, Attr: %, Type: %, Rule: %, Threshold: %', 
                v_identity_config_rec.id, 
                v_identity_config_rec.attr_code, 
                v_identity_config_rec.data_type, 
                v_identity_config_rec.match_rule, 
                v_identity_config_rec.threshold;
        END LOOP;
    ELSE
        RAISE WARNING 'No active identity resolution configs found. Exiting';
        RETURN;
    END IF;

    -- 2. Iterate through unprocessed raw profiles
    RAISE NOTICE 'Processing up to % unprocessed raw profiles', batch_size;
    FOR r_profile IN
        SELECT raw_profiles.*
        FROM public.cdp_raw_profiles_stage as raw_profiles
        LEFT JOIN public.cdp_profile_links as links
        ON raw_profiles.raw_profile_id = links.raw_profile_id
        WHERE links.raw_profile_id IS NULL
        LIMIT batch_size
    LOOP
        RAISE NOTICE 'Processing raw_profile_id: %', r_profile.raw_profile_id;
        matched_master_id := NULL;
        v_where_conditions := '{}';

        -- 3. Iterate over identity resolution configs
        FOREACH v_identity_config_rec IN ARRAY identity_configs_array
        LOOP
            v_raw_value_text := NULL;
            RAISE NOTICE 'Evaluating config for attribute: %', v_identity_config_rec.attr_code;

            -- 3.1 Map attribute code to raw profile values
            CASE v_identity_config_rec.attr_code
                WHEN 'phone_number' THEN v_raw_value_text := r_profile.phone_number::TEXT;
                WHEN 'crm_id' THEN v_raw_value_text := r_profile.crm_id::TEXT;
                WHEN 'zalo_user_id' THEN v_raw_value_text := r_profile.zalo_user_id::TEXT;
                WHEN 'email' THEN v_raw_value_text := r_profile.email::TEXT;
                ELSE
                    BEGIN
                        SELECT ext_attributes ->> v_identity_config_rec.attr_code
                        INTO v_raw_value_text
                        FROM cdp_raw_profiles_stage
                        WHERE raw_profile_id = r_profile.raw_profile_id;
                        RAISE NOTICE 'Fetched ext_attribute %: %', v_identity_config_rec.attr_code, v_raw_value_text;
                    EXCEPTION
                        WHEN OTHERS THEN
                            RAISE WARNING 'Failed to fetch ext_attribute %: %', v_identity_config_rec.attr_code, SQLERRM;
                    END;
            END CASE;

            -- 3.2 Validate raw value
            IF v_raw_value_text IS NOT NULL AND (
                v_identity_config_rec.data_type NOT IN ('VARCHAR', 'citext', 'TEXT') OR v_raw_value_text != ''
            ) THEN
                v_master_col_name := v_identity_config_rec.attr_code;
                v_condition_text := '';
                RAISE NOTICE 'Raw value for %: %', v_identity_config_rec.attr_code, v_raw_value_text;

                -- 3.3 Build match condition
                CASE v_identity_config_rec.match_rule
                    WHEN 'exact' THEN
                        v_condition_text := format('mp.%I = %L', v_master_col_name, v_raw_value_text);
                        RAISE NOTICE 'Built exact match condition: %', v_condition_text;

                    WHEN 'fuzzy_trgm' THEN
                        IF v_identity_config_rec.data_type IN ('VARCHAR', 'citext', 'TEXT') AND v_identity_config_rec.threshold IS NOT NULL THEN
                            v_condition_text := format('similarity(mp.%I, %L) >= %s', v_master_col_name, v_raw_value_text, v_identity_config_rec.threshold);
                            RAISE NOTICE 'Built fuzzy_trgm condition: %', v_condition_text;
                        ELSE
                            RAISE WARNING 'Invalid fuzzy_trgm config for %: invalid data_type or threshold', v_identity_config_rec.attr_code;
                        END IF;

                    WHEN 'fuzzy_dmetaphone' THEN
                        IF v_identity_config_rec.data_type IN ('VARCHAR', 'citext', 'TEXT') THEN
                            v_condition_text := format('dmetaphone(mp.%I) = dmetaphone(%L)', v_master_col_name, v_raw_value_text);
                            RAISE NOTICE 'Built fuzzy_dmetaphone condition: %', v_condition_text;
                        ELSE
                            RAISE WARNING 'Invalid fuzzy_dmetaphone config for %: invalid data_type', v_identity_config_rec.attr_code;
                        END IF;

                    ELSE
                        RAISE WARNING 'Unknown match_rule for %: %', v_identity_config_rec.attr_code, v_identity_config_rec.match_rule;
                        CONTINUE;
                END CASE;

                IF v_condition_text != '' THEN
                    v_where_conditions := array_append(v_where_conditions, '(' || v_condition_text || ')');
                END IF;
            ELSE
                RAISE NOTICE 'Skipping attribute %: invalid or null value', v_identity_config_rec.attr_code;
            END IF;
        END LOOP;

        -- 4. Execute dynamic match query
        IF array_length(v_where_conditions, 1) IS NOT NULL THEN
            v_dynamic_select_query := 'SELECT master_profile_id FROM cdp_master_profiles mp WHERE ' ||
                array_to_string(v_where_conditions, ' OR ') || ' LIMIT 1';
            RAISE NOTICE 'Executing dynamic query: %', v_dynamic_select_query;

            BEGIN
                EXECUTE v_dynamic_select_query INTO matched_master_id;
                RAISE NOTICE 'Query result - matched_master_id: %', matched_master_id;
            EXCEPTION
                WHEN OTHERS THEN
                    RAISE WARNING 'Query execution failed for raw_profile_id %: % - SQL: %', r_profile.raw_profile_id, SQLERRM, v_dynamic_select_query;
                    matched_master_id := NULL;
            END;
        ELSE
            RAISE NOTICE 'No valid match conditions for raw_profile_id %', r_profile.raw_profile_id;
        END IF;

        -- 5. Link raw to matched or insert new master
        IF matched_master_id IS NOT NULL THEN
            RAISE NOTICE 'Match found for raw_profile_id %: Linking to master_profile_id %', r_profile.raw_profile_id, matched_master_id;
            -- 5.1 Match found: update master profile and insert link
            BEGIN
                INSERT INTO cdp_profile_links (raw_profile_id, master_profile_id, match_rule)
                VALUES (r_profile.raw_profile_id, matched_master_id, 'DynamicMatch');
                RAISE NOTICE 'Inserted link for raw_profile_id % to master_profile_id %', r_profile.raw_profile_id, matched_master_id;
            EXCEPTION 
                WHEN unique_violation THEN
                    RAISE NOTICE 'Duplicate link skipped for raw_profile_id %', r_profile.raw_profile_id;
                    CONTINUE;
                WHEN OTHERS THEN
                    RAISE WARNING 'Failed to insert link for raw_profile_id %: %', r_profile.raw_profile_id, SQLERRM;
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
                updated_at = NOW(),
                last_seen_at = r_profile.last_seen_at,
                last_seen_touchpoint_id =  COALESCE(mp.last_seen_touchpoint_id, r_profile.last_seen_touchpoint_id),
                last_known_channel = COALESCE(mp.last_known_channel, r_profile.last_known_channel)
            WHERE mp.master_profile_id = matched_master_id;
            RAISE NOTICE 'Updated master_profile_id % with raw_profile_id % data', matched_master_id, r_profile.raw_profile_id;

        ELSE
            RAISE NOTICE 'No match found for raw_profile_id %: Creating new master profile', r_profile.raw_profile_id;
            -- 5.2 No match found: create new master profile and link
            INSERT INTO cdp_master_profiles (
                first_name, last_name, email, phone_number,
                address_line1, city, state, zip_code,
                source_systems, first_seen_raw_profile_id, web_visitor_ids, tenant_id, 
                last_seen_at, last_seen_touchpoint_id, last_known_channel
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
                r_profile.tenant_id,
                r_profile.last_seen_at,
                r_profile.last_seen_touchpoint_id,
                r_profile.last_known_channel
            )
            RETURNING master_profile_id INTO matched_master_id;
            RAISE NOTICE 'Created new master_profile_id % for raw_profile_id %', matched_master_id, r_profile.raw_profile_id;

            BEGIN
                INSERT INTO cdp_profile_links (raw_profile_id, master_profile_id, match_rule)
                VALUES (r_profile.raw_profile_id, matched_master_id, 'NewMaster');
                RAISE NOTICE 'Inserted link for raw_profile_id % to new master_profile_id %', r_profile.raw_profile_id, matched_master_id;
            EXCEPTION 
                WHEN unique_violation THEN
                    RAISE NOTICE 'Duplicate link skipped for raw_profile_id %', r_profile.raw_profile_id;
                    CONTINUE;
                WHEN OTHERS THEN
                    RAISE WARNING 'Failed to insert link for raw_profile_id %: %', r_profile.raw_profile_id, SQLERRM;
            END;
        END IF;


        RAISE NOTICE 'Marked raw_profile_id % as processed', r_profile.raw_profile_id;
    END LOOP;

    -- Log function completion
    RAISE NOTICE 'Completed resolve_customer_identities_dynamic at %, duration: %', NOW(), NOW() - v_start_time;
END;
$$ LANGUAGE plpgsql;