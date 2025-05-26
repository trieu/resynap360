import json
import os
import psycopg2
import logging # Use the logging module for more control

# --- Logger Setup ---
# In AWS Lambda, the root logger is often pre-configured.
# You can get a specific logger for your module if preferred.
logger = logging.getLogger(__name__)
logger.setLevel(os.environ.get("LOG_LEVEL", "INFO").upper()) # Allow configuring log level

# --- Configuration from environment variables ---
# Grouping configuration makes it easier to manage
DB_HOST = os.environ.get("DB_HOST")
DB_NAME = os.environ.get("DB_NAME")
DB_USER = os.environ.get("DB_USER")
DB_PASS = os.environ.get("DB_PASS")
try:
    DB_PORT = int(os.environ.get("DB_PORT", "5432"))
    DB_BATCH_SIZE = int(os.environ.get("DB_BATCH_SIZE", "10000"))
except ValueError as e:
    logger.critical(f"Invalid non-integer value for DB_PORT or DB_BATCH_SIZE: {e}")
    # For a Lambda, critical errors that prevent startup should ideally raise
    # an exception to signal a failed initialization if this setup were global.
    # In the handler, we'll check if they are properly set.
    DB_PORT = 0 # Indicate error
    DB_BATCH_SIZE = 0 # Indicate error


def get_db_connection():
    """
    Establishes and returns a database connection.
    Raises an exception if connection fails.
    """
    logger.debug(f"Attempting to connect to DB at {DB_HOST}:{DB_PORT}")
    try:
        conn = psycopg2.connect(
            host=DB_HOST,
            database=DB_NAME,
            user=DB_USER,
            password=DB_PASS,
            port=DB_PORT,
            connect_timeout=5  # Seconds
        )
        # Optional: Simple health check after connection
        with conn.cursor() as cursor:
            cursor.execute("SELECT 1;")
            if cursor.fetchone()[0] != 1:
                raise psycopg2.OperationalError("Database health check (SELECT 1) failed.")
        logger.info("Database connection and health check successful.")
        return conn
    except psycopg2.Error as e:
        logger.error(f"Database connection failed: {e}")
        raise  # Re-raise the exception to be caught by the handler


def call_update_master_profiles_status_procedure(connection, batch_size):
    """
    Calls the database stored procedure to update profiles.
    """
    updated_profile_ids = []
    sql = "SELECT * FROM update_master_profiles_status(%s);"
    try:
        # The connection itself can be used as a context manager for transactions
        with connection: # This will automatically commit on success or rollback on error within the block
            with connection.cursor() as cursor:
                logger.info(f"Calling stored procedure: update_master_profiles_status with batch_size={batch_size}")
                cursor.execute(sql, (batch_size,))
                rows = cursor.fetchall()
                updated_profile_ids = [str(row[0]) for row in rows]
        logger.info(f"Successfully executed procedure. {len(updated_profile_ids)} profiles reported as updated.")
        return updated_profile_ids
    except psycopg2.Error as e:
        logger.error(f"Failed to execute update procedure or fetch results: {e}")
        raise # Re-raise to be handled by the main handler


def lambda_handler(event, context):
    logger.info("Lambda triggered. Version 2025.05.19 (Refactored)")

    # --- Validate Essential Configuration ---
    required_env_vars = {
        "DB_HOST": DB_HOST,
        "DB_NAME": DB_NAME,
        "DB_USER": DB_USER,
        "DB_PASS": DB_PASS
    }
    missing_vars = [key for key, value in required_env_vars.items() if not value]
    if missing_vars:
        error_msg = f"Configuration Error: Missing critical environment variables: {missing_vars}"
        logger.critical(error_msg)
        return {"statusCode": 500, "error": error_msg}

    if DB_PORT == 0 or DB_BATCH_SIZE == 0: # Check for conversion errors from global scope
        error_msg = "Configuration Error: DB_PORT or DB_BATCH_SIZE is invalid."
        logger.critical(error_msg)
        return {"statusCode": 500, "error": error_msg}


    db_connection = None
    try:
        db_connection = get_db_connection()
        updated_profiles = call_update_master_profiles_status_procedure(db_connection, DB_BATCH_SIZE)

        logger.info(f"Process complete. {len(updated_profiles)} records processed.")
        return {"statusCode": 200, "updated_profile_ids": updated_profiles}

    except psycopg2.Error as e: # Catch specific psycopg2 errors from helper functions
        # Errors are already logged by helper functions
        return {"statusCode": 500, "error": f"Database operation failed: {str(e)}"}
    except Exception as e:
        logger.exception(f"An unexpected error occurred: {e}") # logger.exception includes stack trace
        return {"statusCode": 500, "error": f"An unexpected error occurred: {str(e)}"}
    finally:
        if db_connection:
            try:
                db_connection.close()
                logger.info("Database connection closed cleanly.")
            except Exception as e:
                logger.warning(f"Error while closing DB connection: {e}")