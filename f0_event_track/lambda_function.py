import json
import boto3

firehose = boto3.client('firehose')
FIREHOSE_STREAM_NAME = 'DIRECT_PUT_PNJ_WEB_EVENTS'

def lambda_handler(event, context):
    print("Event received:", event)
    
    try:
        body = json.loads(event['body'])
        
        # TODO: validate or transform body if needed
        data = json.dumps(body).encode('utf-8')

        response = firehose.put_record(
            DeliveryStreamName=FIREHOSE_STREAM_NAME,
            Record={'Data': data}
        )

        return {
            "statusCode": 200,
            "headers": {
                "Access-Control-Allow-Headers": "Content-Type,X-Amz-Date,Authorization,X-Api-Key,X-Amz-Security-Token",
                "Access-Control-Allow-Methods": "GET,POST,PUT,DELETE,OPTIONS",
                "Access-Control-Allow-Origin": "*"
            },
            "body": json.dumps({
                "message": "c360-profile-track sent to Firehose",
                "firehose_response": response
            })
        }
        
    except Exception as e:
        print("Error:", str(e))
        return {
            "statusCode": 500,
            "headers": {
                "Access-Control-Allow-Headers": "Content-Type,X-Amz-Date,Authorization,X-Api-Key,X-Amz-Security-Token",
                "Access-Control-Allow-Methods": "GET,POST,PUT,DELETE,OPTIONS",
                "Access-Control-Allow-Origin": "*"
            },
            "body": json.dumps({
                "error": "Failed to send to Firehose",
                "details": str(e)
            })
        }
