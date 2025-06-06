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
    _batch_size INTEGER := 100; -- default batch size
    _total_max_process INTEGER := 10000; -- limit total records per session
    _to_process_this_batch INTEGER;
    _from_ts TIMESTAMPTZ;
    _to_ts TIMESTAMPTZ;
    _latest_ts TIMESTAMPTZ;
    _log_id BIGINT;
    _tenant_id TEXT := 'demo'; -- default tenant_id, can be parameterized if needed
    _existing_status TEXT;
BEGIN
    -- Determine time range first
    SELECT r.received_at INTO _latest_ts
    FROM cdp_raw_profiles_stage r
    LEFT JOIN cdp_profile_links l ON r.raw_profile_id = l.raw_profile_id
    WHERE l.raw_profile_id IS NULL AND r.status_code = 1
    ORDER BY r.received_at DESC
    LIMIT 1;

    IF _latest_ts IS NULL THEN
        RAISE INFO 'No unlinked raw profiles found. Exiting without processing.';
        RETURN;
    END IF;

    -- Define time window: from (latest - 180m) to (latest + 1m)
    _to_ts := COALESCE(to_datetime, _latest_ts + INTERVAL '1 minute');
    _from_ts := COALESCE(from_datetime, _to_ts - INTERVAL '180 minutes');

    RAISE NOTICE 'Processing profiles from % to %', _from_ts, _to_ts;

    -- Check for existing success or in-progress job for same time window
    SELECT job_status INTO _existing_status
    FROM cdp_id_resolution_status
    WHERE tenant_id = _tenant_id
      AND data_from_datetime = _from_ts
      AND data_to_datetime = _to_ts
      AND job_status IN ('success', 'processing')
    LIMIT 1;

    
    IF FOUND THEN
        RAISE NOTICE 'Skipping run: Job already exists with status % for this time range [% - %]', _existing_status, _from_ts, _to_ts;
        RETURN;
    END IF;
    -- If FOUND is FALSE, there’s no existing job → proceed with resolution and logging.

    -- Insert log entry
    INSERT INTO cdp_id_resolution_status (
        tenant_id, data_from_datetime, data_to_datetime,
        job_status, job_started_at
    ) VALUES (
        _tenant_id, _from_ts, _to_ts,
        'processing', now()
    ) RETURNING id INTO _log_id;

    BEGIN
        LOOP
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

        RAISE INFO 'Total processed: %', _total_processed;

        UPDATE cdp_id_resolution_status
        SET job_status = 'success',
            processed_count = _total_processed,
            job_completed_at = now(),
            updated_at = now()
        WHERE id = _log_id;

    EXCEPTION WHEN OTHERS THEN
        UPDATE cdp_id_resolution_status
        SET job_status = 'failed',
            error_message = SQLERRM,
            job_completed_at = now(),
            updated_at = now()
        WHERE id = _log_id;
        RAISE;
    END;
END;
$$;

-- for python to call process_new_raw_profiles and get the count of processed records
CREATE OR REPLACE FUNCTION call_process_new_raw_profiles_fn(
    from_datetime TIMESTAMPTZ DEFAULT NOW() - INTERVAL '3 hours',
    to_datetime TIMESTAMPTZ DEFAULT NOW()
) RETURNS INTEGER AS $$
DECLARE
    _processed INTEGER := 0;
BEGIN
    CALL process_new_raw_profiles(from_datetime, to_datetime, _processed);
    RETURN _processed;
END;
$$ LANGUAGE plpgsql;


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

