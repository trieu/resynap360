# Tài liệu thiết kế bảng `cdp_master_profiles` 

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

Dưới đây là chi tiết về cấu trúc của bảng `cdp_master_profiles` và giải thích ý nghĩa của từng trường:

| Tên trường (Field Name)       | Kiểu dữ liệu (Data Type)         | Mặc định (Default)        | NULL? | Giải thích                                                                                                                                                                |
| :---------------------------- | :------------------------------- | :------------------------ | :---- | :----------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `master_profile_id`           | UUID                             | `gen_random_uuid()`       | KHÔNG | ID duy nhất toàn cục cho mỗi hồ sơ master, là khóa chính của bảng.                                                                                                       |
| `tenant_id`                   | VARCHAR(36)                      |                           | CÓ    | ID của Tenant (khách hàng doanh nghiệp sử dụng CDP), quan trọng cho môi trường đa khách hàng (multi-tenant).                                                              |
| **Trường Định danh Cốt lõi (Core Identity Fields)** |                                  |                           |       |                                                                                                                                                                          |
| `email`                       | CITEXT                           |                           | CÓ    | Địa chỉ email chính của khách hàng. `CITEXT` là kiểu text không phân biệt chữ hoa/thường, hữu ích cho việc tìm kiếm và đảm bảo tính duy nhất.                                 |
| `secondary_emails`            | TEXT[]                           |                           | CÓ    | Mảng chứa các địa chỉ email phụ đã được xác minh của khách hàng.                                                                                                            |
| `phone_number`                | VARCHAR(50)                      |                           | CÓ    | Số điện thoại chính của khách hàng (nên được chuẩn hóa).                                                                                                                   |
| `secondary_phone_numbers`     | TEXT[]                           |                           | CÓ    | Mảng chứa các số điện thoại phụ đã được xác minh (nên được chuẩn hóa).                                                                                                      |
| `web_visitor_ids`             | TEXT[]                           |                           | CÓ    | Mảng chứa các ID khách truy cập website (ví dụ: từ cookie) được liên kết với hồ sơ này.                                                                                      |
| `national_ids`                | TEXT[]                           |                           | CÓ    | Mảng chứa các số định danh quốc gia (ví dụ: CCCD/CMND ở Việt Nam - thường 9 hoặc 12 số; SSN ở Mỹ - 9 số).                                                                      |
| `crm_contact_ids`             | JSONB                            | `'{}'::jsonb`             | CÓ    | Đối tượng JSONB lưu trữ các ID liên hệ từ nhiều hệ thống CRM khác nhau. Ví dụ: `{ "salesforce_crm": "sf_id_123", "hubspot_mkt_crm": "hs_id_456" }`.                     |
| `social_user_ids`             | JSONB                            | `'{}'::jsonb`             | CÓ    | Đối tượng JSONB lưu trữ ID người dùng từ các nền tảng mạng xã hội. Ví dụ: `{ "facebook": "fb_user_xxx", "zalo": "zalo_user_yyy" }`.                                       |
| **Thông tin Cá nhân (Personal Information)** |                                  |                           |       |                                                                                                                                                                          |
| `first_name`                  | VARCHAR(255)                     |                           | CÓ    | Tên của khách hàng. Ví dụ: 'Văn Anh' hoặc 'Anh'.                                                                                                                            |
| `last_name`                   | VARCHAR(255)                     |                           | CÓ    | Họ của khách hàng. Ví dụ: 'Nguyễn'.                                                                                                                                      |
| `gender`                      | VARCHAR(20)                      |                           | CÓ    | Giới tính của khách hàng. Ví dụ: 'male', 'female', 'unknown', 'other'. Nên có CHECK constraint.                                                                        |
| `date_of_birth`               | DATE                             |                           | CÓ    | Ngày sinh của khách hàng.                                                                                                                                                    |
| **Địa chỉ và Vị trí (Address and Location)** |                                  |                           |       |                                                                                                                                                                          |
| `address_line1`               | VARCHAR(500)                     |                           | CÓ    | Địa chỉ dòng 1 (ví dụ: số nhà, tên đường, thường là địa chỉ tạm trú hoặc địa chỉ liên hệ chính).                                                                             |
| `address_line2`               | VARCHAR(500)                     |                           | CÓ    | Địa chỉ dòng 2 (ví dụ: tên tòa nhà, số căn hộ, phường/xã, thường là địa chỉ thường trú nếu khác).                                                                            |
| `city`                        | VARCHAR(255)                     |                           | CÓ    | Thành phố / Tỉnh.                                                                                                                                                            |
| `state`                       | VARCHAR(255)                     |                           | CÓ    | Bang / Khu vực hành chính cấp cao hơn (nếu có).                                                                                                                                |
| `zip_code`                    | VARCHAR(10)                      |                           | CÓ    | Mã bưu điện.                                                                                                                                                                 |
| `country`                     | VARCHAR(100)                     |                           | CÓ    | Quốc gia.                                                                                                                                                                    |
| `latitude`                    | DOUBLE PRECISION                 |                           | CÓ    | Vĩ độ, thường lấy từ API vị trí địa lý của ứng dụng di động hoặc các nguồn khác.                                                                                             |
| `longitude`                   | DOUBLE PRECISION                 |                           | CÓ    | Kinh độ, thường lấy từ API vị trí địa lý của ứng dụng di động hoặc các nguồn khác.                                                                                              |
| **Tùy chọn và Bản địa hóa (Preferences and Localization)** |                                  |                           |       |                                                                                                                                                                          |
| `preferred_language`          | VARCHAR(20)                      |                           | CÓ    | Ngôn ngữ ưa thích của khách hàng cho giao tiếp. Ví dụ: 'vi', 'en'.                                                                                                           |
| `preferred_currency`          | VARCHAR(10)                      |                           | CÓ    | Đơn vị tiền tệ ưa thích của khách hàng. Ví dụ: 'VND', 'USD'.                                                                                                                    |
| `preferred_communication`     | JSONB                            | `'{}'::jsonb`             | CÓ    | Đối tượng JSONB lưu trữ các kênh liên lạc ưa thích. Ví dụ: `{ "email": true, "sms": false, "zalo": true, "push_notification": true }`.                                      |
| **Tóm tắt Hành vi (Behavioral Summary)** |                                  |                           |       |                                                                                                                                                                          |
| `last_seen_at`                | TIMESTAMPTZ                      | `NOW()`                   | CÓ    | Thời điểm cuối cùng khách hàng có hoạt động được ghi nhận (ví dụ: truy cập web, mở app, tương tác).                                                                       |
| `last_seen_observer_id`       | VARCHAR(36)                      |                           | CÓ    | ID của hệ thống hoặc "quan sát viên sự kiện" (event observer) cuối cùng đã ghi nhận hành vi của người dùng.                                                                   |
| `last_seen_touchpoint_id`     | VARCHAR(36)                      |                           | CÓ    | ID của điểm chạm (touchpoint) cuối cùng mà khách hàng tương tác.                                                                                                               |
| `last_seen_touchpoint_url`    | VARCHAR(2048)                    |                           | CÓ    | URL của điểm chạm cuối cùng (nếu là web).                                                                                                                                      |
| `last_known_channel`          | VARCHAR(50)                      |                           | CÓ    | Kênh tương tác cuối cùng được ghi nhận. Ví dụ: 'web', 'mobile_app', 'email_campaign', 'retail_store'.                                                                     |
| **Trường Dữ liệu Tính điểm (Scoring Data Fields)** |                                  |                           |       |                                                                                                                                                                          |
| `total_sessions`              | INT                              | `1`                       | CÓ    | Tổng số phiên truy cập web và/hoặc phiên đăng nhập ứng dụng, được tính toán từ dữ liệu sự kiện.                                                                                |
| `total_purchases`             | INT                              |                           | CÓ    | Tổng số lần mua sản phẩm hoặc dịch vụ.                                                                                                                                         |
| `data_quality_score`          | INT                              |                           | CÓ    | Điểm chất lượng dữ liệu của hồ sơ này, đánh giá mức độ đầy đủ và chính xác của thông tin.                                                                                       |
| `lead_score`                  | INT                              |                           | CÓ    | Điểm khách hàng tiềm năng, thường được sử dụng trong marketing và sales để ưu tiên.                                                                                             |
| `churn_probability`           | NUMERIC                          |                           | CÓ    | Xác suất rời bỏ (churn) dự đoán, ước tính khả năng khách hàng ngừng sử dụng dịch vụ/sản phẩm trong một khoảng thời gian nhất định.                                                   |
| `customer_lifetime_value`     | NUMERIC                          |                           | CÓ    | Giá trị vòng đời khách hàng (CLV) dự đoán hoặc đã tính toán.                                                                                                                    |
| **Trường Phân khúc AI/ML (AI/ML Segmentation Fields)** |                                  |                           |       |                                                                                                                                                                          |
| `customer_segments`           | TEXT[]                           |                           | CÓ    | Mảng chứa các phân khúc khách hàng mà hồ sơ này thuộc về. Ví dụ: `['frequent_traveler', 'high_value_customer', 'tech_savvy']`.                                              |
| `persona_tags`                | TEXT[]                           |                           | CÓ    | Mảng chứa các thẻ mô tả chân dung khách hàng (persona). Ví dụ: `['history_lover', 'luxury_traveler', 'budget_conscious']`.                                                   |
| `data_labels`                 | TEXT[]                           |                           | CÓ    | Mảng chứa các nhãn dữ liệu tùy chỉnh. Ví dụ: `['internal_test_profile', 'email_opt_out', 'web_signup_campaign_q4_2024', 'gdpr_consent_given']`.                            |
| `customer_journeys`           | JSONB                            | `'{}'::jsonb`             | CÓ    | Đối tượng JSONB theo dõi trạng thái của khách hàng trong các hành trình khác nhau. Ví dụ: `{"onboarding_series": {"status": "active", "current_stage": "Email 3 Sent"}}`.   |
| **Siêu dữ liệu Hồ sơ (Metadata about Profile)** |                                  |                           |       |                                                                                                                                                                          |
| `created_at`                  | TIMESTAMP WITH TIME ZONE         | `NOW()`                   | CÓ    | Thời điểm hồ sơ master này được tạo lần đầu tiên.                                                                                                                             |
| `updated_at`                  | TIMESTAMP WITH TIME ZONE         | `NOW()`                   | CÓ    | Thời điểm hồ sơ master này được cập nhật lần cuối. Thường được quản lý bởi một trigger.                                                                                       |
| `first_seen_raw_profile_id`   | UUID                             |                           | CÓ    | ID của bản ghi hồ sơ thô (`cdp_raw_profiles_stage.raw_profile_id`) đầu tiên đã được khớp và đóng góp vào việc tạo ra hồ sơ master này.                                            |
| `source_systems`              | TEXT[]                           |                           | CÓ    | Mảng liệt kê tên các hệ thống nguồn (`cdp_raw_profiles_stage.source_system`) đã đóng góp dữ liệu vào hồ sơ master này.                                                           |
| **Thuộc tính Mở rộng (Flexible Attributes)** |                                  |                           |       |                                                                                                                                                                          |
| `ext_attributes`              | JSONB                            | `'{}'::jsonb`             | CÓ    | Đối tượng JSONB linh hoạt để lưu trữ các thuộc tính đặc thù theo từng lĩnh vực kinh doanh hoặc các thuộc tính mới phát sinh. Ví dụ: `{"retail": {"loyalty_tier": "Gold"}, "travel": {"preferred_airline": "VN"}}`. |
| **Tóm tắt Hành vi từ Tổng hợp Sự kiện (Behavioral Summary from Event Aggregation)** |                |                           |       |                                                                                                                                                                          |
| `event_summary`               | JSONB                            | `'{}'::jsonb`             | CÓ    | Đối tượng JSONB lưu trữ các tóm tắt hành vi được tổng hợp từ dữ liệu sự kiện. Ví dụ: `{"page_view_count": 150, "last_product_viewed_id": "prod_xyz", "total_login_count": 25}`. |
| **Embeddings sẵn sàng cho ML/AI (ML/AI-ready Embeddings)** |                                  |                           |       |                                                                                                                                                                          |
| `identity_embedding`          | VECTOR(384)                      |                           | CÓ    | Vector embedding đại diện cho các đặc trưng định danh (ví dụ: tên + email + SĐT) để tìm kiếm tương đồng mờ (fuzzy matching). Yêu cầu extension `pgvector`.                      |
| `persona_embedding`           | VECTOR(384)                      |                           | CÓ    | Vector embedding đại diện cho các đặc trưng chân dung/sở thích/hành vi để tìm kiếm tương đồng về ngữ nghĩa. Yêu cầu extension `pgvector`.                                        |

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