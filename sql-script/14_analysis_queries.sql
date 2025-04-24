-- Tổng số Hồ sơ Thô (Total Raw Profiles):
SELECT COUNT(*) FROM cdp_raw_profiles_stage;

-- Số lượng Hồ sơ Master Duy nhất (Number of Unique Identities):
SELECT COUNT(*) FROM cdp_master_profiles;

-- Hoặc (nên cho kết quả tương tự nếu logic liên kết đúng)
SELECT COUNT(DISTINCT master_profile_id) FROM cdp_profile_links;

-- Số lượng Hồ sơ Thô đã được giải quyết (Processed Raw Profiles):
SELECT COUNT(*) FROM cdp_raw_profiles_stage WHERE processed_at IS NOT NULL;

-- Số lượng Hồ sơ Thô được liên kết với một Master (Linked Raw Profiles):
SELECT COUNT(*) FROM cdp_profile_links;

-- Số lượng Hồ sơ Thô được coi là trùng lặp (Raw Profiles considered Duplicates):
-- Đây là những hồ sơ thô được liên kết đến một master_profile_id mà master đó không được tạo ra từ chính hồ sơ thô đó
SELECT COUNT(*)
FROM cdp_profile_links pl
JOIN cdp_master_profiles mp ON pl.master_profile_id = mp.master_profile_id
WHERE pl.raw_profile_id != mp.first_seen_raw_profile_id; -- Giả định first_seen_raw_profile_id lưu ID thô đầu tiên tạo master

-- Hoặc, đếm các master có nhiều hơn một liên kết:
SELECT COUNT(*)
FROM (
    SELECT master_profile_id
    FROM cdp_profile_links
    GROUP BY master_profile_id
    HAVING COUNT(*) > 1
) AS duplicate_masters;

-- Số lượng Hồ sơ Thô chưa được xử lý (Unprocessed Raw Profiles):
SELECT COUNT(*) FROM cdp_raw_profiles_stage WHERE processed_at IS NULL;