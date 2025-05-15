
import uuid
from f2_event_to_entities.processor import create_uuid_from_string


def run_test():
    # --- Example Usage ---

    my_string1 = "This is my unique identifier string."
    my_string2 = "Another different string."
    my_string3 = "This is my unique identifier string." # Same as string1

    # Create UUIDs using the default DNS namespace
    uuid1 = create_uuid_from_string(my_string1)
    uuid2 = create_uuid_from_string(my_string2)
    uuid3 = create_uuid_from_string(my_string3) # Should be same as uuid1

    print(f"String 1: '{my_string1}'")
    print(f"UUID from String 1: {uuid1}")
    print("-" * 20)

    print(f"String 2: '{my_string2}'")
    print(f"UUID from String 2: {uuid2}")
    print("-" * 20)

    print(f"String 3: '{my_string3}'")
    print(f"UUID from String 3: {uuid3}")
    print("-" * 20)

    print(f"Are UUIDs from string1 and string3 the same? {uuid1 == uuid3}")
    print(f"Are UUIDs from string1 and string2 the same? {uuid1 == uuid2}")

    # You can get the UUID as a string using .str
    print(f"UUID from String 1 as string using str(): {str(uuid1)}")

    # You can also get the hex representation (no hyphens)
    print(f"UUID from String 1 as hex: {uuid1.hex}")
    
    map = {"key1": "value1", "key2": "value2", "key_1": "value_1"}
    map['key_1'] = map.get('key_1', map.get('key1'))
    print(map)

    map['key_2'] = map.get('key2', map.get('key_2'))
    print(map)

    map['key_3'] = map.get('key3', map.get('key_3'))
    print(map)