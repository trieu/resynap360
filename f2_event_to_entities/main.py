import base64
import json
import os
import psycopg2
import socket
from processor import convert_event_to_profile, save_to_postgresql


# --- load db_credentials ---
import db_utils
db_credentials = db_utils.get_db_credentials()
DB_HOST = db_credentials.get("DB_HOST")
DB_NAME = db_credentials.get("DB_NAME")
DB_USER = db_credentials.get("DB_USER")
DB_PASS = db_credentials.get("DB_PASS")
DB_PORT = int(db_credentials.get("DB_PORT", "5432"))

# batch size to commit
C360_RAW_PROFILE_BATCH_SIZE = int(os.environ.get("C360_RAW_PROFILE_BATCH_SIZE", "150"))   

def lambda_handler(event, context):
    print("🔥 [START] Lambda triggered. Using version 2025.05.15 10h")
    
    # --- Validate Configuration ---
    missing_env = [var for var in ["DB_HOST", "DB_NAME", "DB_USER", "DB_PASS"] if not db_credentials.get(var)]
    if missing_env:
        print(f"[CONFIG ERROR] Missing environment variables: {missing_env}")
        return {
            "records": [
                {"recordId": r['recordId'], "result": "ProcessingFailed", "data": r['data']}
                for r in records
            ]
        }

    records = event.get("records", [])
    output = []
    db_connection = None
    
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
        return {
            "records": [
                {"recordId": r['recordId'], "result": "ProcessingFailed", "data": r['data']}
                for r in records
            ]
        }


    # --- Process Each Record ---
    valid_profiles = []
    for record in records:
        record_id = record.get("recordId", "N/A")
        record_data = record.get("data", "") 
        print(f"✨ [PROCESSING] Record ID: {record_id}")

        try:
            # event to profile
            profile = convert_event_to_profile(record_data)
            
            # only save valid profiles
            valid_profiles.append(profile) 
            if len(valid_profiles) >= C360_RAW_PROFILE_BATCH_SIZE:
                 # --- Save batch to PostgreSQL ---
                save_to_postgresql(valid_profiles, db_connection)
                # reset batch 
                valid_profiles = []
             
            output.append({
                "recordId": record_id,
                "result": "Ok",
                "web_visitor_id": profile["web_visitor_id"]
            })
        except Exception as e:
            print(f"[ERROR] Record ID {record_id} failed: {str(e)}")
            output.append({
                "recordId": record_id,
                "result": "ProcessingFailed",
                "data": record["data"]
            })

    # check and flush all to PostgreSQL
    if len(valid_profiles) > 0:        
        save_to_postgresql(valid_profiles, db_connection)

    # --- Close Connection ---
    if db_connection:
        try:
            db_connection.close()
            print("✅ [DB CLOSED] Connection closed cleanly.")
        except Exception as e:
            print(f"[WARN] Error while closing DB connection: {str(e)}")

    print(f"✅ [COMPLETE] Processed {len(output)} records.")
    return {"records": output}