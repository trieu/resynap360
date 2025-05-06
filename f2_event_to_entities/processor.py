import base64
import json
import boto3
from botocore.exceptions import ClientError
import phonenumbers
import psycopg2
import html
import re
import json

# --- Helper Functions ---

# basic sanitization to avoid XSS injection
def sanitize_input(value):
    """Basic XSS prevention by escaping HTML and trimming whitespace."""
    if isinstance(value, str):
        value = value.strip()
        # Optional: remove script tags or other dangerous patterns
        value = re.sub(r"<script.*?>.*?</script>", "", value, flags=re.IGNORECASE | re.DOTALL)
        return html.escape(value)
    return value

def validate_phone_number(phone_number_str):
    """Validate Vietnamese phone numbers, even if no country code is provided."""
    if not phone_number_str:
        return False
    try:
        # Use 'VN' as default region so local numbers are parsed correctly
        parsed_number = phonenumbers.parse(phone_number_str, "VN")
        is_valid = phonenumbers.is_valid_number(parsed_number)
        if not is_valid:
            print(f"[DEBUG] Invalid phone number format: {phone_number_str}")
        return is_valid
    except phonenumbers.phonenumberutil.NumberParseException as e:
        print(f"[DEBUG] NumberParseException for '{phone_number_str}': {e}")
        return False
    except Exception as e:
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



# Note: We commit per record here. For large batches,
# a single commit after the loop might be more efficient,
# but error handling becomes more complex (rollback on failure).
# Committing per record ensures successfully processed records persist
# even if later records in the batch fail.




def save_to_postgresql(profile, connection):
    """Upserts a single sanitized profile into PostgreSQL based on (tenant_id, web_visitor_id)."""
    try:
        with connection.cursor() as cursor:
            upsert_query = """
                INSERT INTO public.cdp_raw_profiles_stage (
                    tenant_id, first_name, last_name, email, phone_number, zalo_user_id, web_visitor_id, 
                    crm_id, address_line1, city, state, zip_code, source_system, ext_attributes, received_at
                )
                VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, NOW())
                ON CONFLICT (tenant_id, web_visitor_id) DO UPDATE SET
                    first_name = EXCLUDED.first_name,
                    last_name = EXCLUDED.last_name,
                    email = EXCLUDED.email,
                    phone_number = EXCLUDED.phone_number,
                    zalo_user_id = EXCLUDED.zalo_user_id,
                    crm_id = EXCLUDED.crm_id,
                    address_line1 = EXCLUDED.address_line1,
                    city = EXCLUDED.city,
                    state = EXCLUDED.state,
                    zip_code = EXCLUDED.zip_code,
                    source_system = EXCLUDED.source_system,
                    ext_attributes = EXCLUDED.ext_attributes,
                    received_at = NOW(),
                    processed_at = NULL;
            """
            values = (
                sanitize_input(profile.get("tenant_id")),
                sanitize_input(profile.get("firstname")),
                sanitize_input(profile.get("lastname")),
                sanitize_input(profile.get("email")),
                sanitize_input(profile.get("phone")),
                sanitize_input(profile.get("zalo_user_id")),
                sanitize_input(profile.get("web_visitor_id")),
                sanitize_input(profile.get("crm_id")),
                sanitize_input(profile.get("address_line1")),
                sanitize_input(profile.get("city")),
                sanitize_input(profile.get("state")),
                sanitize_input(profile.get("zip_code")),
                sanitize_input(profile.get("source_system")),
                json.dumps(profile.get("ext_attributes") or {})  # Safely serialize JSON
            )
            cursor.execute(upsert_query, values)
            connection.commit()
    except psycopg2.Error as db_error:
        connection.rollback()
        raise db_error
    except Exception as e:
        raise e
