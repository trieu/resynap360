import json
import boto3
import os

# firehose configs
FIREHOSE_STREAM_NAME = os.environ.get("FIREHOSE_STREAM_NAME", "DIRECT_PUT_PNJ_WEB_EVENTS") 
firehose_client = boto3.client('firehose')

def parse_event_body(event):
    """Parse and return the body from the API Gateway event."""
    raw_body = event.get('body')
    if isinstance(raw_body, str):
        return json.loads(raw_body)
    elif isinstance(raw_body, dict):
        return raw_body
    else:
        raise ValueError("Invalid event body format")


def is_valid_event(body):
    """Check if the event contains required fields for processing."""
    return (
        isinstance(body, dict)
        and body.get("metric") == "identify"
        and len(body.get("visid", "")) > 0
        and len(body.get("tenant_id", "")) > 0
    )


def send_to_firehose(body):
    """Send the event body to Firehose."""
    data = json.dumps(body).encode("utf-8")
    response = firehose_client.put_record(
        DeliveryStreamName=FIREHOSE_STREAM_NAME,
        Record={"Data": data}
    )
    return response


def build_response(status_code, body):
    """Build HTTP response with CORS headers."""
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
    print("Event received:", event)

    response_code = 200
    try:
        body = parse_event_body(event)

        if is_valid_event(body):
            tenant_id = body["tenant_id"]
            visid = body["visid"]

            firehose_response = send_to_firehose(body)
            print("Firehose response:", firehose_response)

            response_body = {
                "success": True,
                "message": "Event sent to Firehose",
                "tenant_id": tenant_id,
                "visid": visid,
                "record_id": firehose_response['RecordId']
            }
        else:
            response_code = 400
            response_body = {
                "success": False,
                "message": "Invalid event payload"
            }

        return build_response(response_code, response_body)

    except Exception as e:
        print("Error:", str(e))
        return build_response(500, {
            "error": "Failed to send to Firehose",
            "details": str(e)
        })