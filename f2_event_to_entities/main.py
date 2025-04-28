import json
import phonenumbers
import psycopg
import os
from dotenv import load_dotenv

# Load environment variables from a .env file (useful in development)
load_dotenv()

# Environment variables for Aurora PostgreSQL connection
DB_HOST = os.getenv('DB_HOST')
DB_PORT = os.getenv('DB_PORT')
DB_NAME = os.getenv('DB_NAME')
DB_USER = os.getenv('DB_USER')
DB_PASSWORD = os.getenv('DB_PASSWORD')

def validate_phone_number(phone_number):
    """Check if the phone number is valid using phonenumbers library."""
    try:
        parsed_number = phonenumbers.parse(phone_number)
        return phonenumbers.is_valid_number(parsed_number)
    except phonenumbers.phonenumberutil.NumberParseException:
        return False

def save_to_aurora(phone_number):
    """Saves the phone number into Aurora PostgreSQL."""
    try:
        # Async DB connection (can be replaced with sync if needed)
        with psycopg.connect(
            f"dbname={DB_NAME} user={DB_USER} password={DB_PASSWORD} host={DB_HOST} port={DB_PORT}"
        ) as conn:
            with conn.cursor() as cursor:
                # Assuming there's a table `phone_numbers` with a column `phone_number`
                insert_query = "INSERT INTO phone_numbers (phone_number) VALUES (%s)"
                cursor.execute(insert_query, (phone_number,))
                conn.commit()

    except Exception as e:
        print(f"Error saving to Aurora: {e}")
        raise

def lambda_handler(event, context):
    """Main Lambda handler to process Firehose event."""
    print('Loading function')
    
    # Process the list of records and transform them
    print(json.dumps(event))  # Log the entire event for debugging
    output = []

    for record in event['records']:
        # Decode the record data (assuming it's base64 encoded in the event)
        data = json.loads(record['data'])  # Assuming data is JSON encoded in the Firehose stream
        phone_number = data.get('phone_number', None)

        # Validate the phone number and save it to Aurora if valid
        if phone_number and validate_phone_number(phone_number):
            print(f"Valid phone number: {phone_number}")
            save_to_aurora(phone_number)
            result = 'Ok'
        else:
            print(f"Invalid phone number: {phone_number}")
            result = 'Failed'

        output.append({
            'recordId': record['recordId'],
            'result': result,
            'data': record['data']
        })
    
    # Log the number of successful records
    print(f"Processing completed. Successful records: {len(output)}.")
    
    # Return the output in the expected format
    return {'records': output}
