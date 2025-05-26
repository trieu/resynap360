import json
import boto3
import os
from littletable import Table
from datetime import datetime, timedelta
import psycopg2


# Create the in-memory profile cache
persona_profiles_cache = Table()
persona_profiles_cache.create_index("key")


def load_recent_profiles_from_pgsql():
    """
    Load profiles updated in the last 7 days from PostgreSQL
    """
    cutoff = (datetime.utcnow() - timedelta(days=7)).isoformat()
    
    conn = psycopg2.connect(
        dbname=os.environ["PGDATABASE"],
        user=os.environ["PGUSER"],
        password=os.environ["PGPASSWORD"],
        host=os.environ["PGHOST"],
        port=os.environ.get("PGPORT", 5432),
    )
    cur = conn.cursor()
    cur.execute("""
        SELECT tenant_id, visitor_id, persona_profiles
        FROM cdp_persona_profiles
        WHERE updated_at >= %s
    """, (cutoff,))
    
    rows = cur.fetchall()
    persona_profiles_cache.clear()
    for tenant_id, visitor_id, profiles in rows:
        key = f"{tenant_id}:{visitor_id}"
        persona_profiles_cache.insert({"key": key, "persona_profiles": profiles})
    
    print(f"✅ Loaded {len(rows)} persona profiles into cache")
    cur.close()
    conn.close()


class EventQueue:
    def __init__(self):
        self.queue_type = os.environ.get("QUEUE_TYPE", "firehose").lower()

        if self.queue_type == "firehose":
            self.stream_name = os.environ.get("FIREHOSE_STREAM_NAME", "DIRECT_PUT_PNJ_WEB_EVENTS")
            self.client = boto3.client('firehose')

        elif self.queue_type == "redis":
            raise ValueError("Redis is no longer supported. Use LittleTable in-memory cache.")

        else:
            raise ValueError(f"Unsupported QUEUE_TYPE: {self.queue_type}")

    def send(self, event: dict) -> dict:
        if self.queue_type == "firehose":
            data = json.dumps(event).encode("utf-8")
            return self.client.put_record(
                DeliveryStreamName=self.stream_name,
                Record={"Data": data}
            )
        else:
            raise RuntimeError("Invalid event queue configuration")


class WebEventProcessor:
    def __init__(self, event_queue: EventQueue = None):
        self.event_queue = event_queue or EventQueue()

    def handle_event(self, event):
        print("Event received:", event)
        try:
            body = self._parse_event_body(event)

            if self._is_valid_event(body):
                tenant_id = body["tenant_id"]
                visid = body["visid"]

                # Send to event queue
                queue_response = self._send_to_event_queue(body)
                print("Queue response:", queue_response)

                # Fetch persona profiles using in-memory cache
                persona_profiles = self._get_persona_profiles(tenant_id, visid)

                return self._build_response(200, {
                    "success": True,
                    "message": "Event sent to queue",
                    "tenant_id": tenant_id,
                    "visid": visid,
                    "persona_profiles": persona_profiles
                })
            else:
                return self._build_response(400, {
                    "success": False,
                    "message": "Invalid event payload"
                })

        except Exception as e:
            print("Error:", str(e))
            return self._build_response(500, {
                "error": "Failed to send to queue",
                "details": str(e)
            })

    def _parse_event_body(self, event):
        raw_body = event.get('body')
        if isinstance(raw_body, str):
            return json.loads(raw_body)
        elif isinstance(raw_body, dict):
            return raw_body
        else:
            raise ValueError("Invalid event body format")

    def _is_valid_event(self, body):
        metric_len = len(body.get("metric", ""))
        visid_len = len(body.get("visid", ""))
        tenant_id_len = len(body.get("tenant_id", ""))
        return (
            isinstance(body, dict)
            and (0 < metric_len < 50)
            and (1 <= visid_len <= 36)
            and (1 <= tenant_id_len <= 36)
        )

    def _send_to_event_queue(self, body):
        return self.event_queue.send(body)

    def _get_persona_profiles(self, tenant_id, visitor_id):
        """
        Lookup persona_profiles from in-memory cache (LittleTable)
        """
        try:
            key = f"{tenant_id}:{visitor_id}"
            row = persona_profiles_cache.find_one(key=key)
            if row:
                return json.loads(row["persona_profiles"])
            else:
                return ["persona_web_visitor"]
        except Exception as e:
            print(f"LittleTable error while fetching persona_profiles for {key}: {str(e)}")
            return ["persona_web_visitor"]

    def _build_response(self, status_code, body):
        return {
            "statusCode": status_code,
            "headers": {
                "Content-Type": "application/json",
                "Referrer-Policy": "strict-origin-when-cross-origin",
                "Access-Control-Allow-Headers": "Content-Type,X-Amz-Date,Authorization,X-Api-Key,X-Amz-Security-Token",
                "Access-Control-Allow-Methods": "GET,POST,PUT,DELETE,OPTIONS",
                "Access-Control-Allow-Origin": "*"
            },
            "body": json.dumps(body)
        }


def lambda_handler(event, context):
    # For AWS Lambda with SnapStart: preload cache once
    if persona_profiles_cache.size() == 0:
        load_recent_profiles_from_pgsql()
    processor = WebEventProcessor()
    return processor.handle_event(event)
