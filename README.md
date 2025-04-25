# 🔍 Real-time Entity Resolution + Agentic AI for Customer Engagement  

![Flow Diagram](diagram.png)

### 👉 Lý do chọn PostgreSQL 16 cho Identity Resolution quy mô lớn

Trong kiến trúc CDP hiện đại, việc giải quyết trùng lặp danh tính (Identity Resolution) là **trái tim của cá nhân hóa & phân tích hành vi**. 
Dưới đây là kiến trúc nhắm tới xử lý dữ liệu hành vi real-time, mở rộng linh hoạt, và dễ tùy biến với cả stack AWS lẫn Open Source.

---

## 🧠 Tổng quan luồng xử lý

### 1️⃣ **Customer Touchpoints (App, Web, IoT...)**
Khách hàng tương tác qua app, web, hoặc thiết bị IoT. Tracking JS sẽ gửi event theo dạng JSON đến:

- `API Gateway` (AWS) hoặc
- HTTP endpoint (tự host bằng FastAPI, Express,...) với NginX hay AWS ALB

### 2️⃣ **Firehose hoặc Kafka**  
Sự kiện được đẩy vào hệ thống thu thập:
- **AWS Firehose**: dễ dùng, tích hợp sẵn với S3, Redshift, OpenSearch
- **Apache Kafka**: chủ động hơn, phù hợp nếu bạn đã có hạ tầng Open Source

### 3️⃣ **Raw Data Lake (S3 hoặc HDFS)**  
Mọi event gốc đều được lưu xuống Data Lake để audit, training model hoặc query ad-hoc.

### 4️⃣ **Lambda Function (F2: Event to Entity)**  
Lambda/worker backend sẽ:
- Kéo dữ liệu từ Kafka/Firehose
- Chuẩn hóa và mapping field
- Build các **customer profile entity**
- Lưu vào **PostgreSQL**

---

## 🚀 Lý do chọn **PostgreSQL ** cho Entity Resolution Service

Khối xử lý thực thể (Entity Resolution) chính là nơi xảy ra **magic**: kết nối nhiều mảnh dữ liệu rời rạc thành một **identity duy nhất**. 
Lý do chọn **PostgreSQL 16+** là vì:

### ✅ **1. CTEs & JSON/JSONB Processing cực mạnh**
- Phân tích dữ liệu profile lưu dưới dạng JSON
- Truy vấn phân lớp, join động theo rule rất linh hoạt

### ✅ **2. Stored Procedure & PL/pgSQL nâng cấp**
- PostgreSQL 16 hỗ trợ `CALL` stored procedures giống Oracle
- Có thể build 1 engine "rule-based identity matching" chạy bên trong DB 
- Giảm load data từ database ra code

### ✅ **3. Performance cải thiện rõ rệt ở JOIN và Parallel Scan**
- Khi khối lượng dữ liệu profile > 100M rows, khả năng scale trở nên rõ ràng
- Có thể tối ưu query theo từng trường hợp matching logic (email, phone, deviceID,...)

### ✅ **4. Extension Support: pg_trgm, bloom, etc.**
- So khớp fuzzy matching rất dễ implement
- Có thể dùng `SIMILARITY()` hoặc `LEVENSHTEIN()` để tìm match gần đúng

### ✅ **5. Không lock-in vendor, dễ migrate**
- Dù deploy trên RDS, Aurora hay PostgreSQL open-source đều được
- Linh hoạt giữa AWS và on-premises/Open Source infra

---

## ❌ Tại sao không dùng MongoDB / DynamoDB / Elasticsearch cho Identity Resolution?

Các hệ NoSQL hoặc Search Engine như MongoDB, DynamoDB, Elasticsearch (OpenSearch) có nhiều ưu điểm về tốc độ đọc ghi đơn giản — nhưng lại **rất hạn chế khi xử lý logic phân giải danh tính phức tạp**, đặc biệt:

### ⚠️ Hạn chế:

- **Không hỗ trợ join động hoặc CTE** → khó xử lý match theo nhiều điều kiện phức tạp (multi-field logic)
- **Khó viết logic phân lớp hoặc phân nhánh theo rule động**
- **Thiếu công cụ debug, trace query, hoặc audit logic một cách rõ ràng**
- **Fuzzy matching bị giới hạn hoặc phải mở rộng bằng custom script (tốn effort, scale không tốt)**

---

## ✅ Lý do chọn SQL-based engine (PostgreSQL 16+)

Dùng PostgreSQL cho phép bạn xây dựng một **identity resolution engine tinh gọn, mở rộng được và kiểm soát chặt chẽ**, nhờ:

### 💡 Ưu điểm vượt trội:

- 🔁 **Tái sử dụng rule dễ dàng** qua view/stored procedure
- 🧩 **Dynamic rule logic** được config từ table (`cdp_profile_attributes`) → không cần hardcode
- 🔍 **Dễ trace**: có thể log lại từng bước match, từng điều kiện khớp
- 🧪 **Testing & audit dễ dàng**: chỉ cần chạy lại SQL để so sánh version logic trước/sau
- 🧠 **Fuzzy matching & scoring** bằng `pg_trgm`, `Levenshtein`, `bloom` extension — không cần dùng tool ngoài

---

### 🛠 Case cụ thể bạn có thể làm với PostgreSQL mà NoSQL khó:

| Use Case | PostgreSQL | NoSQL |
|----------|------------|-------|
| Match theo logic `IF email match OR (phone + name match)` | ✅ Rất dễ với CTE + IF | ❌ Phải xử lý ở app |
| Fuzzy match tên hoặc địa chỉ | ✅ Với `pg_trgm`, `SIMILARITY()` | 🔶 Có thể với plugin | 
| Truy xuất & debug logic match cụ thể | ✅ Truy vấn log & trace đơn giản | ❌ Không rõ ràng |
| Dynamic rule (config từ bảng) | ✅ Full support | ❌ Khó, phải code lại |
| So sánh version matching rule qua thời gian | ✅ Dùng audit log hoặc trigger | ❌ Không có native support |


---

## ⚡ Kết quả: Real-time AI Agentic Engagement

Khi danh tính được phân giải thành công:
- System sẽ notify qua **SNS hoặc Kafka topic**
- Các **AI Agent** (Zalo, SMS, Web notification,...) có thể tự động gửi message đúng lúc, đúng người

---

## 🧩 Mở rộng & Báo cáo

- Dữ liệu có thể truy vấn real-time qua **Superset** hoặc Athena
- Dashboard phân tích & insight người dùng sẽ luôn cập nhật theo thời gian thực

---

# 📌 Tổng Kết:

✅ PostgreSQL 16 là một lựa chọn **rất thực tế** cho bài toán Identity Resolution:  
- Scale tốt  
- Logic mạnh  
- Không vendor lock-in  
- Hỗ trợ rule động

🔥 Kiến trúc có thể chạy hoàn toàn trên AWS stack hoặc open-source 100%. Tùy vào định hướng đội ngũ và ngân sách.
