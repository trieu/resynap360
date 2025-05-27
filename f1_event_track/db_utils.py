import boto3
import json
import os
import logging
import base64
from botocore.exceptions import ClientError, BotoCoreError
from botocore.config import Config

# --- Logger setup ---
logger = logging.getLogger()
if not logger.hasHandlers():
    logging.basicConfig()
logger.setLevel(logging.INFO)

# --- Constants ---
SECRET_NAME = os.environ.get("SECRET_NAME")
REGION_NAME = os.environ.get("AWS_REGION", "ap-southeast-1")

# --- AWS SDK config (optional retries & debug support) ---
boto_config = Config(
    retries={
        'max_attempts': 5,
        'mode': 'standard'
    },
    # uncomment to see AWS SDK debug logs
    # log_level='debug'
)

def get_db_credentials(secret_name=SECRET_NAME, region_name=REGION_NAME):
    """
    Retrieve database credentials from AWS Secrets Manager with structured logging and parsing.
    """
    logger.info(f"Fetching DB credentials from Secrets Manager: {secret_name}, region: {region_name}")

    if not secret_name:
        raise ValueError("Missing required environment variable: SECRET_NAME")
    if not region_name:
        raise ValueError("Missing required environment variable: AWS_REGION")

    try:
        session = boto3.session.Session()
        client = session.client("secretsmanager", region_name=region_name, config=boto_config)

        response = client.get_secret_value(SecretId=secret_name)
        
        if 'SecretString' in response:
            secret_raw = response['SecretString']
        else:
            secret_raw = base64.b64decode(response['SecretBinary']).decode('utf-8')

        secret_dict = json.loads(secret_raw)

        # Validate required fields
        required_fields = ["DB_HOST", "DB_USER", "DB_NAME", "DB_PORT"]
        for field in required_fields:
            if field not in secret_dict:
                raise ValueError(f"Missing expected field in secret: {field}")

        # Parse DB_PORT safely
        port_str = secret_dict.get("DB_PORT", "5432")
        try:
            secret_dict["DB_PORT"] = int(port_str)
        except (ValueError, TypeError):
            logger.warning(f"Invalid DB_PORT value '{port_str}', falling back to default 5432")
            secret_dict["DB_PORT"] = 5432

        logger.info(f"Retrieved credentials for DB user '{secret_dict.get('DB_USER')}' at host '{secret_dict.get('DB_HOST')}'")

        return secret_dict

    except ClientError as e:
        error_code = e.response['Error']['Code']
        logger.error(f"ClientError while fetching secret: {error_code} - {str(e)}")
        raise
    except BotoCoreError as e:
        logger.error(f"BotoCoreError: {str(e)}")
        raise
    except Exception as e:
        logger.exception("Unexpected error while retrieving DB credentials")
        raise