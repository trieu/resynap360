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
from datetime import datetime, timezone
import uuid


def convert_event_to_profile(record_data:str):
    decoded_bytes = base64.b64decode(record_data)
    decoded_str = decoded_bytes.decode('utf-8')
    
    # build json event_data
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
    
    return profile



# --- Helper Functions ---


def create_uuid_from_string(input_string, namespace=uuid.NAMESPACE_DNS):
  """
  Creates a deterministic UUID (version 5) from a string using a specified namespace.

  Args:
    input_string: The string to generate the UUID from.
    namespace: A UUID object representing the namespace. Defaults to uuid.NAMESPACE_DNS.
               Use a consistent namespace for consistent results.

  Returns:
    A uuid.UUID object generated from the string and namespace.
  """
  # uuid.uuid5() takes the namespace UUID and the name (your string)
  # It returns a UUID object
  return uuid.uuid5(namespace, input_string)


def has_string_value(data):
    """
    Checks if the input data is a non-empty string after removing leading/trailing whitespace.
    Args:
        data: The variable to check.
    Returns:
        True if data is a string and contains characters other than whitespace,
        False otherwise (if it's not a string, or is an empty string, or contains only whitespace).
    """
    # Check if the data is an instance of a string
    # This prevents errors if data is None, a number, a list, etc.
    is_string = isinstance(data, str)

    # If it's a string, check if it's non-empty after stripping whitespace
    # data.strip() removes leading and trailing whitespace
    # len(...) > 0 checks if there are any characters left
    has_content = is_string and len(data.strip()) > 0

    # Return True only if both conditions are met
    return has_content


def is_valid_email(email):
  """
  Checks if a string is a valid email address using a simple regular expression.

  Args:
    email: The string to check.

  Returns:
    True if the string is a valid email address, False otherwise.
  """
  # A simple regex for basic email validation.
  # It checks for the presence of characters before and after the '@' symbol,
  # and at least one dot in the domain part.
  regex = r'^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$'
  
  # re.match() checks if the pattern matches at the beginning of the string.
  # We use it here because a valid email should match the pattern from start to end.
  if re.match(regex, email):
    return True
  else:
    return False


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


################# SQL to upsert profile #################

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
    VALUES %s -- the list of tuples
    ON CONFLICT (tenant_id, web_visitor_id) DO UPDATE SET
        source_system = EXCLUDED.source_system,
        received_at = NOW(), -- Or EXCLUDED.received_at if you want to keep the original time on conflict
        status_code = 1, -- Or EXCLUDED.status_code
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

def save_to_postgresql(profiles, db_connection):
    if not profiles:
        raise RuntimeError("❌ profiles is null or empty")
    
    if not isinstance(db_connection, psycopg2.extensions.connection):
        raise RuntimeError("❌ Failed to connect to PostgreSQL")

    try:
        deduped_profiles = {}
        for profile in profiles:
            tenant_id = profile.get("tenant_id")
            web_visitor_id = profile.get("web_visitor_id")
            if not tenant_id or not web_visitor_id:
                continue
            key = (tenant_id.strip(), web_visitor_id.strip())
            deduped_profiles[key] = profile  # Only keep the last occurrence

        values = []
        for key, profile in deduped_profiles.items():
            
            # received_at must be the value of system time UTC
            received_at = datetime.now(timezone.utc)
            status_code = 1
            email = profile.get("email")
            phone_number = profile.get("phone_number")            
            
            values.append((
                sanitize_input(profile.get("tenant_id")),
                sanitize_input(profile.get("source_system")),
                received_at,  
                status_code, 
                sanitize_input(email),
                sanitize_input(phone_number),
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
            print(f"✅ [PROFILE] is ready to save with phone_number {phone_number} email {email}")

        if values:
            with db_connection.cursor() as cursor:
                execute_values(cursor, sql_upsert_profile, values)
            db_connection.commit()
            print(f"✅ [SAVED] save_to_postgresql, commit values: {len(values)}")

    except psycopg2.Error as db_error:
        db_connection.rollback()
        raise db_error
    except Exception as e:
        raise e