-- Main Logic Function (can be run manually)
CREATE OR REPLACE PROCEDURE process_new_raw_profiles()
LANGUAGE plpgsql
AS $$
DECLARE
    _unprocessed_count INTEGER;
    _batch_size INTEGER := 20;
    _total_max_process INTEGER := 1000;  -- Limit total records per session
    _total_processed INTEGER := 0;
    _to_process_this_batch INTEGER;
BEGIN
    LOOP
        -- Determine how many raw profiles are still unlinked
        SELECT COUNT(*) INTO _unprocessed_count
        FROM cdp_raw_profiles_stage r
        LEFT JOIN cdp_profile_links l ON r.raw_profile_id = l.raw_profile_id
        WHERE l.raw_profile_id IS NULL;

        -- Exit if none left
        EXIT WHEN _unprocessed_count = 0;

        -- Compute how many to process in this batch (respecting total max limit)
        _to_process_this_batch := LEAST(_batch_size, _total_max_process - _total_processed);

        -- Exit if we've reached the max allowed for this run
        EXIT WHEN _to_process_this_batch <= 0;

        -- Call identity resolution function for this batch
        PERFORM resolve_customer_identities_dynamic(_to_process_this_batch);

        -- Commit the transaction after batch
        COMMIT;

        -- Track how many we've processed
        _total_processed := _total_processed + _to_process_this_batch;
    END LOOP;
END;
$$;


-- set process_new_raw_profiles in every minute
CREATE EXTENSION IF NOT EXISTS pg_cron;
SELECT cron.schedule(
    'process_new_profiles_every_minute',
    '* * * * *',  -- every minute
    $$CALL process_new_raw_profiles();$$
);

-- Trigger Function (delegates to the above):
CREATE OR REPLACE FUNCTION process_new_raw_profiles_trigger_func()
RETURNS trigger AS $$
BEGIN
    -- Delegate the logic to the main processing function
    CALL process_new_raw_profiles();
    RETURN NULL; -- Required for AFTER trigger, FOR EACH STATEMENT
END;
$$ LANGUAGE plpgsql;