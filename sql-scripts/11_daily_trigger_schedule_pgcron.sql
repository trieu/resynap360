
SELECT cron.schedule(
    'daily_identity_resolution',
    '0 2 * * *', -- Mỗi ngày lúc 2:00 AM
    $$SELECT run_daily_identity_resolution();$$
);