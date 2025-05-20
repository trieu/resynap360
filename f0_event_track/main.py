import json
import boto3
import os
import redis


class EventQueue:
    """
    Abstracts the event queue implementation. Supports Firehose or Redis Pub/Sub
    depending on the QUEUE_TYPE environment variable.
    """
    def __init__(self):
        self.queue_type = os.environ.get("QUEUE_TYPE", "firehose").lower()

        if self.queue_type == "firehose":
            self.stream_name = os.environ.get("FIREHOSE_STREAM_NAME", "DIRECT_PUT_PNJ_WEB_EVENTS")
            self.client = boto3.client('firehose')

        elif self.queue_type == "redis":
            redis_host = os.environ.get("REDIS_HOST", "localhost")
            redis_port = int(os.environ.get("REDIS_PORT", 6379))
            self.channel = os.environ.get("REDIS_CHANNEL", "pnj_web_events")
            self.client = redis.StrictRedis(host=redis_host, port=redis_port, decode_responses=True)

        else:
            raise ValueError(f"Unsupported QUEUE_TYPE: {self.queue_type}")

    def send(self, event: dict) -> dict:
        """
        Sends the event to the appropriate backend based on queue_type.
        """
        if self.queue_type == "firehose":
            data = json.dumps(event).encode("utf-8")
            return self.client.put_record(
                DeliveryStreamName=self.stream_name,
                Record={"Data": data}
            )

        elif self.queue_type == "redis":
            data = json.dumps(event)
            result = self.client.publish(self.channel, data)
            return {"result": result, "backend": "redis"}

        else:
            raise RuntimeError("Invalid event queue configuration")


class WebEventProcessor:
    def __init__(self, event_queue: EventQueue = None):
        """
        Initialize the processor with an optional EventQueue instance.
        """
        self.event_queue = event_queue or EventQueue()

    def handle_event(self, event):
        """
        Entry point to handle incoming Lambda events.
        Parses, validates, and routes the event.
        """
        print("Event received:", event)
        try:
            body = self._parse_event_body(event)

            if self._is_valid_event(body):
                tenant_id = body["tenant_id"]
                visid = body["visid"]

                # Send to event queue
                queue_response = self._send_to_event_queue(body)
                print("Queue response:", queue_response)

                persona_profiles = self._get_persona_profiles(visid)

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
        """
        Parses the 'body' from the API Gateway event.
        """
        raw_body = event.get('body')
        if isinstance(raw_body, str):
            return json.loads(raw_body)
        elif isinstance(raw_body, dict):
            return raw_body
        else:
            raise ValueError("Invalid event body format")

    def _is_valid_event(self, body):
        """
        Validates that the event body has required fields.
        """
        return (
            isinstance(body, dict)
            and body.get("metric") == "identify"
            and len(body.get("visid", "")) > 0
            and len(body.get("tenant_id", "")) > 0
        )

    def _send_to_event_queue(self, body):
        """
        Dispatches the event body to the configured event queue.
        """
        return self.event_queue.send(body)

    def _get_persona_profiles(self, visitor_id):
        """
        Stub for retrieving persona profiles based on visitor ID.
        """
        return ['persona_web_visitor']

    def _build_response(self, status_code, body):
        """
        Constructs a standard API Gateway HTTP response.
        """
        return {
            "statusCode": status_code,
            "headers": {
                "Access-Control-Allow-Headers": "Content-Type,X-Amz-Date,Authorization,X-Api-Key,X-Amz-Security-Token",
                "Access-Control-Allow-Methods": "GET,POST,PUT,DELETE,OPTIONS",
                "Access-Control-Allow-Origin": "*"
            },
            "body": json.dumps(body)
        }


def lambda_handler(event, context):
    """
    Lambda function entrypoint.
    """
    processor = WebEventProcessor()
    return processor.handle_event(event)
