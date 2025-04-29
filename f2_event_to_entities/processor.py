import base64
import json
import boto3
from botocore.exceptions import ClientError
import phonenumbers
import psycopg2


# --- Helper Functions ---

def validate_phone_number(phone_number_str):
    """Check if the phone number string is valid using phonenumbers library."""
    if not phone_number_str:
        return False
    try:
        # Attempt to parse with potential default region if known, otherwise try without
        # For simplicity, just trying parse without region first.
        # If you know the common country code, you can add it here:
        # parsed_number = phonenumbers.parse(phone_number_str, "VN") # Example for Vietnam
        parsed_number = phonenumbers.parse(phone_number_str)
        return phonenumbers.is_valid_number(parsed_number)
    except phonenumbers.phonenumberutil.NumberParseException:
        return False
    except Exception as e:
        # Catch any other unexpected errors during parsing
        print(f"[WARN] Error parsing phone number '{phone_number_str}': {e}")
        return False


def get_db_credentials(secret_name, region_name):
    """Retrieve database credentials from AWS Secrets Manager."""
    if not secret_name or not region_name:
        raise ValueError("Secret name and region name must be provided.")

    session = boto3.session.Session()
    client = session.client(service_name='secretsmanager', region_name=region_name)
    try:
        get_secret_value_response = client.get_secret_value(SecretId=secret_name)
        # Decrypts secret using the associated KMS key.
        # Depending on whether the secret is a string or binary
        if 'SecretString' in get_secret_value_response:
            secret = get_secret_value_response['SecretString']
        else:
            # Binary secrets need to be base64 decoded
            secret = base64.b64decode(get_secret_value_response['SecretBinary'])

        return json.loads(secret)
    except ClientError as e:
        # More specific error handling for ClientError
        if e.response['Error']['Code'] == 'DecryptionFailureException':
            # Secrets Manager can't decrypt the protected secret text using the provided KMS key.
            raise Exception("Secrets Manager Decryption Failure: " + str(e))
        elif e.response['Error']['Code'] == 'InternalServiceErrorException':
            # An error occurred on the server side.
            raise Exception("Secrets Manager Internal Service Error: " + str(e))
        elif e.response['Error']['Code'] == 'InvalidParameterException':
            # You provided an invalid value for a parameter.
            raise Exception("Secrets Manager Invalid Parameter: " + str(e))
        elif e.response['Error']['Code'] == 'InvalidRequestException':
            # You provided a parameter value that is not valid for the current state of the resource.
            raise Exception("Secrets Manager Invalid Request: " + str(e))
        elif e.response['Error']['Code'] == 'ResourceNotFoundException':
            # We can't find the resource that you asked for.
            raise Exception(f"Secrets Manager Secret not found: {secret_name}")
        else:
            # Catch any other ClientError
            raise Exception("Secrets Manager Client Error: " + str(e))
    except Exception as e:
        # Catch any other exceptions
        raise Exception(f"An unexpected error occurred retrieving secret: {str(e)}")


def save_to_postgresql(profile, connection):
    """Saves a single profile record to the PostgreSQL database."""
    try:
        with connection.cursor() as cursor:
            insert_query = """
                INSERT INTO public.cdp_raw_profiles_stage (
                    first_name, last_name, email, phone_number, zalo_user_id,
                    crm_id, address_line1, city, state, zip_code, source_system
                ) VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s)
            """
            cursor.execute(insert_query, (
                profile.get("firstname"),
                profile.get("lastname"),
                profile.get("email"),
                profile.get("phone"),
                profile.get("zalo_user_id"),
                profile.get("customer_id"),
                profile.get("address_line1"),
                profile.get("city"),
                profile.get("state"),
                profile.get("zip_code"),
                profile.get("source_system")
            ))
            # Note: We commit per record here. For large batches,
            # a single commit after the loop might be more efficient,
            # but error handling becomes more complex (rollback on failure).
            # Committing per record ensures successfully processed records persist
            # even if later records in the batch fail.
            connection.commit()
    except psycopg2.Error as db_error:
        # Rollback the transaction on error for this record
        connection.rollback()
        raise db_error # Re-raise the exception so the main loop can catch it
    except Exception as e:
         raise e # Re-raise any other exception