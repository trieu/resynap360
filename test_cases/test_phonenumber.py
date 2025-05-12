
from f2_event_to_entities.processor import is_valid_basic_phone

import random
import itertools
from typing import Generator, List, Literal

valid_vn_numbers = [
    # Viettel
    "+84961234567", "0961234567",
    "+84381234567", "0381234567",

    # Vinaphone
    "+84911234567", "0911234567",
    "+84881234567", "0881234567",

    # Mobifone
    "+84901234567", "0901234567",
    "+84781234567", "0781234567",
    "0903122290",  "0903880047",     

    # Vietnamobile
    "+84921234567", "0921234567",
    "+84561234567", "0561234567",

    # Gmobile
    "+84991234567", "0991234567",
    "+84591234567", "0591234567",
]

invalid_vn_numbers = [
    '870000372432', '860000316623',
    "0951234567",        # Invalid prefix
    "+84091234567",      # Malformed country code
    "08491234567",       # Misplaced international code
    "091234567",         # Too short
    "09123456789",       # Too long
    "09a1234567",        # Invalid characters
    "",                  # Empty string
    None                 # NoneType
]

test_numbers = valid_vn_numbers + invalid_vn_numbers



def generate_vn_phone_numbers(
    count: int = 5_000_000,
    format: Literal["local", "international", "both"] = "international",
    seed: int = None
) -> List[str] | Generator[str, None, None]:
    """
    Efficiently generate valid Vietnamese phone numbers.

    Args:
        count (int): Total numbers to generate.
        format (str): 'local', 'international', or 'both'.
        seed (int): Optional seed for reproducibility.

    Returns:
        list of str | generator: Phone numbers in desired format.
    """
    if seed is not None:
        random.seed(seed)

    # Valid Vietnamese prefixes (mobile carriers)
    vn_prefixes = [
        "096", "097", "098", "032", "033", "034", "035", "036", "037", "038", "039",  # Viettel
        "091", "094", "081", "082", "083", "084", "085", "088",                      # Vinaphone
        "090", "093", "070", "076", "077", "078", "079",                             # Mobifone
        "092", "056", "058",                                                        # Vietnamobile
        "099", "059"                                                                 # Gmobile
    ]

    seen = set()
    def generate_one():
        while True:
            prefix = random.choice(vn_prefixes)
            body = f"{random.randint(0, 9999999):07d}"
            local = f"{prefix}{body}"
            if local in seen:
                continue
            seen.add(local)
            if format == "local":
                yield local
            elif format == "international":
                yield f"+84{local[1:]}"
            elif format == "both":
                yield {"local": local, "international": f"+84{local[1:]}"}

    # Return the first `count` phone numbers as a list
    return list(itertools.islice(generate_one(), count))




def run_test():
    vn_numbers = generate_vn_phone_numbers(count=100, format='both', seed=42)
    for obj in vn_numbers:
        num = obj["international"] if isinstance(obj, dict) else obj
        result = is_valid_basic_phone(num)
        print(f"Testing {num} → Valid: {result}")
        
    for num in test_numbers:
        result = is_valid_basic_phone(num)
        print(f"Testing {num} → Valid: {result}")
        
    num = '860000316623'
    result = is_valid_basic_phone(num)
    print(f"Testing {num} → Valid: {result}")
    
