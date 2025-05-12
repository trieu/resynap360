import base64
import json
import boto3
from botocore.exceptions import ClientError
import phonenumbers
import psycopg2
from psycopg2.extras import execute_values, Json
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
        value = re.sub(r"<script.*?>.*?</script>", "", value,
                       flags=re.IGNORECASE | re.DOTALL)
        return html.escape(value)
    return value


def is_valid_basic_phone(phone: str) -> bool:
    """
    Check if phone number is non-empty, contains digits, and not just whitespace.

    Args:
        phone (str): Input phone number as string.

    Returns:
        bool: True if looks like a phone number, False if invalid format.
    """
    if not phone:
        return False
    phone = phone.strip()
    return phone.isdigit() or (phone.startswith("+") and phone[1:].isdigit())


def validate_phone_number(phone_number_str):
    """
    Check phone number using phonenumbers.parse(phone_number_str, "VN").

    Args:
        phone (str): Input phone number as string.

    Returns:
        bool: True if looks like a phone number, False if invalid format.
    """
    if not phone_number_str:
        return False
    try:
        # Use 'VN' as default region so local numbers are parsed correctly
        parsed_number = phonenumbers.parse(phone_number_str, "VN")
        is_valid = phonenumbers.is_possible_number(parsed_number)
        if not is_valid:
            print(f"[DEBUG] Invalid phone_number format: {phone_number_str}")
        return is_valid
    except phonenumbers.phonenumberutil.NumberParseException as e:
        print(f"[DEBUG] NumberParseException for '{phone_number_str}': {e}")
        return False
    except Exception as e:
        print(
            f"[WARN] Error parsing phone_number '{phone_number_str}': {e}")
        return False


def get_db_credentials(secret_name, region_name):
    """Retrieve database credentials from AWS Secrets Manager."""
    if not secret_name or not region_name:
        raise ValueError("Secret name and region name must be provided.")

    session = boto3.session.Session()
    client = session.client(
        service_name='secretsmanager', region_name=region_name)
    try:
        get_secret_value_response = client.get_secret_value(
            SecretId=secret_name)
        # Decrypts secret using the associated KMS key.
        # Depending on whether the secret is a string or binary
        if 'SecretString' in get_secret_value_response:
            secret = get_secret_value_response['SecretString']
        else:
            # Binary secrets need to be base64 decoded
            secret = base64.b64decode(
                get_secret_value_response['SecretBinary'])

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
        raise Exception(
            f"An unexpected error occurred retrieving secret: {str(e)}")


# Note: We commit per record here. For large batches,
# a single commit after the loop might be more efficient,
# but error handling becomes more complex (rollback on failure).
# Committing per record ensures successfully processed records persist
# even if later records in the batch fail.

sql_upsert_profile = """
    INSERT INTO public.cdp_raw_profiles_stage (
        tenant_id, source_system, received_at, status_code,
        email, phone_number, web_visitor_id, crm_contact_id, crm_source_id, social_user_id,
        first_name, last_name, gender, date_of_birth,
        address_line1, address_line2, city, state, zip_code, country,
        latitude, longitude,
        preferred_language, preferred_currency, preferred_communication,
        last_seen_at, last_seen_observer_id, last_seen_touchpoint_id,
        last_seen_touchpoint_url, last_known_channel,
        ext_attributes
    )
    VALUES (
        %s, %s, NOW(), 1,
        %s, %s, %s, %s, %s, %s,
        %s, %s, %s, %s,
        %s, %s, %s, %s, %s, %s,
        %s, %s,
        %s, %s, %s,
        %s, %s, %s,
        %s, %s,
        %s
    )
    ON CONFLICT (tenant_id, web_visitor_id) DO UPDATE SET
        source_system = EXCLUDED.source_system,
        received_at = NOW(),
        status_code = 1,
        email = EXCLUDED.email,
        phone_number = EXCLUDED.phone_number,
        crm_contact_id = EXCLUDED.crm_contact_id,
        crm_source_id = EXCLUDED.crm_source_id,
        social_user_id = EXCLUDED.social_user_id,
        first_name = EXCLUDED.first_name,
        last_name = EXCLUDED.last_name,
        gender = EXCLUDED.gender,
        date_of_birth = EXCLUDED.date_of_birth,
        address_line1 = EXCLUDED.address_line1,
        address_line2 = EXCLUDED.address_line2,
        city = EXCLUDED.city,
        state = EXCLUDED.state,
        zip_code = EXCLUDED.zip_code,
        country = EXCLUDED.country,
        latitude = EXCLUDED.latitude,
        longitude = EXCLUDED.longitude,
        preferred_language = EXCLUDED.preferred_language,
        preferred_currency = EXCLUDED.preferred_currency,
        preferred_communication = EXCLUDED.preferred_communication,
        last_seen_at = EXCLUDED.last_seen_at,
        last_seen_observer_id = EXCLUDED.last_seen_observer_id,
        last_seen_touchpoint_id = EXCLUDED.last_seen_touchpoint_id,
        last_seen_touchpoint_url = EXCLUDED.last_seen_touchpoint_url,
        last_known_channel = EXCLUDED.last_known_channel,
        ext_attributes = EXCLUDED.ext_attributes;
"""

def save_to_postgresql(profiles, connection):
    if not profiles:
        return

    try:
        values = []

        for profile in profiles:
            # Optional: skip invalid records
            if not profile.get("tenant_id") or not profile.get("web_visitor_id"):
                continue

            values.append((
                sanitize_input(profile.get("tenant_id")),
                sanitize_input(profile.get("source_system")),
                sanitize_input(profile.get("email")),
                sanitize_input(profile.get("phone_number")),
                sanitize_input(profile.get("web_visitor_id")),
                sanitize_input(profile.get("crm_contact_id")),
                sanitize_input(profile.get("crm_source_id")),
                sanitize_input(profile.get("social_user_id")),
                sanitize_input(profile.get("first_name")),
                sanitize_input(profile.get("last_name")),
                sanitize_input(profile.get("gender")),
                sanitize_input(profile.get("date_of_birth")),
                sanitize_input(profile.get("address_line1")),
                sanitize_input(profile.get("address_line2")),
                sanitize_input(profile.get("city")),
                sanitize_input(profile.get("state")),
                sanitize_input(profile.get("zip_code")),
                sanitize_input(profile.get("country")),
                sanitize_input(profile.get("latitude")),
                sanitize_input(profile.get("longitude")),
                sanitize_input(profile.get("preferred_language")),
                sanitize_input(profile.get("preferred_currency")),
                Json(profile.get("preferred_communication") or {}),
                sanitize_input(profile.get("last_seen_at")),
                sanitize_input(profile.get("last_seen_observer_id")),
                sanitize_input(profile.get("last_seen_touchpoint_id")),
                sanitize_input(profile.get("last_seen_touchpoint_url")),
                sanitize_input(profile.get("last_known_channel")),
                Json(profile.get("ext_attributes") or {})
            ))

        if values:
            with connection.cursor() as cursor:
                execute_values(cursor, sql_upsert_profile, values)
            connection.commit()
            print(f"✅ [SAVED] save_to_postgresql, commit values: {len(values)}")

    except psycopg2.Error as db_error:
        connection.rollback()
        raise db_error
    except Exception as e:
        raise e