# put this at the top of your locustfile (or just before the request you want to trace)
import logging
from http.client import HTTPConnection

# --- HTTP Debugging ---
HTTPConnection.debuglevel = 1 # Set to 0 once resolved to reduce log verbosity
logging.basicConfig(level=logging.DEBUG) # Call once, set root logger level
requests_log = logging.getLogger("requests.packages.urllib3")
requests_log.setLevel(logging.DEBUG)
requests_log.propagate = True # Ensure these logs are handled by the root logger's handlers

from locust import HttpUser, task, between
from faker import Faker
import uuid
import json
from datetime import datetime, timedelta, timezone # Import timezone
import random
# logging is already imported and configured

CDP_TRACK_URL = 'https://ahri4fkpmd.execute-api.ap-southeast-1.amazonaws.com/dev/c360-profile-track'

fake = Faker('vi_VN')
# logging.basicConfig(level=logging.INFO) # Avoid re-calling basicConfig

# List of valid Vietnamese mobile phone_number prefixes
# These are 3-digit prefixes for 10-digit mobile numbers.
VIETNAMESE_MOBILE_PREFIXES = [
    # Viettel
    "096", "097", "098", "086", "032", "033", "034", "035", "036", "037", "038", "039",
    # MobiFone
    "090", "093", "089", "070", "079", "077", "076", "078",
    # VinaPhone
    "091", "094", "088", "083", "084", "085", "081", "082",
    # Vietnamobile
    "092", "056", "058",
    # Gmobile
    "099", "059",
    # ITelecom (uses VinaPhone infrastructure)
    "087"
]

def generate_vietnamese_phone_number():
    """Generates a valid 10-digit Vietnamese mobile phone_number number."""
    prefix = random.choice(VIETNAMESE_MOBILE_PREFIXES)
    # Mobile numbers are 10 digits long. Prefixes are 3 digits.
    # So, we need 10 - 3 = 7 more random digits.
    remaining_digits = "".join([str(random.randint(0, 9)) for _ in range(7)])
    return prefix + remaining_digits

# --- Configuration for Simulated Time Range ---
# Define your desired time range here. These should be UTC.
# Example: Simulate events for the month of April 2025
SIMULATION_START_DATETIME_STR = "2025-01-01T00:00:00Z"
SIMULATION_END_DATETIME_STR = "2025-04-30T23:59:59Z"

# Convert string dates to datetime objects once
try:
    # Strip 'Z' and add tzinfo for robust parsing if format varies slightly
    # or use fromisoformat if Python version is >= 3.7 and strings are strictly ISO compliant with Z
    SIMULATION_START_UTC = datetime.fromisoformat(SIMULATION_START_DATETIME_STR.replace('Z', '+00:00'))
    SIMULATION_END_UTC = datetime.fromisoformat(SIMULATION_END_DATETIME_STR.replace('Z', '+00:00'))

    # Ensure they are UTC
    if SIMULATION_START_UTC.tzinfo is None or SIMULATION_START_UTC.tzinfo.utcoffset(SIMULATION_START_UTC) != timedelta(0):
        SIMULATION_START_UTC = SIMULATION_START_UTC.replace(tzinfo=timezone.utc)
    if SIMULATION_END_UTC.tzinfo is None or SIMULATION_END_UTC.tzinfo.utcoffset(SIMULATION_END_UTC) != timedelta(0):
        SIMULATION_END_UTC = SIMULATION_END_UTC.replace(tzinfo=timezone.utc)

    if SIMULATION_START_UTC >= SIMULATION_END_UTC:
        raise ValueError("Simulation start datetime must be before end datetime.")

except ValueError as e:
    logging.error(f"Error parsing simulation datetime strings: {e}. Please check format (YYYY-MM-DDTHH:MM:SSZ).")
    # Fallback to current time if parsing fails, or handle as critical error
    SIMULATION_START_UTC = datetime.now(timezone.utc) - timedelta(days=30)
    SIMULATION_END_UTC = datetime.now(timezone.utc)
    logging.warning(f"Falling back to default range: {SIMULATION_START_UTC.isoformat()} to {SIMULATION_END_UTC.isoformat()}")

class C360User(HttpUser):
    wait_time = between(1, 3)
    # It's good practice to set the host at the class level if all tasks hit the same host
    # host = "https://ahri4fkpmd.execute-api.ap-southeast-1.amazonaws.com"
    
    def get_random_datetime_in_range(self, start_utc, end_utc):
        """Generates a random datetime object within the given UTC range."""
        delta = end_utc - start_utc
        if delta.total_seconds() <= 0: # Should be caught by initial check, but good to have
            return start_utc # Or handle error appropriately

        random_seconds = random.uniform(0, delta.total_seconds())
        random_datetime_utc = start_utc + timedelta(seconds=random_seconds)
        return random_datetime_utc

    @task
    def send_profile_track_event(self):
        # Generate a random datetime within the specified simulation range
        simulated_datetime_utc = self.get_random_datetime_in_range(SIMULATION_START_UTC, SIMULATION_END_UTC)

        # 2. Format it to the desired string "YYYY-MM-DDTHH:MM:SSZ"
        formatted_datetime_utc = simulated_datetime_utc.strftime('%Y-%m-%dT%H:%M:%SZ')

        # unix_timestamp
        unix_ts = int(simulated_datetime_utc.timestamp() * 1000)

        # Generate fake data
        first_name = fake.first_name()
        last_name = fake.last_name()
        email = fake.email()
        
        # generate a valid Vietnamese phone_number number
        phone_number = generate_vietnamese_phone_number()
        
        # date_of_birth from 18 to 60
        dob = fake.date_of_birth(minimum_age=18, maximum_age=60).strftime("%Y-%m-%d") 

        # UTM sources
        utm_sources = ["facebook", "google", "tiktok", "zalo", "email", "organic"]
        utm_mediums = ["cpc", "banner", "video", "social", "email"]
        utm_campaigns = ["summer_sale", "new_arrival", "flash_deal", "womens_day"]
        utm_terms = ["jewelry+sale", "bracelet+offer", "ring+discount", "gold+promo"]
        utm_contents = ["image_ad_01", "carousel_ad_02", "video_ad_03", "newsletter_04"]

        # Payload of event
        EVENT_NAME = "identify"
        payload = {
            "schema_version": "2025.04.28", # CRITICAL: VERIFY THIS VALUE with API documentation
            "event_id": str(uuid.uuid4()),
            "tenant_id": "PNJ",
            "datetime": formatted_datetime_utc,
            "unix_timestamp": unix_ts, 
            "metric": EVENT_NAME, # VERIFY: Allowed values?
            "visid": str(uuid.uuid4()),
            "mediahost": "www.pnj.com.vn",
            "tpurl": "https://www.pnj.com.vn/",
            "profile_traits": {
                "phone_number": phone_number,
                "last_name": last_name,
                "first_name": first_name,
                "gender": fake.random_element(elements=("male", "female")),
                "dob": dob,
                "loyalty_level": fake.random_element(elements=("bronze", "silver", "gold", "platinum")),
                "email": email,
                "metadata": {
                    # VERIFY: Expected format/values for referrer? (e.g., full URL, specific keywords)
                    "referrer": random.choice(utm_sources) + "_ad"
                }
            },
            "utmdata": {
                "utmsource": random.choice(utm_sources), 
                "utmmedium": random.choice(utm_mediums),
                "utmcampaign": random.choice(utm_campaigns), 
                "utmterm": random.choice(utm_terms), 
                "utmcontent": random.choice(utm_contents) 
            }
        }
        
        # This log is very helpful.
        logging.debug("🔄 Payload to be sent:\n" + json.dumps(payload, indent=2, ensure_ascii=False))

        # Set headers
        headers = {
            "Content-Type": "application/json",
            "Accept": "application/json",
            "user-agent": self.client.headers.get("User-Agent", "LocustIO") # Use Locust's default or your custom one
        }

        # If host is set on the class, url should be relative: '/dev/c360-profile-track'
        with self.client.post(
            url=CDP_TRACK_URL,
            json=payload, # Locust handles the json.dumps internally
            headers=headers,
            catch_response=True
        ) as response:
            if response.status_code == 200 or response.status_code == 201: # Consider other success codes like 201 (Created)
                logging.info(f"✅ Success: {response.status_code} - Response text: {response.text[:500]}") # Log part of response text
                response.success()
            else:
                # Log the request body again on failure for easy correlation with the error message
                logging.error(f"❌ Failed: {response.status_code} - Response text: {response.text}")
                logging.error(f"Sent Payload that failed:\n{json.dumps(payload, indent=2, ensure_ascii=False)}")
                response.failure(f"API Error: {response.status_code} - {response.text}")