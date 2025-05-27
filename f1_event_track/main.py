import json
import os
import sqlite3
from datetime import datetime, timedelta, timezone
import logging

# Third-party dependencies
import boto3
import psycopg2

# Custom utility for fetching DB credentials
import db_utils

# =====================================
# Global Scope - runs on cold start only
# =====================================

logger = logging.getLogger()
logger.setLevel(logging.INFO)

# Setup in-memory SQLite DB as a fast cache
try:
    sqlite_conn = sqlite3.connect(":memory:", check_same_thread=False)
    sqlite_conn.row_factory = sqlite3.Row
    sqlite_cursor = sqlite_conn.cursor()

    # Create table to cache persona_profiles
    sqlite_cursor.execute("""
        CREATE TABLE IF NOT EXISTS persona_profiles_cache (
            key TEXT PRIMARY KEY,
            persona_profiles TEXT,
            cached_at DATETIME NOT NULL
        )
    """)
    sqlite_cursor.execute("CREATE INDEX IF NOT EXISTS idx_key ON persona_profiles_cache(key)")
    sqlite_conn.commit()
    logger.info("✅ In-memory SQLite cache initialized successfully.")
except Exception as e:
    logger.error(f"❌ CRITICAL: Failed to initialize SQLite in-memory cache: {e}")
    sqlite_conn = None

# Cache expiry control
CACHE_EXPIRY_TIME = None
CACHE_TTL_SECONDS = 300  # 5 minutes

def get_datetime_now():
    return datetime.now(timezone.utc)

def refresh_profiles_cache_from_pgsql():
    """Load data from PostgreSQL and refresh the in-memory cache."""
    global CACHE_EXPIRY_TIME
    pg_conn = None

    try:
        # Load credentials via secure helper
        db_credentials = db_utils.get_db_credentials()
        pg_conn = psycopg2.connect(
            dbname=db_credentials["DB_NAME"],
            user=db_credentials["DB_USER"],
            password=db_credentials["DB_PASS"],
            host=db_credentials["DB_HOST"],
            port=int(db_credentials.get("DB_PORT", 5432)),
            connect_timeout=5
        )

        cutoff_date = (get_datetime_now() - timedelta(days=7)).isoformat()

        with pg_conn.cursor() as cur:
            cur.execute("""
                SELECT tenant_id, visitor_id, persona_profiles
                FROM cdp_persona_profiles
                WHERE updated_at >= %s
            """, (cutoff_date,))
            rows = cur.fetchall()

        # Refresh cache in SQLite
        sqlite_cursor.execute("DELETE FROM persona_profiles_cache")
        profiles_to_insert = []
        for tenant_id, visitor_id, profiles in rows:
            key = f"{tenant_id}:{visitor_id}"
            profiles_json = json.dumps(profiles) if not isinstance(profiles, str) else profiles
            profiles_to_insert.append((key, profiles_json, get_datetime_now()))

        sqlite_cursor.executemany("""
            INSERT INTO persona_profiles_cache (key, persona_profiles, cached_at)
            VALUES (?, ?, ?)
        """, profiles_to_insert)
        sqlite_conn.commit()

        CACHE_EXPIRY_TIME = get_datetime_now() + timedelta(seconds=CACHE_TTL_SECONDS)
        logger.info(f"✅ Cache refreshed. Loaded {len(rows)} profiles. Expires at {CACHE_EXPIRY_TIME.isoformat()}Z")

    except (psycopg2.Error, KeyError) as e:
        logger.error(f"❌ PostgreSQL error: {e}")
        raise
    finally:
        if pg_conn:
            pg_conn.close()

class EventQueue:
    """Wrapper to send events to a downstream queue (e.g., Firehose)."""
    def __init__(self):
        self.queue_type = os.environ.get("QUEUE_TYPE", "firehose").lower()
        if self.queue_type == "firehose":
            self.stream_name = os.environ.get("FIREHOSE_STREAM_NAME")
            if not self.stream_name:
                raise ValueError("FIREHOSE_STREAM_NAME not set.")
            self.client = boto3.client("firehose")
        else:
            raise ValueError(f"Unsupported QUEUE_TYPE: {self.queue_type}")

    def send(self, event: dict) -> dict:
        """Send an event to Firehose."""
        data = json.dumps(event).encode("utf-8")
        return self.client.put_record(
            DeliveryStreamName=self.stream_name,
            Record={"Data": data}
        )

class WebEventProcessor:
    """Main handler to process incoming web events."""
    def __init__(self, event_queue: EventQueue):
        self.event_queue = event_queue

    def _parse_event_body(self, event: dict) -> dict:
        body = event.get("body")
        if not body:
            raise ValueError("Missing event body")
        return json.loads(body) if isinstance(body, str) else body

    def _is_valid_event(self, body: dict) -> bool:
        return (
            isinstance(body, dict) and
            all(isinstance(body.get(k), str) and 1 <= len(body[k]) <= 36 for k in ["visid", "tenant_id"]) and
            isinstance(body.get("metric"), str) and len(body["metric"]) < 50
        )

    def _get_persona_profiles(self, tenant_id: str, visitor_id: str) -> list:
        default_profile = ["persona_web_visitor"]
        if not sqlite_conn:
            logger.error("SQLite unavailable.")
            return default_profile

        try:
            key = f"{tenant_id}:{visitor_id}"
            cursor = sqlite_conn.cursor()
            cursor.execute("SELECT persona_profiles FROM persona_profiles_cache WHERE key = ?", (key,))
            row = cursor.fetchone()
            return json.loads(row["persona_profiles"]) if row else default_profile
        except sqlite3.Error as e:
            logger.error(f"SQLite error for key {key}: {e}")
            return default_profile

    def _build_response(self, status_code: int, body: dict) -> dict:
        return {
            "statusCode": status_code,
            "headers": {
                "Content-Type": "application/json",
                "Access-Control-Allow-Origin": "*",
                "Access-Control-Allow-Headers": "Content-Type,X-Amz-Date,Authorization,X-Api-Key,X-Requested-With",
                "Access-Control-Allow-Methods": "GET,POST,PUT,DELETE,OPTIONS",
            },
            "body": json.dumps(body)
        }

    def handle_event(self, event: dict):
        try:
            body = self._parse_event_body(event)
            if not self._is_valid_event(body):
                logger.warning(f"Invalid payload: {body}")
                return self._build_response(400, {"message": "Invalid event payload"})

            self.event_queue.send(body)
            profiles = self._get_persona_profiles(body["tenant_id"], body["visid"])
            return self._build_response(200, {
                "success": True,
                "message": "Event received successfully.",
                "persona_profiles": profiles
            })

        except json.JSONDecodeError:
            return self._build_response(400, {"message": "Invalid JSON format."})
        except Exception as e:
            logger.error(f"Error processing event: {e}", exc_info=True)
            return self._build_response(500, {"message": "Internal Server Error"})

# ===================== Lambda Entry Point =====================
# Initialize reusable clients/handlers during cold start
event_queue_client = EventQueue()
event_processor = WebEventProcessor(event_queue_client)

def lambda_handler(event, context):
    if CACHE_EXPIRY_TIME is None or get_datetime_now() > CACHE_EXPIRY_TIME:
        logger.info("Cache is stale or uninitialized. Refreshing...")
        try:
            refresh_profiles_cache_from_pgsql()
        except Exception as e:
            logger.error(f"Cache refresh failed: {e}")

    return event_processor.handle_event(event)