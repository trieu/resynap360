
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
        RAISE NOTICE '[LINK_OR_CREATE] Match found for raw_profile_id %: Linking to master_profile_id % (tenant_id: %)', p_raw_profile.raw_profile_id, v_final_master_id, p_raw_profile.tenant_id;

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

            -- Contact Info (prefer raw if not null)
            email = COALESCE(p_raw_profile.email, mp.email),
            phone_number = COALESCE(p_raw_profile.phone_number, mp.phone_number),

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
            updated_at = NOW()
        WHERE mp.master_profile_id = v_final_master_id;
        RAISE NOTICE '[LINK_OR_CREATE] Updated master_profile_id % with raw_profile_id % data', v_final_master_id, p_raw_profile.raw_profile_id;

    ELSE
        RAISE NOTICE '[LINK_OR_CREATE] No match found for raw_profile_id % (tenant_id: %): Creating new master profile', p_raw_profile.raw_profile_id, p_raw_profile.tenant_id;
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
        RAISE NOTICE '[LINK_OR_CREATE] Created new master_profile_id % for raw_profile_id %', v_final_master_id, p_raw_profile.raw_profile_id;
    END IF;

    -- Link raw profile to master profile (either existing or new)
    BEGIN
        INSERT INTO cdp_profile_links (raw_profile_id, master_profile_id, match_rule)
        VALUES (p_raw_profile.raw_profile_id, v_final_master_id, p_match_rule);
        RAISE NOTICE '[LINK_OR_CREATE] Inserted link for raw_profile_id % to master_profile_id % with rule %', p_raw_profile.raw_profile_id, v_final_master_id, p_match_rule;
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
CREATE OR REPLACE FUNCTION resolve_customer_identities_dynamic(batch_size INT DEFAULT 1000)
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
    v_start_time TIMESTAMPTZ := NOW();
BEGIN
    -- Log function start
    RAISE NOTICE '[RESOLVE_IDENTITIES] Starting resolve_customer_identities_dynamic at % with batch_size %', v_start_time, batch_size;

    -- 1. Fetch active IR configs
    RAISE NOTICE '[RESOLVE_IDENTITIES] Fetching identity resolution configurations from cdp_profile_attributes';
    SELECT array_agg(
        ROW(id, attribute_internal_code, data_type, matching_rule, matching_threshold, consolidation_rule)::identity_config_type
    )
    INTO identity_configs_array
    FROM cdp_profile_attributes
    WHERE is_identity_resolution = TRUE
    AND status = 'ACTIVE'
    AND matching_rule IS NOT NULL
    AND matching_rule <> 'none'; -- Changed from != to <> for SQL standard

    -- Log config details
    IF identity_configs_array IS NULL OR array_length(identity_configs_array, 1) = 0 THEN
        RAISE WARNING '[RESOLVE_IDENTITIES] No active identity resolution configs found. Exiting';
        RETURN;
    END IF;
    RAISE NOTICE '[RESOLVE_IDENTITIES] Found % active identity configs', array_length(identity_configs_array, 1);
    FOREACH v_identity_config_rec IN ARRAY identity_configs_array
    LOOP
        RAISE NOTICE '[RESOLVE_IDENTITIES] Config ID: %, Attr: %, Type: %, Rule: %, Threshold: %',
            v_identity_config_rec.id,
            v_identity_config_rec.attr_code,
            v_identity_config_rec.data_type,
            v_identity_config_rec.match_rule,
            v_identity_config_rec.threshold;
    END LOOP;

    -- 2. Iterate through unprocessed raw profiles
    RAISE NOTICE '[RESOLVE_IDENTITIES] Processing up to % unprocessed raw profiles', batch_size;
    FOR r_profile IN
        SELECT raw_profiles.*
        FROM public.cdp_raw_profiles_stage as raw_profiles
        LEFT JOIN public.cdp_profile_links as links
        ON raw_profiles.raw_profile_id = links.raw_profile_id
        WHERE links.raw_profile_id IS NULL -- Only process profiles not yet linked
        AND raw_profiles.status_code = 1 -- Process only active raw profiles
        LIMIT batch_size
    LOOP
        RAISE NOTICE '[RESOLVE_IDENTITIES] Processing raw_profile_id: % for tenant_id: %', r_profile.raw_profile_id, r_profile.tenant_id;
        matched_master_id := NULL;
        v_where_conditions := '{}';

        -- 3. Iterate over identity resolution configs to build match conditions
        FOREACH v_identity_config_rec IN ARRAY identity_configs_array
        LOOP
            v_raw_value_text := NULL;
            -- RAISE NOTICE '[RESOLVE_IDENTITIES] Evaluating config for attribute: %', v_identity_config_rec.attr_code; -- Can be verbose

            -- 3.1 Map attribute code to raw profile values
            CASE v_identity_config_rec.attr_code
                WHEN 'phone_number' THEN v_raw_value_text := r_profile.phone_number::TEXT;
                WHEN 'crm_source_id' THEN v_raw_value_text := r_profile.crm_source_id::TEXT;
                WHEN 'social_user_id' THEN v_raw_value_text := r_profile.social_user_id::TEXT;
                WHEN 'email' THEN v_raw_value_text := r_profile.email::TEXT;
                -- Add other direct field mappings here if necessary
                ELSE -- Attempt to get from ext_attributes for dynamic attributes
                    BEGIN
                        SELECT r_profile.ext_attributes ->> v_identity_config_rec.attr_code
                        INTO v_raw_value_text;
                        -- IF v_raw_value_text IS NOT NULL THEN
                        --    RAISE NOTICE '[RESOLVE_IDENTITIES] Fetched ext_attribute %: %', v_identity_config_rec.attr_code, v_raw_value_text;
                        -- END IF;
                    EXCEPTION
                        WHEN OTHERS THEN
                            RAISE WARNING '[RESOLVE_IDENTITIES] Failed to fetch ext_attribute % for raw_profile_id %: %', v_identity_config_rec.attr_code, r_profile.raw_profile_id, SQLERRM;
                    END;
            END CASE;

            -- 3.2 Validate raw value and build condition
            IF v_raw_value_text IS NOT NULL AND (
                (v_identity_config_rec.data_type IN ('VARCHAR', 'citext', 'TEXT') AND v_raw_value_text <> '')
                OR v_identity_config_rec.data_type NOT IN ('VARCHAR', 'citext', 'TEXT') -- For non-text types, not-null is enough
            ) THEN
                v_master_col_name := v_identity_config_rec.attr_code; -- Assumes master profile has same column name
                v_condition_text := '';
                -- RAISE NOTICE '[RESOLVE_IDENTITIES] Raw value for %: %', v_identity_config_rec.attr_code, v_raw_value_text; -- Can be verbose

                -- 3.3 Build match condition based on rule
                CASE v_identity_config_rec.match_rule
                    WHEN 'exact' THEN
                        v_condition_text := format('mp.%I IS NOT DISTINCT FROM %L', v_master_col_name, v_raw_value_text);
                    WHEN 'fuzzy_trgm' THEN
                        IF v_identity_config_rec.data_type IN ('VARCHAR', 'citext', 'TEXT') AND v_identity_config_rec.threshold IS NOT NULL THEN
                            v_condition_text := format('similarity(mp.%I, %L) >= %s', v_master_col_name, v_raw_value_text, v_identity_config_rec.threshold);
                        ELSE
                            RAISE WARNING '[RESOLVE_IDENTITIES] Invalid fuzzy_trgm config for % (raw_profile_id %): invalid data_type or missing threshold', v_identity_config_rec.attr_code, r_profile.raw_profile_id;
                        END IF;
                    WHEN 'fuzzy_dmetaphone' THEN
                        IF v_identity_config_rec.data_type IN ('VARCHAR', 'citext', 'TEXT') THEN
                            v_condition_text := format('dmetaphone(mp.%I) = dmetaphone(%L)', v_master_col_name, v_raw_value_text);
                        ELSE
                            RAISE WARNING '[RESOLVE_IDENTITIES] Invalid fuzzy_dmetaphone config for % (raw_profile_id %): invalid data_type', v_identity_config_rec.attr_code, r_profile.raw_profile_id;
                        END IF;
                    ELSE
                        RAISE WARNING '[RESOLVE_IDENTITIES] Unknown match_rule for % (raw_profile_id %): %', v_identity_config_rec.attr_code, r_profile.raw_profile_id, v_identity_config_rec.match_rule;
                        CONTINUE;
                END CASE;

                IF v_condition_text <> '' THEN
                    v_where_conditions := array_append(v_where_conditions, '(' || v_condition_text || ')');
                END IF;
            -- ELSE
                -- RAISE NOTICE '[RESOLVE_IDENTITIES] Skipping attribute % for raw_profile_id %: invalid, null, or empty value', v_identity_config_rec.attr_code, r_profile.raw_profile_id; -- Verbose
            END IF;
        END LOOP;

        -- 4. Execute dynamic match query if conditions exist
        IF array_length(v_where_conditions, 1) > 0 THEN
            v_dynamic_select_query := format(
                'SELECT mp.master_profile_id FROM cdp_master_profiles mp WHERE mp.tenant_id IS NOT DISTINCT FROM %L AND (%s) LIMIT 1',
                r_profile.tenant_id,
                array_to_string(v_where_conditions, ' OR ')
            );
            RAISE NOTICE '[RESOLVE_IDENTITIES] Executing dynamic query for raw_profile_id %: %', r_profile.raw_profile_id, v_dynamic_select_query;

            BEGIN
                EXECUTE v_dynamic_select_query INTO matched_master_id;
                IF matched_master_id IS NOT NULL THEN
                    RAISE NOTICE '[RESOLVE_IDENTITIES] Query result for raw_profile_id % - matched_master_id: %', r_profile.raw_profile_id, matched_master_id;
                END IF;
            EXCEPTION
                WHEN OTHERS THEN
                    RAISE WARNING '[RESOLVE_IDENTITIES] Query execution failed for raw_profile_id %: % - SQL: %', r_profile.raw_profile_id, SQLERRM, v_dynamic_select_query;
                    matched_master_id := NULL;
            END;
        ELSE
            RAISE NOTICE '[RESOLVE_IDENTITIES] No valid attribute-based match conditions built for raw_profile_id % (tenant_id: %)', r_profile.raw_profile_id, r_profile.tenant_id;
        END IF;

        -- 5. Link raw profile to matched master or create a new master profile
        -- This entire block is now replaced by calling the new function
        IF matched_master_id IS NOT NULL THEN
            -- A match was found by the dynamic query
            matched_master_id := link_or_create_master_profile(r_profile, matched_master_id, 'DynamicMatch');
        ELSE
            -- No match found by dynamic query, or no conditions to query with
            matched_master_id := link_or_create_master_profile(r_profile, NULL, 'NewMaster');
        END IF;
        
        -- matched_master_id now holds the ID of the master profile (either existing or newly created and linked)
        -- If link_or_create_master_profile failed to link due to unique violation, it logs and returns the ID.
        -- If it failed more critically (not handled in current link_or_create_master_profile), matched_master_id might be NULL or unchanged.

        RAISE NOTICE '[RESOLVE_IDENTITIES] Finished processing for raw_profile_id %; associated master_profile_id: %', r_profile.raw_profile_id, COALESCE(matched_master_id::text, 'NONE');
    END LOOP;

    -- Log function completion
    RAISE NOTICE '[RESOLVE_IDENTITIES] Completed resolve_customer_identities_dynamic at %, duration: %', NOW(), NOW() - v_start_time;
END;
$$ LANGUAGE plpgsql;