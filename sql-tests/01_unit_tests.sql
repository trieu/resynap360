
-- run CIR in specific time range
CALL process_new_raw_profiles( 
	'2025-05-13 0:00:00+07',  -- from_datetime (TIMESTAMPTZ)
    '2025-05-13 23:30:00+07'   -- to_datetime (TIMESTAMPTZ)
);

CALL process_new_raw_profiles();

SELECT COUNT(*) 
FROM cdp_raw_profiles_stage r
LEFT JOIN cdp_profile_links l ON r.raw_profile_id = l.raw_profile_id
WHERE l.raw_profile_id IS NULL
  AND '2025-05-13 14:04:00+07' <= r.received_at AND r.received_at < '2025-05-13 14:05:30+07'
  AND r.status_code = 1;