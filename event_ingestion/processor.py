import json
import psycopg2
import phonenumbers
import re
import os
from dotenv import load_dotenv

class EventProcessor:
    def __init__(self):
        load_dotenv()
        self.pg_conn = psycopg2.connect(
            host=os.getenv("PG_HOST"),
            port=int(os.getenv("PG_PORT")),
            user=os.getenv("PG_USER"),
            password=os.getenv("PG_PASS"),
            dbname=os.getenv("PG_DB")
        )

    def is_valid_email(self, email):
        return re.match(r"[^@]+@[^@]+\.[^@]+", email or "") is not None

    def is_valid_phone(self, phone, region="VN"):
        try:
            parsed = phonenumbers.parse(phone, region)
            return phonenumbers.is_valid_number(parsed)
        except Exception:
            return False

    def validate_event(self, event_json):
        profile = event_json.get("profile_traits", {})
        phone = profile.get("phone", "")
        email = profile.get("email", "")
        return self.is_valid_phone(phone) or self.is_valid_email(email)

    def process_event(self, event_json):
        if not self.validate_event(event_json):
            raise ValueError("Invalid phone and email")

        with self.pg_conn:
            with self.pg_conn.cursor() as cur:
                cur.execute("SELECT insert_event_if_unique(%s)", (json.dumps(event_json),))
