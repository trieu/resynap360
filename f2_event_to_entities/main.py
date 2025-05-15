import base64
import json
import os
import psycopg2
import socket
from processor import create_uuid_from_string, has_string_value, is_valid_basic_phone, is_valid_email, save_to_postgresql

# --- Configuration from environment variables ---
DB_HOST = os.environ.get("DB_HOST")
DB_NAME = os.environ.get("DB_NAME")
DB_USER = os.environ.get("DB_USER")
DB_PASS = os.environ.get("DB_PASS")
DB_PORT = int(os.environ.get("DB_PORT", "5432"))
DB_BATCH_SIZE = int(os.environ.get("DB_BATCH_SIZE", "150"))   

def lambda_handler(event, context):
    print("🔥 [START] Lambda triggered. Using version 2025.05.15 10h")

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

    # --- Process Each Record ---
    valid_profiles = []
    for record in records:
        record_id = record.get("recordId", "N/A")
        print(f"✨ [PROCESSING] Record ID: {record_id}")

        try:
            decoded_bytes = base64.b64decode(record['data'])
            decoded_str = decoded_bytes.decode('utf-8')
            #
            event_data = json.loads(decoded_str)
            
            tenant_id = event_data.get("tenant_id",'')
            observer_id = event_data.get("observer_id",'')
            mediahost = event_data.get("mediahost",'')
            schema_version = event_data.get("schema_version",'')
            
            web_visitor_id = event_data.get("visid")
            profile = event_data.get("profile_traits", {})
            profile["tenant_id"] = tenant_id         
            
            # if event has phone_number, check for valid phone_number  
            phone_number = profile.get("phone_number") # this is the field name in PGSQL table schema
            if has_string_value(phone_number) and not is_valid_basic_phone(phone_number):
                raise ValueError(f"Invalid phone_number: '{phone_number}'")

            # if event has email, check for valid email   
            email = profile.get("email")
            if has_string_value(email) and not is_valid_email(email):
                raise ValueError(f"Invalid email: '{email}'")
            
            # check web_visitor_id to convert from event to entity
            if has_string_value(web_visitor_id):
                # mapping from JavaScript SDK Event Schema to PGSQL Table Schema
                profile["phone_number"] =  profile.get("phone",  profile.get("phone_number"))
                profile["first_name"] =  profile.get("firstname", profile.get("first_name") ) # get value of firstname with default is first_name
                profile["first_name"] =  profile.get("name", profile.get("first_name")  )  # get value of name with default is first_name
                profile["last_name"] =  profile.get("lastname", profile.get("last_name"))
                profile["date_of_birth"] =  profile.get("birthday", profile.get("date_of_birth") )            
                profile["crm_contact_id"] =  profile.get("userid", profile.get("crm_contact_id") ) # user of system is same as CRM contact info
                profile["source_system"] =  profile.get("usersource", profile.get("source_system") ) # usersource is sourcesystem
            else:
                # If `web_visitor_id` is missing, it means the data likely came from the CRM or data lake. 
                # In that case, try generating a hashed UUID using the `key_hint` value."**
                key_hint = tenant_id + observer_id + mediahost + schema_version + phone_number + email
                web_visitor_id = create_uuid_from_string(key_hint)
                
            # set web_visitor_id 
            profile["web_visitor_id"] = web_visitor_id
            
            # only save valid profiles
            valid_profiles.append(profile) 
            if len(valid_profiles) >= DB_BATCH_SIZE:
                 # --- Save batch to PostgreSQL ---
                save_to_postgresql(valid_profiles, db_connection)
                # reset batch 
                valid_profiles = []
             
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