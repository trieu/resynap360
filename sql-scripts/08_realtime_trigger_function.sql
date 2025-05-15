-- Main Logic Function (can be run manually)
CREATE OR REPLACE PROCEDURE process_new_raw_profiles(
    IN from_datetime TIMESTAMPTZ DEFAULT NULL,
    IN to_datetime TIMESTAMPTZ DEFAULT NULL,
    INOUT _total_processed INTEGER DEFAULT 0
)
LANGUAGE plpgsql
AS $$
DECLARE
    _unprocessed_count INTEGER;
    _batch_size INTEGER := 50;  -- default batch size
    _total_max_process INTEGER := 5000;  -- Limit total records per session
    _to_process_this_batch INTEGER;
    _from_ts TIMESTAMPTZ;
    _to_ts TIMESTAMPTZ;
BEGIN
    -- Handle default values for datetime range
    _to_ts := COALESCE(to_datetime, NOW());
    _from_ts := COALESCE(from_datetime, _to_ts - INTERVAL '30 minutes');

    -- Log time window for debugging
    RAISE NOTICE 'Processing profiles from % to %', _from_ts, _to_ts;

    LOOP
        -- Count unprocessed records within the given time range
        SELECT COUNT(*) INTO _unprocessed_count
        FROM cdp_raw_profiles_stage r
        LEFT JOIN cdp_profile_links l ON r.raw_profile_id = l.raw_profile_id
        WHERE l.raw_profile_id IS NULL
          AND _from_ts <= r.received_at AND r.received_at < _to_ts
          AND r.status_code = 1;

        -- Exit if nothing left
        EXIT WHEN _unprocessed_count = 0;

        -- Limit batch size based on remaining allowable total
        _to_process_this_batch := LEAST(_batch_size, _total_max_process - _total_processed);
        EXIT WHEN _to_process_this_batch <= 0;

        BEGIN
            -- Pass time window and batch size into resolver 
            -- PERFORM resolve_customer_identities_dynamic(_to_process_this_batch, _from_ts, _to_ts);
            PERFORM resolve_customer_identities_dynamic(_to_process_this_batch);

            -- Track processed count
            _total_processed := _total_processed + _to_process_this_batch;

            RAISE NOTICE 'Processed % profiles (total so far: %)', _to_process_this_batch, _total_processed;
        EXCEPTION WHEN OTHERS THEN
            -- Optional: log and continue
            RAISE WARNING 'Error in batch: %, rolling back this batch', SQLERRM;
        END;
    END LOOP;
END;
$$;



-- set process_new_raw_profiles in every minute
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