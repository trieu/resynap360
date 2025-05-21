import os
import json
import logging
from datetime import datetime, timedelta, timezone
import psycopg2

# --- Logger Setup ---
logger = logging.getLogger(__name__)
logger.setLevel(os.environ.get("LOG_LEVEL", "INFO").upper())

# --- Config ---
DB_HOST = os.environ.get("DB_HOST")
DB_NAME = os.environ.get("DB_NAME")
DB_USER = os.environ.get("DB_USER")
DB_PASS = os.environ.get("DB_PASS")
try:
    DB_PORT = int(os.environ.get("DB_PORT", "5432"))
    DB_BATCH_SIZE = int(os.environ.get("DB_BATCH_SIZE", "10000"))  # Not used here, but good to keep
except ValueError as e:
    logger.critical(f"Invalid non-integer value for DB_PORT or DB_BATCH_SIZE: {e}")
    DB_PORT, DB_BATCH_SIZE = 0, 0

# Runtime limits
DEFAULT_WINDOW_INTERVAL = timedelta(seconds=int(os.environ.get("WINDOW_INTERVAL_SECONDS", "15")))
DEFAULT_MAX_ITERATIONS = int(os.environ.get("MAX_ITERATIONS", "10000"))
DEFAULT_MAX_LOOP_DURATION = timedelta(hours=int(os.environ.get("MAX_LOOP_HOURS", "6")))


def get_db_connection():
    logger.debug(f"Connecting to DB at {DB_HOST}:{DB_PORT}")
    try:
        conn = psycopg2.connect(
            host=DB_HOST,
            database=DB_NAME,
            user=DB_USER,
            password=DB_PASS,
            port=DB_PORT,
            connect_timeout=5
        )
        with conn.cursor() as cursor:
            cursor.execute("SELECT 1;")
            if cursor.fetchone()[0] != 1:
                raise psycopg2.OperationalError("Health check failed.")
        logger.info("Database connection established.")
        return conn
    except psycopg2.Error as e:
        logger.error(f"Connection failed: {e}")
        raise


def call_process_new_raw_profiles(conn, from_dt: datetime, to_dt: datetime) -> int:
    """
    Calls the wrapper function which internally calls the stored procedure and returns OUT result.
    """
    with conn.cursor() as cursor:
        cursor.execute("SELECT call_process_new_raw_profiles_fn(%s, %s);", (from_dt, to_dt))
        result = cursor.fetchone()
        conn.commit()

        if result is None or result[0] is None:
            return 0  # Fall back to 0 if nothing was returned
        return result[0]




def lambda_handler(event, context):
    logger.info("Lambda triggered. Version 2025.05.21")

    missing = [k for k in ["DB_HOST", "DB_NAME", "DB_USER", "DB_PASS"] if not os.environ.get(k)]
    if missing:
        msg = f"Missing critical env vars: {missing}"
        logger.critical(msg)
        return {"statusCode": 500, "error": msg}

    if DB_PORT == 0 or DB_BATCH_SIZE == 0:
        msg = "Invalid DB_PORT or DB_BATCH_SIZE configuration."
        logger.critical(msg)
        return {"statusCode": 500, "error": msg}

    start_time = datetime.now(timezone.utc)
    current_target_time = event.get("initial_target_time")
    if current_target_time:
        current_target_time = datetime.fromisoformat(current_target_time)
    else:
        current_target_time = start_time

    window_interval = DEFAULT_WINDOW_INTERVAL
    max_iterations = DEFAULT_MAX_ITERATIONS
    max_duration = DEFAULT_MAX_LOOP_DURATION

    logger.info(f"Starting historical processing loop at {start_time.isoformat()}")
    logger.info(f"Initial target time: {current_target_time}, window size: {window_interval}, max iterations: {max_iterations}, max duration: {max_duration}")

    conn = None
    try:
        conn = get_db_connection()
        iteration_count = 0
        total_processed = 0

        while iteration_count < max_iterations:
            now = datetime.now(timezone.utc)
            if now - start_time > max_duration:
                logger.warning(f"Stopped due to max loop duration: {max_duration}")
                break

            iteration_count += 1
            to_dt = current_target_time
            from_dt = to_dt - window_interval

            logger.info(f"Iteration {iteration_count}: Processing from {from_dt} to {to_dt}")

            processed = call_process_new_raw_profiles(conn, from_dt, to_dt)
            logger.info(f"Iteration {iteration_count} complete. Records processed: {processed}")
            total_processed += processed
            current_target_time = from_dt  # Move window backwards

        elapsed = datetime.now(timezone.utc) - start_time
        logger.info(f"Processing complete. Iterations: {iteration_count}, Total processed: {total_processed}, Duration: {elapsed}")
        return {
            "statusCode": 200,
            "iterations": iteration_count,
            "total_processed": total_processed,
            "duration_seconds": elapsed.total_seconds()
        }

    except Exception as e:
        logger.exception("Unhandled error during Lambda execution")
        return {"statusCode": 500, "error": str(e)}

    finally:
        if conn:
            try:
                conn.close()
                logger.info("DB connection closed.")
            except Exception as e:
                logger.warning(f"Error closing DB connection: {e}")
