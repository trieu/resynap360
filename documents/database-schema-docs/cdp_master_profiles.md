# Tài liệu thiết kế bảng `cdp_master_profiles` 

**Ngày tạo:** 09 tháng 05 năm 2025

1. Mục đích sử dụng
2. Thiết kế bảng và giải thích từng trường
3. Index chi tiết
4. Trigger xử lý
5. Câu lệnh SQL tạo bảng
6. Câu lệnh SQL tạo sample data

---

### 1. Mục đích sử dụng

Bảng `cdp_master_profiles` là bảng trung tâm trong Nền tảng Dữ liệu Khách hàng (CDP), được thiết kế để lưu trữ **hồ sơ khách hàng thống nhất (unified customer profile)**, hay còn gọi là **"hồ sơ vàng" (golden record)**. Mỗi bản ghi trong bảng này đại diện cho một cá nhân duy nhất đã được xác định và hợp nhất từ nhiều nguồn dữ liệu khác nhau thông qua quá trình giải quyết định danh (Identity Resolution).

Mục đích chính của bảng này bao gồm:

* **Cung cấp cái nhìn 360 độ về khách hàng:** Tập hợp tất cả thông tin định danh, nhân khẩu học, giao dịch, hành vi, và sở thích của khách hàng vào một nơi duy nhất.
* **Nền tảng cho phân khúc khách hàng (Segmentation):** Cho phép tạo ra các phân khúc khách hàng chi tiết dựa trên bất kỳ thuộc tính nào để phục vụ các chiến dịch marketing, bán hàng, và chăm sóc khách hàng được cá nhân hóa.
* **Cá nhân hóa trải nghiệm (Personalization):** Cung cấp dữ liệu cần thiết để cá nhân hóa nội dung, sản phẩm, và các tương tác trên mọi kênh.
* **Phân tích và báo cáo (Analytics and Reporting):** Là nguồn dữ liệu chính cho các phân tích sâu về hành vi khách hàng, giá trị vòng đời khách hàng (CLV), nguy cơ rời bỏ (churn), và hiệu quả chiến dịch.
* **Hỗ trợ các ứng dụng AI/ML:** Cung cấp dữ liệu đầu vào và lưu trữ kết quả từ các mô hình học máy như tính điểm khách hàng tiềm năng (lead scoring), dự đoán churn, gợi ý sản phẩm, và tạo các vector embedding cho tìm kiếm tương đồng.
* **Đảm bảo tính nhất quán dữ liệu:** Là nguồn dữ liệu khách hàng đáng tin cậy (single source of truth) cho các hệ thống khác trong doanh nghiệp.

### 2. Thiết kế bảng và giải thích từng trường

## Tài liệu chi tiết các trường trong bảng `cdp_master_profiles`

* SQL field: sql-scripts/05_master_profiles_table.sql

Bảng `cdp_master_profiles` lưu trữ hồ sơ khách hàng chuẩn (golden record) sau khi đã thực hiện xử lý hợp nhất danh tính (identity resolution). Dưới đây là mô tả chi tiết cho từng trường:

### 1. Thông tin định danh chính (Core identity fields)

* `master_profile_id`: UUID tự sinh, định danh duy nhất của hồ sơ master.
* `tenant_id`: ID định danh của khách hàng sử dụng hệ thống CDP (đa tenant).
* `email`: Email chính, được chuẩn hóa và dùng để so khớp danh tính.
* `secondary_emails`: Mảng email phụ đã xác thực, có thể đến từ các nguồn khác nhau.
* `phone_number`: Số điện thoại chính.
* `secondary_phone_numbers`: Mảng số điện thoại phụ.
* `web_visitor_ids`: Danh sách ID của visitor khi duyệt web (cookie, fingerprint...).
* `national_ids`: CCCD/CMND/SSN... định danh công dân.
* `crm_contact_ids`: ID người dùng trên các CRM (dạng JSONB), ví dụ: `{"salesforce": "1234"}`.
* `social_user_ids`: ID người dùng trên mạng xã hội như Facebook, Zalo, Google...

### 2. Thông tin cá nhân (Personal information)

* `first_name`: Tên.
* `last_name`: Họ.
* `gender`: Giới tính ('male', 'female', 'unknown'...).
* `date_of_birth`: Ngày sinh.
* `marital_status`: Tình trạng hôn nhân ('single', 'married'...).
* `has_children`: Có con hay không.
* `income_range`: Thu nhập ('under\_10M', '10M\_to\_30M'...).
* `occupation`: Nghề nghiệp.
* `industry`: Ngành nghề hoạt động.
* `education_level`: Trình độ học vấn ('High School', 'Bachelor'...)

### 3. Địa chỉ & vị trí (Address and location)

* `address_line1`: Địa chỉ tạm trú.
* `address_line2`: Địa chỉ thường trú.
* `city`, `state`, `zip_code`, `country`: Thông tin địa lý.
* `latitude`, `longitude`: Tọa độ địa lý.

### 4. Thông tin hành vi và sở thích (Preferences & persona details)

* `lifestyle`: Lối sống ('digital nomad', 'corporate traveler'...)
* `pain_points`: Nỗi đau, vấn đề gặp phải ('khó lên lịch trình', 'rào cản ngôn ngữ'...)
* `interests`: Sở thích ('lịch sử', 'ẩm thực đường phố'...)
* `goals`: Mục tiêu cá nhân khi tương tác dịch vụ ('khám phá văn hóa', 'tiết kiệm chi phí')
* `motivations`: Động lực sử dụng dịch vụ.
* `personal_values`: Giá trị cá nhân ('bền vững', 'tính xác thực')
* `spending_behavior`: Hành vi chi tiêu ('price-sensitive', 'premium-first')
* `favorite_brands`: Thương hiệu yêu thích.

### 5. Ngôn ngữ & giao tiếp (Localization & communication)

* `preferred_language`: Ngôn ngữ ưa thích ('vi', 'en'...)
* `preferred_currency`: Đơn vị tiền tệ ưa thích.
* `preferred_communication`: Kênh liên lạc ưa thích (JSON), ví dụ: `{ "email": true, "sms": false }`
* `preferred_shopping_channels`: Kênh mua sắm yêu thích ('online', 'retail\_store'...)
* `preferred_locations`: Địa điểm yêu thích.
* `preferred_contents`: Loại nội dung ưa thích ('video', 'review')

### 6. Tổng hợp hành vi (Behavioral summary)

* `last_seen_at`: Thời gian tương tác gần nhất.
* `last_seen_observer_id`: ID hệ thống ghi nhận tương tác.
* `last_seen_touchpoint_id`: ID điểm chạm cuối.
* `last_seen_touchpoint_url`: URL tương tác cuối.
* `last_known_channel`: Kênh tương tác cuối ('web', 'app', 'store'...)

### 7. Scoring (Chấm điểm hành vi & tiềm năng)

* `total_sessions`: Tổng số phiên truy cập web hoặc app.
* `total_purchases`: Tổng số đơn hàng đã mua.
* `avg_order_value`: Giá trị đơn hàng trung bình (đơn vị: VND).
* `last_purchase_date`: Ngày mua gần nhất.
* `data_quality_score`: Điểm đánh giá chất lượng dữ liệu (0-100).
* `lead_score`: Điểm tiềm năng marketing (0-100), tính bằng ML hoặc heuristic.
* `lead_score_model_version`: Phiên bản model chấm điểm lead.
* `lead_score_last_updated`: Thời gian cập nhật lead\_score lần cuối.
* `engagement_score`: Tổng hợp mức độ tương tác từ các sự kiện như pageview, click, time\_on\_site (thang điểm 0-100).
* `recency_score`: Điểm tương tác gần đây (càng mới càng cao).
* `churn_probability`: Xác suất rời bỏ (0-1), ví dụ: `0.8765` tương ứng 87.65%.
* `customer_lifetime_value`: Tổng giá trị dự kiến mang lại (CLV).
* `loyalty_tier`: Nhóm khách hàng trung thành ('Gold', 'Silver'...)

### 8. AI/ML segmentation

* `customer_segments`: Các phân khúc khách hàng ('high\_value', 'frequent\_traveler'...)
* `persona_tags`: Nhãn nhận diện hành vi hoặc sở thích ('luxury\_traveler')
* `data_labels`: Nhãn nội bộ ('email\_opt\_out', 'test\_user'...)
* `customer_journeys`: Lưu tiến trình journey (onboarding, re-engagement...), ví dụ: `{ "onboarding": { "status": "completed" }}`
* `next_best_actions`: Đề xuất hành động tiếp theo (JSON), ví dụ: `{ "campaign": "retarget_summer", "cta": "book_now" }`

### 9. Metadata & nguồn gốc

* `created_at`, `updated_at`: Timestamps tạo và cập nhật hồ sơ.
* `first_seen_raw_profile_id`: ID raw profile đầu tiên đóng góp vào hồ sơ này.
* `source_systems`: Danh sách hệ thống đóng góp dữ liệu (web, crm, app...)

### 10. Trường mở rộng & embedding AI

* `ext_attributes`: Trường mở rộng theo domain cụ thể.
* `event_summary`: Tổng hợp hành vi dưới dạng JSON, ví dụ: `{ "page_view": 10, "purchase": 2 }`
* `identity_embedding`: Vector định danh dùng cho so khớp mờ (AI).
* `persona_embedding`: Vector mô tả hành vi, sở thích dùng cho gợi ý nội dung, sản phẩm.
                                     |

**Ghi chú về kiểu dữ liệu `VECTOR`:** Việc sử dụng kiểu `VECTOR(384)` đòi hỏi phải cài đặt và kích hoạt extension `pgvector` trong PostgreSQL. Nếu extension này không có sẵn, câu lệnh tạo bảng sẽ thất bại.

### 3. Index chi tiết

Để đảm bảo hiệu suất truy vấn tối ưu cho bảng `cdp_master_profiles`, các index sau được đề xuất. Hầu hết các index B-tree đều bao gồm `tenant_id` làm trường đầu tiên để hỗ trợ hiệu quả cho môi trường đa khách hàng.

Danh sách tất cả các tên index được đề xuất (bao gồm cả những index có điều kiện hoặc yêu cầu extension cụ thể):

**1. Index Khóa Chính (Tự động tạo):**
   * Tên index cho khóa chính `master_profile_id` thường được PostgreSQL tự động tạo với một tên như `cdp_master_profiles_pkey` (hoặc một tên tương tự nếu bạn đặt tên tường minh cho ràng buộc `PRIMARY KEY`).

**2. Indexes B-tree (Thường dùng cho tra cứu chính xác, so sánh phạm vi, sắp xếp):**
   * `idx_master_profiles_tenant_id`
   * `idx_master_profiles_tenant_email`
   * `idx_master_profiles_tenant_id_phone`
   * `idx_master_profiles_tenant_lastname_firstname`
   * `idx_master_profiles_tenant_lead_score`
   * `idx_master_profiles_tenant_clv`
   * `idx_master_profiles_tenant_updated_at`
   * `idx_master_profiles_tenant_created_at`
   * `idx_master_profiles_tenant_last_seen_at`
   * `idx_master_profiles_tenant_first_seen_raw_id`

**3. Indexes GIN (Thường dùng cho kiểu dữ liệu mảng `TEXT[]` và `JSONB` để tìm kiếm bên trong các phần tử hoặc cặp key-value):**
   * `idx_master_profiles_secondary_emails_gin`
   * `idx_master_profiles_secondary_phone_numbers_gin`
   * `idx_master_profiles_web_visitor_ids_gin`
   * `idx_master_profiles_national_ids_gin`
   * `idx_master_profiles_source_systems_gin`
   * `idx_master_profiles_crm_contact_ids_gin`
   * `idx_master_profiles_social_user_ids_gin`
   * `idx_master_profiles_customer_segments_gin`
   * `idx_master_profiles_persona_tags_gin`
   * `idx_master_profiles_data_labels_gin`
   * `idx_master_profiles_preferred_communication_gin`
   * `idx_master_profiles_customer_journeys_gin`
   * `idx_master_profiles_ext_attributes_gin`
   * `idx_master_profiles_event_summary_gin`

**4. Indexes cho Vector Embeddings (Yêu cầu extension `pgvector` - tên ví dụ sử dụng HNSW):**
   * `idx_master_profiles_identity_embedding_hnsw` *(Được đề xuất trong phần SQL đã comment)*
   * `idx_master_profiles_persona_embedding_hnsw` *(Được đề xuất trong phần SQL đã comment)*

**5. Index cho Dữ liệu Vị trí (Yêu cầu extension `earthdistance` và `cube` - tên ví dụ sử dụng GiST):**
   * `idx_master_profiles_location_gist` *(Được đề xuất trong phần SQL đã comment)*

**Tổng cộng (bao gồm cả các index có điều kiện/comment):** Có 1 index khóa chính tự động + 10 index B-tree + 14 index GIN + 2 index Vector + 1 index Vị trí = **28 index** được đề cập.


### 4. Trigger xử lý data

Trigger phổ biến nhất và hữu ích cho bảng master profile là tự động cập nhật trường `updated_at` mỗi khi có một bản ghi được sửa đổi.

**a. Function để cập nhật `updated_at`:** set_master_profile_updated_at

**b. Trigger gọi function trên bảng `cdp_master_profiles`:** trigger_set_master_profile_updated_at

**Các trigger tiềm năng khác (cân nhắc dựa trên yêu cầu cụ thể):**

* **Trigger kiểm tra tính hợp lệ phức tạp:** Nếu có các quy tắc nghiệp vụ phức tạp không thể thực hiện bằng `CHECK constraint` đơn thuần. Tuy nhiên, logic này thường được xử lý ở tầng ứng dụng hoặc trong stored procedure.
* **Trigger đồng bộ dữ liệu:** Để đẩy các thay đổi trên hồ sơ master sang các hệ thống khác (ví dụ: hệ thống campaign, data warehouse). Tuy nhiên, giải pháp sử dụng hàng đợi thông điệp (message queue) qua CDC (Change Data Capture) thường được ưu tiên hơn để tránh ảnh hưởng hiệu năng trực tiếp lên database.
* **Trigger tính toán lại các trường tổng hợp:** Nếu một số trường trong `cdp_master_profiles` được tính toán dựa trên các trường khác trong cùng bản ghi.

### 5. Câu lệnh SQL tạo bảng

Xem file: sql-scripts/05_master_profiles_table.sql


### 6. Câu lệnh SQL tạo sample data

Dưới đây là một số dữ liệu mẫu để minh họa cách chèn dữ liệu vào bảng `cdp_master_profiles`.
(Lưu ý: Đối với các trường `VECTOR`, tôi sẽ để giá trị là `NULL` hoặc một mảng số tượng trưng. Trong thực tế, chúng sẽ được tạo bởi các mô hình Machine Learning.)

```sql
INSERT INTO cdp_master_profiles (
    tenant_id,
    email, secondary_emails, phone_number, secondary_phone_numbers,
    web_visitor_ids, national_ids, crm_contact_ids, social_user_ids,
    first_name, last_name, gender, date_of_birth,
    address_line1, city, state, zip_code, country, latitude, longitude,
    preferred_language, preferred_currency, preferred_communication,
    last_seen_at, last_seen_observer_id, last_seen_touchpoint_id, last_seen_touchpoint_url, last_known_channel,
    total_sessions, total_purchases, data_quality_score, lead_score, churn_probability, customer_lifetime_value,
    customer_segments, persona_tags, data_labels, customer_journeys,
    created_at, updated_at, first_seen_raw_profile_id, source_systems,
    ext_attributes, event_summary,
    identity_embedding, persona_embedding
) VALUES
(
    'tenant-abc-123', -- tenant_id
    'lan.nguyen@example.com'::citext, ARRAY['lan.nguyen.pro@example.com', 'lan.work@example.org'], '+84901234567', ARRAY['+84907654321'],
    ARRAY['visitor_id_web_001', 'visitor_id_app_002'], ARRAY['012345678901'],
    '{ "salesforce": "SF_CONTACT_001XYZ", "hubspot": "HS_CONTACT_789PDQ" }'::jsonb,
    '{ "zalo": "zalo_user_lan_nguyen", "facebook": "fb_lan.nguyen.35" }'::jsonb,
    'Lan', 'Nguyễn Thị', 'female', '1990-05-15',
    '123 Đường Hoa Lan', 'Quận Phú Nhuận', 'Hồ Chí Minh', '700000', 'Vietnam', 10.7984, 106.6821,
    'vi', 'VND', '{ "email": true, "sms": true, "zalo": true, "push_notification": false }'::jsonb,
    '2025-05-08 10:30:00+07', 'observer_web_prod', 'tp_product_view_001', 'https://example.com/products/abc', 'web',
    150, 25, 95, 850, 0.05, 15000000.00,
    ARRAY['high_value_customer', 'tech_savvy', 'online_shopper'], ARRAY['early_adopter', 'discount_seeker'],
    ARRAY['campaign_spring_2025_engaged', 'newsletter_subscriber'],
    '{ "loyalty_program_enrollment": {"status": "completed", "enroll_date": "2023-01-10"}, "new_product_teaser": {"status": "email_sent", "stage": 2} }'::jsonb,
    '2023-01-10 09:00:00+07', '2025-05-08 10:30:00+07', gen_random_uuid(), ARRAY['Salesforce_CRM', 'Website_Events', 'HubSpot_MKT'],
    '{ "retail_preferences": {"favorite_brands": ["BrandA", "BrandB"], "preferred_store_id": "STORE_001"}, "travel_history": {"last_destination": "Singapore", "trip_type": "leisure"} }'::jsonb,
    '{ "total_page_views": 1250, "total_clicks_promo": 50, "last_order_value": 750000, "avg_session_duration_min": 15 }'::jsonb,
    NULL, -- identity_embedding - Sẽ được điền bởi ML model
    NULL  -- persona_embedding - Sẽ được điền bởi ML model
),
(
    'tenant-xyz-789', -- tenant_id
    'minh.pham@example.com'::citext, NULL, '+84988887777', NULL,
    ARRAY['visitor_id_web_003_xyz'], NULL,
    '{ "internal_crm": "ICRM_CONTACT_002ABC" }'::jsonb,
    '{ "linkedin": "linkedin_minh_pham_dev" }'::jsonb,
    'Minh', 'Phạm Văn', 'male', '1985-11-20',
    '456 Chung cư An Khang', 'Quận 2 (TP. Thủ Đức)', 'Hồ Chí Minh', '700000', 'Vietnam', 10.8021, 106.7301,
    'en', 'USD', '{ "email": true, "sms": false, "push_notification": true }'::jsonb,
    '2025-05-07 15:00:00+07', 'observer_app_prod', 'tp_app_login_005', NULL, 'mobile_app',
    75, 5, 80, 600, 0.15, 5000.00,
    ARRAY['new_customer', 'developer_community'], ARRAY['problem_solver'],
    ARRAY['beta_tester_program_q2_2025'],
    '{ "onboarding_checklist": {"status": "in_progress", "completed_steps": ["welcome_email_opened", "profile_setup_50_percent"]} }'::jsonb,
    '2024-11-01 14:00:00+07', '2025-05-07 15:00:00+07', gen_random_uuid(), ARRAY['Internal_CRM_v2', 'Mobile_App_Events'],
    '{ "technical_skills": {"languages": ["Python", "Go", "SQL"], "cloud_platforms": ["AWS", "GCP"]}, "conference_attendance": ["DevMeetup HCMC 2024"] }'::jsonb,
    '{ "app_opens": 300, "features_used": ["feature_A", "feature_C"], "support_tickets_created": 1 }'::jsonb,
    '{0.1, 0.2, 0.3, -0.1, 0.5, 0.01, 0.12, -0.42}'::REAL[], -- Ví dụ placeholder cho vector, độ dài thực tế là 384
    '{0.5, -0.1, 0.2, 0.15, 0.33, -0.05, 0.21, 0.18}'::REAL[]  -- Ví dụ placeholder cho vector, độ dài thực tế là 384
);

-- Thêm ràng buộc CHECK cho gender nếu chưa có trong CREATE TABLE
-- ALTER TABLE cdp_master_profiles ADD CONSTRAINT chk_master_gender_valid CHECK (gender IN ('male', 'female', 'unknown', 'other'));
```