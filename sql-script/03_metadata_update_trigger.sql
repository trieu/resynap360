
-- Function: Suggest index for updated attribute if eligible
CREATE OR REPLACE FUNCTION suggest_index_on_identity_attribute()
RETURNS TRIGGER AS $$
DECLARE
    v_index_sql TEXT;
BEGIN
    NEW.update_at = NOW();

    -- Only run if the attribute is active for identity resolution and indexing
    IF NEW.is_identity_resolution = TRUE AND NEW.is_index = TRUE AND NEW.status = 'ACTIVE' THEN
        CASE
            WHEN NEW.matching_rule = 'exact' AND NEW.data_type = 'citext' THEN
                v_index_sql := format('CREATE INDEX IF NOT EXISTS idx_raw_profiles_stage_%I_exact ON cdp_raw_profiles_stage (%I);',
                                      NEW.attribute_internal_code, NEW.attribute_internal_code);

            WHEN NEW.matching_rule = 'exact' THEN
                v_index_sql := format('CREATE INDEX IF NOT EXISTS idx_raw_profiles_stage_%I_btree ON cdp_raw_profiles_stage (%I);',
                                      NEW.attribute_internal_code, NEW.attribute_internal_code);

            WHEN NEW.matching_rule = 'fuzzy_trgm' THEN
                 -- Ensure pg_trgm extension is installed and enabled in the database
                v_index_sql := format('CREATE INDEX IF NOT EXISTS idx_raw_profiles_stage_%I_trgm ON cdp_raw_profiles_stage USING gin (%I gin_trgm_ops);',
                                      NEW.attribute_internal_code, NEW.attribute_internal_code);

            WHEN NEW.matching_rule = 'fuzzy_dmetaphone' THEN
                -- Ensure fuzzystrmatch extension is installed and enabled in the database
                v_index_sql := format('CREATE INDEX IF NOT EXISTS idx_raw_profiles_stage_%I_dmeta ON cdp_raw_profiles_stage USING btree (dmetaphone(%I));',
                                      NEW.attribute_internal_code, NEW.attribute_internal_code);

            ELSE
                -- No index rule matched for the given criteria
                RETURN NEW;
        END CASE;

        -- Log potential index command
        RAISE NOTICE 'Attempting to create index: %', v_index_sql;

        -- --- Error Handling Block ---
        BEGIN
            -- Execute the index dynamically
            EXECUTE v_index_sql;

            -- Log success if execution passes without error
            RAISE NOTICE 'Successfully executed index creation for attribute "%".', NEW.attribute_internal_code;

        EXCEPTION
            -- Catch the specific error for a non-existent column
            WHEN undefined_column THEN
                RAISE WARNING 'Could not create index for attribute "%" on table "cdp_raw_profiles_stage" because the column "%" does not exist. Index SQL attempted: "%"',
                              NEW.attribute_internal_code, NEW.attribute_internal_code, v_index_sql;
            -- Optional: Catch other potential errors during EXECUTE (e.g., missing extension function)
            WHEN OTHERS THEN
                 RAISE WARNING 'An unexpected error occurred while creating index for attribute "%". SQLSTATE: %, SQLERRM: %. Index SQL attempted: "%"',
                                NEW.attribute_internal_code, SQLSTATE, SQLERRM, v_index_sql;
        END; -- End Error Handling Block
        -- --- End Error Handling Block ---

    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;


-- Drop the existing trigger if it exists
DROP TRIGGER IF EXISTS after_profile_attribute_index_suggestion ON cdp_profile_attributes;

-- Trigger: Suggest index when relevant fields change
CREATE TRIGGER after_profile_attribute_index_suggestion
AFTER INSERT OR UPDATE ON cdp_profile_attributes
FOR EACH ROW
EXECUTE FUNCTION suggest_index_on_identity_attribute();

