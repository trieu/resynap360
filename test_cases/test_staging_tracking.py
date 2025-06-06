import requests
import json

url = "https://cdp-api.resynap.com/id-resolution/c360-profile-track"

payload = {
    "schema_version": "2025.04.28",
    "event_id": "5ed708ca-a682-4c26-969b-5c339554b5ea",
    "tenant_id": "demo",
    "datetime": "2025-05-06T04:00:00Z",
    "unix_timestamp": 1746529570870,
    "metric": "identify",
    "visid": "9b02723f-2dcb-440b-8498-532331d76e9e",
    "mediahost": "elearning.resynap.com",
    "tpurl": "https://elearning.resynap.com/",
    "profile_traits": {
        "phone_number": "860000316623",
        "first_name": "Thomas",
        "last_name": "Nguyen",
        "gender": "male",
        "date_of_birth": "1990-05-21",
        "email": "trieu@example.com",
        "source_system": "website",
        "address_line1": "Phu Lam B",
        "state": "Hochiminh City",
        "ext_attributes": {
            "loyalty_level": "gold"
        }
    }
}

headers = {
    "Content-Type": "application/json"
}

response = requests.post(url, headers=headers, data=json.dumps(payload))

print("Status Code:", response.status_code)
print("Response:", response.text)
