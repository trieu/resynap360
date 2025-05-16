-- Cài đặt các Extension cần thiết cho Fuzzy Matching
CREATE EXTENSION IF NOT EXISTS citext; -- Cho so sánh không phân biệt chữ hoa chữ thường
CREATE EXTENSION IF NOT EXISTS fuzzystrmatch; -- Cho soundex, dmetaphone, levenshtein
CREATE EXTENSION IF NOT EXISTS pg_trgm; -- Cho similarity based on trigrams
CREATE EXTENSION IF NOT EXISTS pgcrypto; -- cho hàm digest() cho SHA256 trong table cdp_profile_links
CREATE EXTENSION IF NOT EXISTS pg_cron; -- cho cron jobs trong customer360 database
CREATE EXTENSION IF NOT EXISTS vector; -- cho Personalization / Fuzzy identity Resolution