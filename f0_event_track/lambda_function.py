import json
import boto3

firehose = boto3.client('firehose')
FIREHOSE_STREAM_NAME = 'DIRECT_PUT_PNJ_WEB_EVENTS'

def lambda_handler(event, context):
    print("Event received:", event)
    body = json.loads(event['body'])
    
    # TODO

    data = json.dumps(body).encode('utf-8')

    response = firehose.put_record(
        DeliveryStreamName=FIREHOSE_STREAM_NAME,
        Record={'Data': data}
    )

    return {"statusCode": 200, "body": json.dumps({"message": "c360-profile-track sent to Firehose  ", "firehose_response": response})}