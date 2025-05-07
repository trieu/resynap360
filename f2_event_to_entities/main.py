import base64
import json
import os
import psycopg2
import socket
from processor import validate_phone_number, save_to_postgresql

# --- Configuration from environment variables ---
DB_HOST = os.environ.get("DB_HOST")
DB_NAME = os.environ.get("DB_NAME")
DB_USER = os.environ.get("DB_USER")
DB_PASS = os.environ.get("DB_PASS")
DB_PORT = int(os.environ.get("DB_PORT", "5432"))


def lambda_handler(event, context):
    print("🔥 [START] Lambda triggered by Firehose version 2025.05.06-09.41")

    records = event.get("records", [])
    output = []
    db_connection = None

    # --- Validate Configuration ---
    missing_env = [var for var in ["DB_HOST", "DB_NAME", "DB_USER", "DB_PASS"] if not os.environ.get(var)]
    if missing_env:
        print(f"[CONFIG ERROR] Missing environment variables: {missing_env}")
        return {
            "records": [
                {"recordId": r['recordId'], "result": "ProcessingFailed", "data": r['data']}
                for r in records
            ]
        }

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
    for record in records:
        record_id = record.get("recordId", "N/A")
        print(f"✨ [PROCESSING] Record ID: {record_id}")

        try:
            decoded_bytes = base64.b64decode(record['data'])
            decoded_str = decoded_bytes.decode('utf-8')
            event_data = json.loads(decoded_str)
            tenant_id = event_data.get("tenant_id")
            web_visitor_id = event_data.get("visid")
            profile = event_data.get("profile_traits", {})
            
            # Add tenant_id into the profile if available
            if tenant_id:
                profile["tenant_id"] = tenant_id

            # Add web_visitor_id into the profile if available
            if web_visitor_id:
                profile["web_visitor_id"] = web_visitor_id
            
            # check for phone_number
            phone_number = profile.get("phone_number")
            if phone_number and not validate_phone_number(phone_number):
                raise ValueError(f"Invalid or missing phone_number number: '{phone_number}'")


            # check for phone_number
            first_name = profile.get("first_name")
            if first_name and not first_name:
                raise ValueError("Missing required field: first_name")
            

            save_to_postgresql(profile, db_connection)
            print(f"✅ [SAVED] Record ID: {record_id}")

            output.append({
                "recordId": record_id,
                "result": "Ok",
                "data": record["data"]
            })

        except Exception as e:
            print(f"[ERROR] Record ID {record_id} failed: {str(e)}")
            output.append({
                "recordId": record_id,
                "result": "ProcessingFailed",
                "data": record["data"]
            })

    # --- Close Connection ---
    if db_connection:
        try:
            db_connection.close()
            print("✅ [DB CLOSED] Connection closed cleanly.")
        except Exception as e:
            print(f"[WARN] Error while closing DB connection: {str(e)}")

    print(f"✅ [COMPLETE] Processed {len(output)} records.")
    return {"records": output}
