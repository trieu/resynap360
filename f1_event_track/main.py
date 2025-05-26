import json
import boto3
import os
import redis


class EventQueue:
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
        self.event_queue = event_queue or EventQueue()

        # Initialize Redis for persona_profiles
        redis_host = os.environ.get("REDIS_HOST", "localhost")
        redis_port = int(os.environ.get("REDIS_PORT", 6379))
        self.redis_client = redis.StrictRedis(
            host=redis_host, port=redis_port, decode_responses=True
        )

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

                # Fetch persona profiles
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

    def _get_persona_profiles(self, visitor_id):
        try:
            redis_key = f"persona_profiles:{visitor_id}"
            result = self.redis_client.get(redis_key)
            if result:
                return json.loads(result)
            else:
                return ["persona_web_visitor"]
        except Exception as e:
            print(f"Redis error while fetching persona_profiles for {visitor_id}: {str(e)}")
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
    processor = WebEventProcessor()
    return processor.handle_event(event)
