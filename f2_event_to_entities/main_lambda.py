import base64
import json
from processor import EventProcessor

processor = EventProcessor()

def lambda_handler(event, context):
    results = []

    for record in event.get('records', []):
        record_id = record['recordId']
        try:
            raw_data = base64.b64decode(record['data']).decode('utf-8')
            event_json = json.loads(raw_data)

            processor.process_event(event_json)

            results.append({
                'recordId': record_id,
                'result': 'Ok',
                'data': base64.b64encode(json.dumps({"status": "inserted"}).encode()).decode()
            })

        except Exception as e:
            print(f"❌ Error: {e}")
            results.append({
                'recordId': record_id,
                'result': 'ProcessingFailed',
                'data': record['data']
            })

    return {'records': results}
