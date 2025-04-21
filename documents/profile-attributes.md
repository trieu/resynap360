# Bảng này định nghĩa *meta-data* cho từng thuộc tính (attribute) của profile trong CDP.


| Tên Cột                  | Kiểu Dữ liệu (Ví dụ) | Mô tả                                                                        | Ghi chú                                                              |
| :----------------------- | :------------------ | :--------------------------------------------------------------------------- | :------------------------------------------------------------------- |
| **id**                     | INT / BIGINT        | Khóa chính, định danh duy nhất cho *định nghĩa* attribute này.                 | PK, Auto-increment                                                   |
| **attribute_internal_code** | VARCHAR(100)        | Tên nội bộ, duy nhất (Map từ **attributeName**). Dùng trong code/hệ thống.    | UNIQUE, NOT NULL                                                     |
| **name**                   | VARCHAR(255)        | Tên hiển thị cho người dùng (Map từ **label**).                                | NOT NULL                                                             |
| **status**                 | INT / VARCHAR(50)   | Trạng thái của định nghĩa attribute (vd: 'ACTIVE', 'INACTIVE', 'DELETED').   | DEFAULT 'ACTIVE'                                                     |
| **attribute_type_id**      | INT / BIGINT        | FK đến bảng **attribute_type** (Loại control UI: Text Input, Dropdown, etc.). | FK                                                                   |
| **data_type**              | VARCHAR(50)         | Kiểu dữ liệu thực tế (Map từ **type**: 'VARCHAR', 'INT', 'BOOLEAN', 'DATETIME', 'JSON', 'FLOAT'). | NOT NULL                                                             |
| **object_id**              | INT / BIGINT        | ID của loại đối tượng chính mà attribute này thuộc về (vd: 1='Customer', 2='Product'). | FK (nếu có bảng Objects)                                             |
| **is_required**            | BOOLEAN / TINYINT   | Thuộc tính này có bắt buộc phải có giá trị không.                              | DEFAULT FALSE                                                        |
| **is_identity_resolution** | BOOLEAN / TINYINT   | Có dùng thuộc tính này để tìm và hợp nhất profile không? (Map từ **identityResolution**). | **(Mới)** DEFAULT FALSE                                           |
| **is_synchronizable**      | BOOLEAN / TINYINT   | Có cho phép đồng bộ giá trị thuộc tính này với hệ thống ngoài không? (Map từ **synchronizable**). | **(Mới)** DEFAULT TRUE                                            |
| **data_quality_score**     | INT                 | Điểm đánh giá chất lượng dữ liệu mặc định/tiềm năng của attribute này. (Map từ **dataQualityScore**). | **(Mới)** NULLable                                                |
| **is_index**               | BOOLEAN / TINYINT   | Có nên tạo index cho giá trị của attribute này trong kho dữ liệu chính không? | DEFAULT FALSE                                                        |
| **is_masking**             | BOOLEAN / TINYINT   | Có cần che (masking) giá trị của attribute này khi hiển thị không? (PII)      | DEFAULT FALSE                                                        |
| **storage_type**           | VARCHAR(50)         | Cách lưu trữ giá trị (vd: 'COLUMN', 'JSON_FIELD').                         |                                                                      |
| **attribute_size**         | INT                 | Kích thước dữ liệu (vd: max length cho VARCHAR).                            | NULLable                                                             |
| **attribute_group**        | VARCHAR(100)        | Nhóm logic trên UI (vd: 'Thông tin cá nhân', 'Thông tin liên hệ').            | NULLable                                                             |
| **parent_id**              | INT / BIGINT        | ID của attribute cha (cho cấu trúc lồng, vd: 'address.street').            | NULLable, FK to **attribute.id**                                       |
| **option_value**           | JSON / TEXT         | Lưu các tùy chọn nếu là dropdown, radio button, etc.                         | NULLable                                                             |
| **process_status**         | INT / VARCHAR(50)   | Trạng thái liên quan đến quy trình xử lý dữ liệu (nếu có).                  | NULLable                                                             |
| **attribute_status**       | INT / VARCHAR(50)   | Trạng thái cụ thể khác (cần làm rõ hoặc loại bỏ nếu trùng **status**).        | NULLable                                                             |
| **last_processed_on**      | TIMESTAMP           | Thời gian xử lý dữ liệu liên quan đến attribute này lần cuối.               | NULLable                                                             |
| **created_at**             | TIMESTAMP           | Thời gian tạo định nghĩa attribute.                                         | DEFAULT CURRENT_TIMESTAMP                                            |
| **created_by**             | VARCHAR(100)        | Người/Hệ thống tạo định nghĩa.                                              |                                                                      |
| **update_at**              | TIMESTAMP           | Thời gian cập nhật định nghĩa attribute cuối cùng.                           | ON UPDATE CURRENT_TIMESTAMP                                          |
| **update_by**              | VARCHAR(100)        | Người/Hệ thống cập nhật cuối.                                               |                                                                      |

**Ví dụ về các bản ghi trong bảng **attribute**:**

*(Giả sử **object_id** = 1 tương ứng với đối tượng "Customer")*

1.  **firstName (Tên):**
    *   **id**: 1
    *   **attribute_internal_code**: "firstName"
    *   **name**: "Tên"
    *   **status**: 'ACTIVE'
    *   **data_type**: "VARCHAR"
    *   **object_id**: 1
    *   **is_required**: TRUE
    *   **is_identity_resolution**: FALSE
    *   **is_synchronizable**: TRUE
    *   **data_quality_score**: 5
    *   **attribute_size**: 100
    *   **attribute_group**: "Thông tin cá nhân"
    *   **is_masking**: FALSE
    *   ... (các trường khác)

2.  **age (Tuổi):**
    *   **id**: 2
    *   **attribute_internal_code**: "age"
    *   **name**: "Tuổi"
    *   **status**: 'ACTIVE'
    *   **data_type**: "INT"
    *   **object_id**: 1
    *   **is_required**: FALSE
    *   **is_identity_resolution**: FALSE
    *   **is_synchronizable**: FALSE
    *   **data_quality_score**: 3
    *   **attribute_group**: "Thông tin cá nhân"
    *   **is_masking**: FALSE
    *   ... (các trường khác)

3.  **primaryEmail (Email chính):**
    *   **id**: 3
    *   **attribute_internal_code**: "primaryEmail"
    *   **name**: "Email Chính"
    *   **status**: 'ACTIVE'
    *   **data_type**: "VARCHAR"
    *   **object_id**: 1
    *   **is_required**: FALSE
    *   **is_identity_resolution**: TRUE  *(Thường dùng Email để merge)*
    *   **is_synchronizable**: TRUE
    *   **data_quality_score**: 9 *(Email thường có độ tin cậy cao)*
    *   **attribute_group**: "Thông tin liên hệ"
    *   **is_masking**: TRUE *(Email là PII)*
    *   **is_index**: TRUE *(Thường xuyên tìm kiếm theo Email)*
    *   ... (các trường khác)

4.  **primaryPhone (Số điện thoại chính):**
    *   **id**: 4
    *   **attribute_internal_code**: "primaryPhone"
    *   **name**: "Số Điện Thoại Chính"
    *   **status**: 'ACTIVE'
    *   **data_type**: "VARCHAR" *(Lưu SĐT dạng chuỗi linh hoạt hơn)*
    *   **object_id**: 1
    *   **is_required**: FALSE
    *   **is_identity_resolution**: TRUE *(Thường dùng SĐT để merge)*
    *   **is_synchronizable**: TRUE
    *   **data_quality_score**: 10 *(SĐT thường có độ tin cậy rất cao)*
    *   **attribute_group**: "Thông tin liên hệ"
    *   **is_masking**: TRUE *(SĐT là PII)*
    *   **is_index**: TRUE *(Thường xuyên tìm kiếm theo SĐT)*
    *   ... (các trường khác)

5.  **birthday (Ngày sinh):**
    *   **id**: 5
    *   **attribute_internal_code**: "birthday"
    *   **name**: "Ngày Sinh"
    *   **status**: 'ACTIVE'
    *   **data_type**: "DATE" *(Hoặc DATETIME nếu cần giờ)*
    *   **object_id**: 1
    *   **is_required**: FALSE
    *   **is_identity_resolution**: FALSE *(Ngày sinh ít khi dùng một mình để merge)*
    *   **is_synchronizable**: TRUE
    *   **data_quality_score**: 7
    *   **attribute_group**: "Thông tin cá nhân"
    *   **is_masking**: FALSE
    *   ... (các trường khác)

Schema này cung cấp một cách linh hoạt để định nghĩa và quản lý tất cả các thuộc tính bạn cần trong CDP, bao gồm cả các cấu hình liên quan đến xử lý, hiển thị và chất lượng dữ liệu.