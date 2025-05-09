# Tài liệu Thiết kế Bảng: `cdp_profile_links` 

**Ngày tạo:** 09 tháng 05 năm 2025


---

### 1. Mục đích sử dụng

Bảng `cdp_profile_links` được thiết kế để lưu trữ và quản lý các mối liên kết quan trọng giữa các bản ghi hồ sơ thô (từ bảng `cdp_raw_profiles_stage`) và các hồ sơ khách hàng thống nhất (master profiles, từ bảng `cdp_master_profiles`) tương ứng của chúng. Mỗi dòng trong bảng này đại diện cho một quyết định liên kết được thực hiện bởi hệ thống giải quyết định danh.

Với `link_id` được thiết kế lại thành một giá trị hash SHA256 của `raw_profile_id` và `master_profile_id`, nó không chỉ là một ID duy nhất mà còn mang tính xác định cao và an toàn hơn về mặt xung đột: cùng một cặp `(raw_profile_id, master_profile_id)` sẽ luôn tạo ra cùng một `link_id`.

Mục đích chính của bảng này bao gồm:

* **Theo dõi Nguồn gốc Dữ liệu (Data Lineage):** Ghi lại một cách rõ ràng mỗi hồ sơ thô đã đóng góp hoặc được ánh xạ tới hồ sơ master nào.
* **Đảm bảo tính duy nhất của liên kết:** Việc `link_id` là khóa chính và được tạo từ `raw_profile_id` và `master_profile_id` đảm bảo rằng một cặp `(raw_profile_id, master_profile_id)` chỉ có thể tồn tại một lần.
* **Hỗ trợ Kiểm toán và Gỡ lỗi (Auditing and Debugging):** Cho phép truy ngược từ một hồ sơ master về các bản ghi thô cấu thành nên nó.
* **Phân tích Quy tắc Khớp nối:** Trường `match_rule` lưu lại thông tin về quy tắc hoặc lý do cụ thể đã dẫn đến việc tạo ra liên kết.
* **Đảm bảo Tính Toàn vẹn và Nhất quán:** Ràng buộc `UNIQUE` trên `raw_profile_id` (`uk_profile_links_raw_id`) vẫn quan trọng để đảm bảo mỗi hồ sơ thô chỉ được liên kết với một hồ sơ master duy nhất.
* **Quản lý vòng đời liên kết:** Trường `linked_at` giúp theo dõi thời điểm các liên kết được tạo.

### 2. Thiết kế bảng và giải thích từng trường

Dưới đây là chi tiết về cấu trúc của bảng `cdp_profile_links` đã được cập nhật và giải thích ý nghĩa của từng trường:

| Tên trường (Field Name) | Kiểu dữ liệu (Data Type)   | Tính toán/Mặc định (Generated/Default) | NULL? | Khóa Ngoại (Foreign Key)                      | Giải thích                                                                                                                                                                                                                                 |
| :---------------------- | :------------------------- | :-------------------------------------- | :---- | :-------------------------------------------- | :----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `raw_profile_id`      | UUID                     |                                         | KHÔNG | `REFERENCES cdp_raw_profiles_stage(raw_profile_id)` | ID của hồ sơ thô được liên kết. Đây là khóa ngoại, tham chiếu đến cột `raw_profile_id` trong bảng `cdp_raw_profiles_stage`.                                                                                 |
| `master_profile_id`   | UUID                     |                                         | KHÔNG | `REFERENCES cdp_master_profiles(master_profile_id)` | ID của hồ sơ master mà hồ sơ thô được liên kết tới. Đây là khóa ngoại, tham chiếu đến cột `master_profile_id` trong bảng `cdp_master_profiles`.                                                                    |
| `link_id`               | VARCHAR(64)              | `GENERATED ALWAYS AS (encode(digest(raw_profile_id::text || ':' || master_profile_id::text, 'sha256'), 'hex')) STORED` | KHÔNG |                                               | Khóa chính của bảng. Đây là một chuỗi hash SHA256 dài 64 ký tự hexa, được tự động tính toán dựa trên việc nối chuỗi `raw_profile_id` và `master_profile_id` (phân tách bằng dấu ':'). `STORED` nghĩa là giá trị được lưu trữ vật lý. **Yêu cầu extension `pgcrypto`.** |
| `linked_at`           | TIMESTAMP WITH TIME ZONE | `NOW()`                                 | CÓ    |                                               | Dấu thời gian (bao gồm múi giờ) ghi nhận thời điểm chính xác khi liên kết này được tạo ra. Mặc định là thời gian hiện tại.                                                                                              |
| `match_rule`          | VARCHAR(100)             |                                         | CÓ    |                                               | Một chuỗi mô tả quy tắc hoặc lý do cụ thể đã dẫn đến việc tạo ra liên kết này. Ví dụ: 'ExactEmailMatch', 'FuzzyNamePhone', 'AdminManualMerge', 'DeterministicRule_001'.                                          |

### 3. Danh sách Index

1.  **Index Khóa Chính (Tự động tạo):**
    * **Tên (Mặc định của PostgreSQL):** `cdp_profile_links_pkey` (hoặc một tên tương tự).
    * **Trường:** `link_id` (kiểu `VARCHAR(64)`).
    * **Loại:** UNIQUE B-tree.
    * **Mục đích:** Đảm bảo tính duy nhất cho mỗi `link_id` và cho phép truy cập cực nhanh vào một bản ghi liên kết cụ thể thông qua `link_id`.

2.  **Index UNIQUE trên `raw_profile_id` (Tạo bởi Ràng buộc UNIQUE):**
    * **Tên :** `uk_profile_links_raw_id`
    * **Trường:** `raw_profile_id`
    * **Loại:** UNIQUE B-tree
    * **Mục đích:** Vẫn giữ vai trò cực kỳ quan trọng:
        * Đảm bảo rằng mỗi `raw_profile_id` chỉ có thể xuất hiện một lần trong bảng `cdp_profile_links`.
        * Tăng tốc đáng kể các truy vấn tìm kiếm hoặc kiểm tra sự tồn tại của một liên kết dựa trên `raw_profile_id`.

3.  **Index trên `master_profile_id`:**
    * **Tên :** `idx_profile_links_master_id`
    * **Trường:** `master_profile_id`
    * **Loại:** B-tree
    * **Mục đích:** Tăng tốc các truy vấn nhằm tìm kiếm tất cả các bản ghi `raw_profile_id` được liên kết với một `master_profile_id` cụ thể.

4.  **Index trên `linked_at`:**
    * **Tên :** `idx_profile_links_linked_at`
    * **Trường:** `linked_at`
    * **Loại:** B-tree
    * **Mục đích:** Tăng tốc các truy vấn lọc hoặc sắp xếp các liên kết dựa trên thời gian chúng được tạo.

---

#### Câu lệnh SQL tạo bảng `cdp_profile_links` (Đã cập nhật `link_id` dùng SHA256)

```sql
-- Bảng 3: cdp_profile_links
-- Liên kết các hồ sơ thô với hồ hồ sơ master tương ứng
-- YÊU CẦU: Extension pgcrypto phải được cài đặt và kích hoạt để sử dụng hàm digest() cho SHA256.
-- Chạy lệnh này một lần cho database nếu chưa có: CREATE EXTENSION IF NOT EXISTS pgcrypto;

CREATE TABLE cdp_profile_links (
    raw_profile_id UUID NOT NULL REFERENCES cdp_raw_profiles_stage(raw_profile_id),
    master_profile_id UUID NOT NULL REFERENCES cdp_master_profiles(master_profile_id),
    link_id VARCHAR(64) GENERATED ALWAYS AS (
        encode(digest(raw_profile_id::text || ':' || master_profile_id::text, 'sha256'), 'hex')
    ) STORED PRIMARY KEY, -- Hashed string (SHA256) làm khóa chính
    linked_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    match_rule VARCHAR(100) -- Ghi lại quy tắc nào đã dẫn đến việc liên kết (ví dụ: 'ExactEmailMatch', 'FuzzyNamePhone', 'DynamicMatch')
);
```

#### Câu lệnh SQL tạo các Index bổ sung và Ràng buộc (Như bạn đã cung cấp trước đó)

Các lệnh tạo index và ràng buộc này vẫn giữ nguyên giá trị:

```sql
-- 1. Đảm bảo có Ràng buộc UNIQUE (và do đó là Index UNIQUE) trên raw_profile_id
-- Ràng buộc này đảm bảo một raw_profile chỉ liên kết với một master_profile.
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint
        WHERE conname = 'uk_profile_links_raw_id' AND conrelid = 'cdp_profile_links'::regclass
    ) THEN
        ALTER TABLE cdp_profile_links ADD CONSTRAINT uk_profile_links_raw_id UNIQUE (raw_profile_id);
        RAISE NOTICE 'Constraint uk_profile_links_raw_id on cdp_profile_links (raw_profile_id) created.';
    ELSE
        RAISE NOTICE 'Constraint uk_profile_links_raw_id on cdp_profile_links (raw_profile_id) already exists.';
    END IF;
END$$;

-- 2. Index trên master_profile_id để tra cứu nhanh các raw_profiles liên kết với một master_profile
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_indexes
        WHERE schemaname = 'public' AND indexname = 'idx_profile_links_master_id'
           AND tablename = 'cdp_profile_links'
    ) THEN
        CREATE INDEX idx_profile_links_master_id ON cdp_profile_links (master_profile_id);
        RAISE NOTICE 'Index idx_profile_links_master_id on cdp_profile_links (master_profile_id) created.';
    ELSE
        RAISE NOTICE 'Index idx_profile_links_master_id on cdp_profile_links (master_profile_id) already exists.';
    END IF;
END$$;

-- 3. Index trên linked_at: khi thường xuyên lọc hoặc sắp xếp các liên kết dựa trên thời gian chúng được tạo.
 DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_indexes
        WHERE schemaname = 'public' AND indexname = 'idx_profile_links_linked_at'
        AND tablename = 'cdp_profile_links'
    ) THEN
    CREATE INDEX idx_profile_links_linked_at ON cdp_profile_links (linked_at);
        RAISE NOTICE 'Index idx_profile_links_linked_at on cdp_profile_links (linked_at) created.';
    ELSE
    RAISE NOTICE 'Index idx_profile_links_linked_at on cdp_profile_links (linked_at) already exists.';
    END IF;
END$$;
```

