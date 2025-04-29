import base64
import json
import os

import psycopg2

from processor import get_db_credentials, validate_phone_number, save_to_postgresql

# --- Configuration ---
# Use environment variables configured in the Lambda function
SECRET_NAME = os.environ.get('SECRET_NAME')
AWS_REGION = os.environ.get('AWS_REGION', 'ap-southeast-1')


# --- Lambda Handler ---

def lambda_handler(event, context):
    print("🔥 Lambda triggered by Firehose")

    records = event.get("records", [])
    output = []
    db_connection = None # Initialize connection to None

    # Validate configuration
    if not SECRET_NAME:
         print("[ERROR] SECRET_NAME environment variable not set.")
         # Mark all records as failed due to configuration error
         return {"records": [{"recordId": r['recordId'], "result": "ProcessingFailed", "data": r['data']} for r in records]}


    # Get DB credentials and connect
    try:
        creds = get_db_credentials(SECRET_NAME, AWS_REGION)
        db_connection = psycopg2.connect(
            host=creds.get('host'),
            database=creds.get('dbname'),
            user=creds.get('username'),
            password=creds.get('password'),
            port=creds.get('port', 5432)
        )
        print("✅ Database connection successful.")
    except Exception as e:
        print(f"[FATAL] DB connection failed: {str(e)}")
        # Mark all records as failed due to connection error
        return {"records": [{"recordId": r['recordId'], "result": "ProcessingFailed", "data": r['data']} for r in records]}

    # Process records from Firehose
    for record in records:
        record_id = record.get("recordId", "N/A") # Get recordId safely
        print(f"✨ Processing record: {record_id}")
        try:
            # 1. Decode and Parse Data
            decoded_bytes = base64.b64decode(record['data'])
            decoded_str = decoded_bytes.decode('utf-8')
            event_data = json.loads(decoded_str)
            profile = event_data.get("profile_traits", {})

            # 2. Validate Data (Missing fields & Phone Number)
            phone_number = profile.get("phone")
            first_name = profile.get("firstname")

            if not first_name:
                 raise ValueError("Missing required field: firstname")

            if not validate_phone_number(phone_number):
                 # Decide how to handle invalid/missing phone numbers.
                 # Raising an error here marks the record as failed.
                 # Alternatively, you could log a warning and proceed without the phone number
                 # if the DB schema allows NULL or you have a default value.
                 raise ValueError(f"Invalid or missing phone number: '{phone_number}'")

            # 3. Save to Database
            # We pass the established connection to the save function
            save_to_postgresql(profile, db_connection)
            print(f"✅ Record saved for ID: {record_id}")

            # 4. Append successful result
            output.append({
                "recordId": record_id,
                "result": "Ok",
                "data": record["data"] # Return the original data for 'Ok' records
            })

        except Exception as e:
            # Catch any error during processing of a single record
            print(f"[ERROR] Failed to process record {record_id}: {str(e)}")
            # 5. Append failed result
            output.append({
                "recordId": record_id,
                "result": "ProcessingFailed",
                # It's good practice to return the original data for failed records
                # so Firehose can potentially retry or send it to a failure destination.
                "data": record["data"]
            })

    # Close the database connection after processing all records
    if db_connection:
        try:
            db_connection.close()
            print("✅ Database connection closed.")
        except Exception as e:
            print(f"[WARN] Error closing database connection: {str(e)}")


    print(f"✅ Batch processing complete. Total records processed: {len(output)}")
    return {"records": output}