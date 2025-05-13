
-- Main Logic Function (can be run manually)
CREATE OR REPLACE FUNCTION process_new_raw_profiles()
RETURNS void AS $$
DECLARE
    _status RECORD;
    _current_trigger_time TIMESTAMPTZ := NOW();
    _delay_seconds INTEGER := 5;
    _sp_actual_start_time TIMESTAMPTZ;
BEGIN
    -- Attempt to get an exclusive lock on the status row.
    -- If another transaction has it (meaning another trigger fired and is active),
    -- this statement will wait until that lock is released.
    -- This is the primary mechanism for serialization and avoiding race conditions.
    BEGIN
        SELECT * INTO _status FROM cdp_id_resolution_status WHERE id = TRUE FOR UPDATE;
    EXCEPTION
        WHEN lock_not_available THEN
            RAISE NOTICE '[TID:%] Could not acquire lock on cdp_id_resolution_status immediately. Another transaction may hold it. Trigger time: %',
                         pg_backend_pid(), _current_trigger_time;
            -- Depending on desired behavior, you might want to retry or simply exit.
            -- For now, exiting as the other transaction should handle it.
            RETURN;
    END;

    -- Check if another instance is already marked as processing.
    -- This handles the case where multiple triggers fired, queued for the FOR UPDATE lock,
    -- and the first one is now processing. Subsequent ones, after acquiring the lock,
    -- will see is_processing = TRUE.
    IF _status.is_processing THEN
        RAISE NOTICE '[TID:%] SP execution is already in progress or scheduled by another trigger. is_processing=TRUE. Current trigger time: %, Lock holder started at: %',
                     pg_backend_pid(), _current_trigger_time, _status.processing_started_at;
        RETURN; -- Do nothing; let the other process complete. The FOR UPDATE lock is released at TX end.
    END IF;

    -- This trigger instance will handle the execution.
    -- Mark that processing is starting and record the time.
    UPDATE cdp_id_resolution_status
    SET is_processing = TRUE,
        processing_started_at = _current_trigger_time
    WHERE id = TRUE;
    -- The FOR UPDATE lock is still held by this transaction.

    RAISE NOTICE '[TID:%] Lock acquired. is_processing set to TRUE. Will wait % seconds. Trigger time: %, Effective processing start: %',
                 pg_backend_pid(), _delay_seconds, _current_trigger_time, _current_trigger_time;

    -- Wait for the specified delay.
    -- This pg_sleep happens *within* the transaction that fired the trigger.
    -- This means the original INSERT/UPDATE statement that caused this trigger to fire
    -- will not complete until this entire function (including the sleep and SP call) completes.
    PERFORM pg_sleep(_delay_seconds);

    -- Record the actual time the SP is called
    _sp_actual_start_time := NOW();
    BEGIN
        RAISE NOTICE '[TID:%] Performing resolve_customer_identities_dynamic. Actual SP call at: % (after %s delay)',
                     pg_backend_pid(), _sp_actual_start_time, _delay_seconds;

        -- Call the identity resolution stored procedure
        PERFORM resolve_customer_identities_dynamic();

        -- Success: Update last execution timestamp and release the processing lock.
        UPDATE cdp_id_resolution_status
        SET last_successful_execution_completed_at = NOW(),
            is_processing = FALSE,
            processing_started_at = NULL -- Clear as processing is done
        WHERE id = TRUE;
        RAISE NOTICE '[TID:%] SP resolve_customer_identities_dynamic completed. is_processing set to FALSE.', pg_backend_pid();

    EXCEPTION
        WHEN OTHERS THEN
            -- Error during SP execution: Release the processing lock but do not update last_successful_execution_completed_at.
            UPDATE cdp_id_resolution_status
            SET is_processing = FALSE,
                processing_started_at = NULL -- Clear as processing attempt failed/ended
            WHERE id = TRUE;
            RAISE WARNING '[TID:%] Error during or after SP call for resolve_customer_identities_dynamic: %. is_processing set to FALSE.', pg_backend_pid(), SQLERRM;
            -- Let the caller (manual or trigger) continue, but the SP logic encountered an issue.
            RETURN;
    END;
    -- The FOR UPDATE lock on cdp_id_resolution_status row is released when this transaction commits.
END;
$$ LANGUAGE plpgsql;

CREATE EXTENSION IF NOT EXISTS pg_cron;

-- set process_new_raw_profiles in every minute
SELECT cron.schedule(
    'process_new_profiles_every_minute',
    '* * * * *',  -- every minute
    $$SELECT process_new_raw_profiles();$$
);


-- Trigger Function (delegates to the above):
CREATE OR REPLACE FUNCTION process_new_raw_profiles_trigger_func()
RETURNS trigger AS $$
BEGIN
    -- Delegate the logic to the main processing function
    PERFORM process_new_raw_profiles();
    RETURN NULL; -- Required for AFTER trigger, FOR EACH STATEMENT
END;
$$ LANGUAGE plpgsql;
