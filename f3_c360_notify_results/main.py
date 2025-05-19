import base64
import json
import os
import psycopg2
import socket


# --- Configuration from environment variables ---
DB_HOST = os.environ.get("DB_HOST")
DB_NAME = os.environ.get("DB_NAME")
DB_USER = os.environ.get("DB_USER")
DB_PASS = os.environ.get("DB_PASS")
DB_PORT = int(os.environ.get("DB_PORT", "5432"))
DB_BATCH_SIZE = int(os.environ.get("DB_BATCH_SIZE", "10000"))


def lambda_handler(event, context):
    print("🔥 [START] Lambda triggered. Using version 2025.05.19")

    db_connection = None
    updated_profiles = []

    # --- Check Reachability & Connect ---
    try:
        print(f"[DEBUG] Attempting to reach DB at {DB_HOST}:{DB_PORT}")
        socket.create_connection((DB_HOST, DB_PORT), timeout=3)
        print(f"✅ [REACHABLE] Host {DB_HOST}:{DB_PORT} is reachable")

        db_connection = psycopg2.connect(
            host=DB_HOST,
            database=DB_NAME,
            user=DB_USER,
            password=DB_PASS,
            port=DB_PORT,
            connect_timeout=5
        )
        with db_connection.cursor() as cursor:
            cursor.execute("SELECT 1;")
            _ = cursor.fetchone()
        print("✅ [DB CONNECT] Connection and health check successful.")
    except Exception as e:
        print(f"[FATAL] Database connection or health check failed: {str(e)}")
        return {"error": str(e)}

    # --- Validate Configuration ---
    missing_env = [var for var in ["DB_HOST", "DB_NAME", "DB_USER", "DB_PASS"] if not os.environ.get(var)]
    if missing_env:
        s = f"[CONFIG ERROR] Missing environment variables: {missing_env}"
        print(s)
        return {"error": s}

    # --- Run Batch Update Function ---
    try:
        sql = "SELECT * FROM update_master_profiles_status(%s);"
        with db_connection.cursor() as cursor:
            print(f"📦 Calling update_master_profiles_status({DB_BATCH_SIZE})")
            cursor.execute(sql, (DB_BATCH_SIZE,))
            rows = cursor.fetchall()
            updated_profiles = [str(row[0]) for row in rows]
            db_connection.commit()
            print(f"✅ [UPDATED] {len(updated_profiles)} profiles updated.")
    except Exception as e:
        print(f"[ERROR] Failed to execute update or fetch results: {str(e)}")
        return {"error": str(e)}
    finally:
        if db_connection:
            try:
                db_connection.close()
                print("✅ [DB CLOSED] Connection closed cleanly.")
            except Exception as e:
                print(f"[WARN] Error while closing DB connection: {str(e)}")

    print(f"✅ [COMPLETE] Processed {len(updated_profiles)} records.")
    return {"updated_profile_ids": updated_profiles}
