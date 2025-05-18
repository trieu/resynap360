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
    _total_max_process INTEGER := 5000;  -- limit total records per session
    _to_process_this_batch INTEGER;
    _from_ts TIMESTAMPTZ;
    _to_ts TIMESTAMPTZ;
    _latest_ts TIMESTAMPTZ;
    _total_processed INTEGER := 0;
BEGIN
    -- Get the latest unlinked and active profile timestamp
    SELECT r.received_at INTO _latest_ts
    FROM cdp_raw_profiles_stage r
    LEFT JOIN cdp_profile_links l ON r.raw_profile_id = l.raw_profile_id
    WHERE l.raw_profile_id IS NULL AND r.status_code = 1
    ORDER BY r.received_at DESC
    LIMIT 1;

    RAISE NOTICE 'Latest received_at: %', _latest_ts;

    -- Define time window: from (latest - 180m) to (latest + 1m)
    _to_ts := COALESCE(to_datetime, _latest_ts + INTERVAL '1 minute');
    _from_ts := COALESCE(from_datetime, _to_ts - INTERVAL '180 minutes');

    RAISE NOTICE 'Processing profiles from % to %', _from_ts, _to_ts;

    LOOP
        -- Count remaining unprocessed records in the time window
        SELECT COUNT(*) INTO _unprocessed_count
        FROM cdp_raw_profiles_stage r
        LEFT JOIN cdp_profile_links l ON r.raw_profile_id = l.raw_profile_id
        WHERE l.raw_profile_id IS NULL
          AND r.status_code = 1
          AND r.received_at BETWEEN _from_ts AND _to_ts;

        EXIT WHEN _unprocessed_count = 0;

        _to_process_this_batch := LEAST(_batch_size, _total_max_process - _total_processed);
        EXIT WHEN _to_process_this_batch <= 0;

        BEGIN
            PERFORM resolve_customer_identities_dynamic(_to_process_this_batch, _from_ts, _to_ts);
            _total_processed := _total_processed + _to_process_this_batch;

            RAISE NOTICE 'Processed % profiles (total so far: %)', _to_process_this_batch, _total_processed;
        EXCEPTION WHEN OTHERS THEN
            RAISE WARNING 'Error in batch: %, rolling back this batch', SQLERRM;
        END;
    END LOOP;
    -- Final info for pg_cron return_message
    RAISE INFO 'Total processed: %', _total_processed;
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


CREATE OR REPLACE FUNCTION cleanup_old_job_run_details(
    older_than_interval INTERVAL DEFAULT INTERVAL '12 hours'
) 
RETURNS INTEGER
LANGUAGE plpgsql
AS $$
DECLARE
    deleted_count INTEGER;
BEGIN
    DELETE FROM cron.job_run_details
    WHERE end_time <= NOW() - older_than_interval;

    GET DIAGNOSTICS deleted_count = ROW_COUNT;

    RAISE NOTICE 'Deleted % records older than %', deleted_count, older_than_interval;

    RETURN deleted_count;
END;
$$;

-- set cleanup_old_job_run_details_hourly in every hour
SELECT cron.schedule(
    'cleanup_old_job_run_details_hourly',
    '0 * * * *',  -- every hour at minute 0
    $$SELECT cleanup_old_job_run_details();$$
);

