# Tài liệu thiết kế bảng `cdp_raw_profiles_stage` 

1. Mục đích sử dụng
2. Thiết kế bảng và giải thích từng trường
3. Index chi tiết
4. Trigger xử lý
5. Câu lệnh SQL tạo bảng
6. Câu lệnh SQL tạo sample data

---

## 📘 1. Mục đích sử dụng

* Dùng cho hệ thống CIR (Customer Identity Resolution)
* Bảng `cdp_raw_profiles_stage` là **bảng staging lưu tạm thời các bản ghi hồ sơ khách hàng thô (raw profile)** được đẩy vào từ các nguồn khác nhau như:

    * **Amazon Kinesis Firehose**
    * **Apache Kafka topics**
    * **Webhook tracking**
    * **CRM, loyalty apps,...**

Dữ liệu này sau đó sẽ được xử lý qua pipeline: *validate → identity resolution → master profile enrichment → personalization*.

---

## 🧱 2. Thiết kế bảng và giải thích các trường

| Trường                        | Kiểu dữ liệu       | Giải thích                                                               |
| ----------------------------- | ------------------ | ------------------------------------------------------------------------ |
| `raw_profile_id`              | `UUID`             | ID duy nhất (tự sinh) cho mỗi bản ghi, dùng để trace                     |
| `tenant_id`                   | `VARCHAR(36)`      | Phân biệt dữ liệu giữa các tổ chức/công ty sử dụng hệ thống              |
| `source_system`               | `VARCHAR(100)`     | Ghi nhận hệ thống gốc như `web_form`, `crm_dynamics`, `mobile_app`, etc. |
| `received_at`                 | `TIMESTAMPTZ`      | Thời điểm bản ghi được nhận                                              |
| `status_code`                 | `SMALLINT`         | 1: hoạt động, 0: bị vô hiệu hóa, -1: cần xóa                             |
| `email`                       | `CITEXT`           | Dùng kiểu `citext` để tìm kiếm không phân biệt hoa/thường                |
| `phone_number`                | `VARCHAR(50)`      | Cần chuẩn hóa định dạng E.164 nếu có thể                                 |
| `web_visitor_id`              | `VARCHAR(36)`      | ID từ trình duyệt cookie/session                                         |
| `crm_contact_id`              | `VARCHAR(100)`     | ID của hồ sơ trong CRM                                                   |
| `crm_source_id`               | `VARCHAR(100)`     | ID gốc từ hệ thống nguồn                                                 |
| `social_user_id`              | `VARCHAR(50)`      | ID từ nền tảng mạng xã hội                                               |
| `first_name`, `last_name`     | `VARCHAR(255)`     | Tên người dùng (đã tách họ và tên riêng)                                 |
| `gender`                      | `VARCHAR(20)`      | `'male'`, `'female'`, `'unknown'`                                        |
| `date_of_birth`               | `DATE`             | Ngày sinh                                                                |
| `address_line1/2`             | `VARCHAR(500)`     | Địa chỉ                                                                  |
| `city/state/country/zip_code` | `VARCHAR`          | Thông tin địa lý                                                         |
| `latitude/longitude`          | `DOUBLE PRECISION` | Vị trí GPS nếu có                                                        |
| `preferred_language/currency` | `VARCHAR`          | Cá nhân hóa theo ngôn ngữ & tiền tệ                                      |
| `preferred_communication`     | `JSONB`            | Ví dụ: `{ "email": true, "sms": false, "zalo": true }`                   |
| `last_seen_at`                | `TIMESTAMPTZ`      | Lần tương tác gần nhất                                                   |
| `last_seen_observer_id`       | `VARCHAR(36)`      | Event observer ID                                                        |
| `last_seen_touchpoint_id`     | `VARCHAR(36)`      | ID của điểm chạm gần nhất                                                |
| `last_seen_touchpoint_url`    | `VARCHAR(2048)`    | URL tương tác gần nhất                                                   |
| `last_known_channel`          | `VARCHAR(50)`      | Kênh cuối cùng: `web`, `mobile`, `store`, etc.                           |
| `ext_attributes`              | `JSON`             | Trường mở rộng linh hoạt                                                 |

---

## 📚 3. Index chính

* Các index theo định danh người dùng: `email`, `phone_number`, `social_user_id`, `crm_contact_id`, `web_visitor_id`
* Luôn kèm `tenant_id` để phục vụ multi-tenancy
* Các index thời gian: `received_at`, `last_seen_at`
* Index cho `status_code` để xử lý logic luồng

---

## 🔁 4. Trigger xử lý hậu INSERT / UPDATE

```sql
CREATE TRIGGER cdp_trigger_process_new_raw_profiles
AFTER INSERT OR UPDATE ON cdp_raw_profiles_stage
FOR EACH STATEMENT
EXECUTE FUNCTION process_new_raw_profiles_trigger_func();
```

Dùng để gọi hàm xử lý dữ liệu mới đẩy vào (thường sẽ gọi identity resolution pipeline).
Nên disable khi load dữ liệu lớn:

```sql
ALTER TABLE cdp_raw_profiles_stage DISABLE TRIGGER cdp_trigger_process_new_raw_profiles;
```

---

## 🧪 5. SQL tạo bảng (rút gọn lại phần tạo index)

Xem file sql-scripts/04_raw_profiles_stage_table.sql

---

## 🧬 6. Tạo sample data

```sql
INSERT INTO cdp_raw_profiles_stage (
    tenant_id, source_system, email, phone_number, web_visitor_id,
    crm_contact_id, crm_source_id, social_user_id,
    first_name, last_name, gender, date_of_birth,
    address_line1, address_line2, city, state, zip_code, country,
    latitude, longitude,
    preferred_language, preferred_currency, preferred_communication,
    last_seen_observer_id, last_seen_touchpoint_id, last_seen_touchpoint_url,
    last_known_channel, ext_attributes
) VALUES 
(
    'tenant_001', 'web_form', 'an.nguyen@example.com', '+84987654321', 'visitor-abc-123',
    'crm-ct-0001', 'lead-crm-002', 'zalo_99887766',
    'An', 'Nguyen', 'male', '1990-01-01',
    '123 Đường Lê Lợi', '456 Đường Nguyễn Trãi', 'Hà Nội', 'HN', '10000', 'Vietnam',
    21.0285, 105.8542,
    'vi', 'VND', '{"email": true, "sms": false, "zalo": true}',
    'observer-999', 'touchpoint-888', 'https://travel.vn/campaign/tet-2025',
    'web', '{"interests": ["travel", "culture"], "loyalty_level": "gold"}'
);
```


