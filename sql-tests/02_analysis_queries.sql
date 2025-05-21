-- Summary Reports:
-- Truy vấn này cung cấp cái nhìn tổng quát về hệ thống phân giải định danh trong CDP, bao gồm các chỉ số chính:
-- Các chỉ số này giúp đánh giá hiệu quả của quá trình phân giải định danh và mức độ bao phủ dữ liệu trong toàn hệ thống.
SELECT
	-- 1. unique_master_profiles: Tổng số hồ sơ chính (master profile) hiện có trong hệ thống.
  (SELECT COUNT(*) FROM cdp_master_profiles) AS unique_master_profiles,

  -- 2. unique_master_links: Số lượng hồ sơ chính đã được liên kết với ít nhất một hồ sơ thô (raw profile).
  (SELECT COUNT(DISTINCT master_profile_id) FROM cdp_profile_links) AS unique_master_links,

  -- 3. total_raw_profiles: Tổng số hồ sơ thô đã được ghi nhận vào bảng tạm (staging) – đang chờ hoặc đang được xử lý phân giải định danh.
  (SELECT COUNT(*) FROM cdp_raw_profiles_stage) AS total_raw_profiles,

  -- 4. unique_raw_links: Số lượng hồ sơ thô đã được liên kết thành công với một hồ sơ chính.
  (SELECT COUNT(DISTINCT raw_profile_id) FROM cdp_profile_links) AS unique_raw_links,

  -- 5. Số lượng Hồ sơ Thô chưa được xử lý (Unprocessed Raw Profiles):
  (SELECT COUNT(*) AS unprocessed_raw_profiles FROM cdp_raw_profiles_stage r 
  			LEFT JOIN cdp_profile_links l ON r.raw_profile_id = l.raw_profile_id WHERE l.raw_profile_id IS NULL);


-- Hoặc, đếm các master có nhiều hơn một liên kết:
SELECT COUNT(*) as duplicate_masters
FROM (
    SELECT master_profile_id
    FROM cdp_profile_links
    GROUP BY master_profile_id
    HAVING COUNT(*) > 1
) AS duplicate_masters;

-- Tổng số Hồ sơ Thô (Total Raw Profiles):
SELECT COUNT(*) FROM cdp_raw_profiles_stage;

-- Số lượng Hồ sơ Master Duy nhất (Number of Unique Identities):
SELECT COUNT(*) FROM cdp_master_profiles;

-- Hoặc (nên cho kết quả tương tự nếu logic liên kết đúng)
SELECT COUNT(DISTINCT master_profile_id) FROM cdp_profile_links;

-- Số lượng Hồ sơ Thô đã được giải quyết (Processed Raw Profiles):
SELECT COUNT(*) FROM cdp_raw_profiles_stage;

-- Số lượng Hồ sơ Thô được liên kết với một Master (Linked Raw Profiles):
SELECT COUNT(*) FROM cdp_profile_links;

-- Số lượng Hồ sơ Thô được coi là trùng lặp (Raw Profiles considered Duplicates):
-- Đây là những hồ sơ thô được liên kết đến một master_profile_id mà master đó không được tạo ra từ chính hồ sơ thô đó
SELECT COUNT(*)
FROM cdp_profile_links pl
JOIN cdp_master_profiles mp ON pl.master_profile_id = mp.master_profile_id
WHERE pl.raw_profile_id != mp.first_seen_raw_profile_id; -- Giả định first_seen_raw_profile_id lưu ID thô đầu tiên tạo master



-- Số lượng Hồ sơ Thô chưa được xử lý (Unprocessed Raw Profiles):
SELECT COUNT(*) FROM cdp_raw_profiles_stage WHERE status_code = 3;

-- total_web_visitor
SELECT COUNT(DISTINCT unnested_web_visitor_id) as total_web_visitor
FROM cdp_master_profiles
CROSS JOIN UNNEST(web_visitor_ids) AS unnested_web_visitor_id
WHERE web_visitor_ids IS NOT NULL;

-- total_raw_profile
SELECT COUNT(raw_profile_id) as total_raw_profile
FROM cdp_raw_profiles_stage

-- count active master profiles
SELECT COUNT(*) 
FROM cdp_master_profiles
WHERE status_code = 1


-- kiểm tra số master profile đã có link
EXPLAIN (ANALYZE, BUFFERS)
SELECT
    COUNT(DISTINCT m.master_profile_id)
FROM
    public.cdp_master_profiles AS m
INNER JOIN
    public.cdp_profile_links AS l 
    ON m.master_profile_id = l.master_profile_id
INNER JOIN
    public.cdp_raw_profiles_stage AS r 
    ON r.raw_profile_id = l.raw_profile_id
   AND r.tenant_id = m.tenant_id;

CALL process_new_raw_profiles(
    from_datetime := NOW() - INTERVAL '180 seconds',
    to_datetime := NOW()
);

-- in 5 minutes, total processed records = 337317 - 221382. 1 minute =  23,187 records