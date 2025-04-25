-- Trigger function: Checks time interval before invoking identity resolution SP
CREATE OR REPLACE FUNCTION process_new_raw_profiles_trigger_func()
RETURNS TRIGGER AS $$
DECLARE
    now_datetime  TIMESTAMP WITH TIME ZONE := NOW();
BEGIN
    BEGIN
       
		RAISE WARNING 'PERFORM resolve_customer_identities_dynamic. now_datetime: % ', now_datetime;
		
		-- Update last_executed_at timestamp
		UPDATE cdp_id_resolution_status
        SET last_executed_at = now_datetime
        WHERE id = TRUE;

		-- Call the identity resolution stored procedure
		PERFORM resolve_customer_identities_dynamic();
       
    EXCEPTION
        WHEN OTHERS THEN
            RAISE WARNING 'Trigger error in process_new_raw_profiles_trigger_func: %', SQLERRM;
            RETURN NULL; -- Let the original INSERT/UPDATE succeed
    END;

    RETURN NULL; -- Required for AFTER trigger, FOR EACH STATEMENT
END;
$$ LANGUAGE plpgsql;
