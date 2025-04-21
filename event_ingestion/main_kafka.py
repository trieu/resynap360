import json
import os
from kafka import KafkaConsumer
from processor import EventProcessor
from dotenv import load_dotenv

load_dotenv()
processor = EventProcessor()

consumer = KafkaConsumer(
    os.getenv("KAFKA_TOPIC"),
    bootstrap_servers=os.getenv("KAFKA_BROKER"),
    group_id=os.getenv("KAFKA_GROUP_ID"),
    value_deserializer=lambda m: json.loads(m.decode('utf-8')),
    auto_offset_reset='earliest'
)

print("🔄 Kafka Consumer Started...")
for message in consumer:
    try:
        processor.process_event(message.value)
        print(f"✅ Processed event: {message.value.get('event_id')}")
    except Exception as e:
        print(f"❌ Failed to process event: {e}")
