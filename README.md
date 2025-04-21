# Real-time Entity Resolution using AWS Tech Stack

## Giới thiệu

Tài liệu này mô tả kiến trúc giải pháp Nhận dạng Thực thể (Entity Resolution) theo thời gian thực sử dụng các dịch vụ của Amazon Web Services (AWS). Mục tiêu là thu thập, xử lý và hợp nhất dữ liệu về các thực thể (ví dụ: khách hàng, sản phẩm) từ nhiều nguồn khác nhau để tạo ra một cái nhìn thống nhất và chính xác, hỗ trợ các hoạt động engagement và phân tích theo thời gian thực.

## Vì sao CDP cần Entity Resolution hay Customer Identity Resolution - CIR

![data-unification](data-unification.png)


Việc **hợp nhất dữ liệu khách hàng từ nhiều nguồn thành một hồ sơ duy nhất** (Customer Identity Resolution - CIR) là **chìa khóa nền tảng** để xây dựng bất kỳ chiến lược data-driven nào trong kỷ nguyên AI và cá nhân hóa. CIR là "must-have" feature của mọi CDP (Customer Data Platform) 

Dưới đây là **5 lý do cấp thiết** vì sao doanh nghiệp nên ưu tiên thực hiện điều này càng sớm càng tốt:

### 1. **Tạo góc nhìn 360° về khách hàng**

- Không thể phục vụ đúng người nếu không hiểu họ thực sự là ai.
- Khi dữ liệu từ web, app, CRM, email, social, offline... được hợp nhất, bạn có một cái nhìn toàn diện về hành vi, nhu cầu, giá trị vòng đời (CLV) và lịch sử tương tác của mỗi khách hàng.
- Đây là nền tảng để phân khúc sâu hơn, đưa ra dự đoán hành vi, và xây dựng chiến lược cá nhân hóa có tác động thực sự.

### 2. **Tăng độ chính xác trong phân tích và dự đoán**

- Garbage in = Garbage out. Dữ liệu sai sẽ làm hỏng mọi mô hình.
- Nếu dữ liệu khách hàng bị phân mảnh hoặc trùng lặp, mọi phân tích – từ marketing attribution đến mô hình AI – đều bị sai lệch.
- CIR làm sạch và thống nhất dữ liệu đầu vào, giúp các thuật toán và dashboard phản ánh đúng thực tế.

### 3. **Tối ưu hiệu suất marketing và ngân sách**
- Gửi thông tin content và product đúng người = ít tốn tiền, hiệu quả cao.
- Khi biết rõ ai là ai, bạn tránh việc gửi trùng thông điệp, chạy quảng cáo lặp lại, hoặc remarketing sai người.
- CIR giúp tiết kiệm chi phí quảng cáo, tăng ROI chiến dịch và giảm churn thông qua các tương tác đúng thời điểm.

### 4. **Hỗ trợ trải nghiệm khách hàng liền mạch (Omni-channel CX)**

- Khách hàng kỳ vọng bạn "nhớ họ" dù tương tác ở bất kỳ kênh nào.
- CIR giúp đảm bảo rằng mọi bộ phận – từ CSKH đến marketing – đều nhìn thấy cùng một thông tin khách hàng, ở mọi điểm chạm (touchpoint).
- Điều này tạo nên trải nghiệm mượt mà, nhất quán và tăng độ hài lòng khách hàng.

### 5. **Tuân thủ pháp lý và bảo mật dữ liệu**

- Không chỉ là hiệu quả, mà còn là sống còn.
- Các quy định như GDPR, CCPA yêu cầu bạn phải biết rõ bạn lưu trữ thông tin gì, ở đâu, và ai có quyền truy cập.
- CIR giúp gom dữ liệu về một nơi, dễ dàng thực hiện các quyền của khách hàng như "xóa", "sửa", hay "yêu cầu truy cập".

### 👉 Bottom line:

**Nếu không làm CIR, bạn đang ra quyết định dựa trên bức tranh mờ nhòe về khách hàng.**  
Không có CIR, mọi nỗ lực AI/ML/CDP/Personalization chỉ là “dựng lâu đài trên cát”.

## Kiến trúc Tổng thể

![Flow Diagram](diagram.png)

Kiến trúc giải pháp bao gồm các luồng dữ liệu chính: thu thập sự kiện, xử lý sự kiện thành thực thể, nhận dạng và hợp nhất thực thể, cập nhật metadata, và tiêu thụ dữ liệu đã giải quyết cho engagement và phân tích.

## Các Thành phần Chính

1.  **Lead / Customer:** Các thực thể chính mà chúng ta muốn nhận dạng và hợp nhất.

2.  **Touchpoints (Web, Mobile App, IoT...):** Các điểm tương tác nơi sự kiện (event) được tạo ra.

3.  **Event Sources (with SDK):** Các nguồn phát sinh sự kiện, thường sử dụng SDK để định dạng và gửi dữ liệu.

4.  **AWS Firehose:** Dịch vụ thu thập và phân phối dữ liệu stream theo thời gian thực, được sử dụng để thu thập các sự kiện.

5.  **Raw Data Lake (AWS S3):** Kho lưu trữ dữ liệu thô dựa trên Amazon S3, nơi Firehose có thể sao lưu hoặc phân phối dữ liệu thô.

6.  **F2: Event To Entities (Lambda):** Một Lambda function xử lý sự kiện thô từ hàng đợi dữ liệu (Data Queue).

    - 1. Pull Raw Record from Data Queue: Lấy dữ liệu thô.

    - 2. Transform Raw Record to Clean Event: Chuyển đổi và làm sạch dữ liệu sự kiện.

    - 3. Data Validation & build Profile Entities: Xác thực dữ liệu và xây dựng các thực thể profile.

    - 4. Save Profile Entities into PostgreSQL: Lưu các thực thể profile vào cơ sở dữ liệu PostgreSQL.

7.  **Entity Resolution Service (PostgreSQL 16+):** Cơ sở dữ liệu PostgreSQL (phiên bản 16 trở lên) đóng vai trò là trung tâm lưu trữ và thực thi logic nhận dạng thực thể.

8.  **CDP Admin DB:** Cơ sở dữ liệu quản trị cho Nền tảng Dữ liệu Khách hàng (CDP), có thể lưu trữ các cấu hình và dữ liệu quản trị khác.

9.  **F1: Profile Attributes (Lambda):**
    Một Lambda function có nhiệm vụ cập nhật metadata vào bảng `profile_attributes` trong Entity Resolution Service DB. Dữ liệu metadata này được lấy từ CDP Admin DB.

        Flow:
        CDP Admin -> CDP Admin DB -> F1 Lambda -> Bảng `profile_attributes` (trong Entity Resolution Service DB)

10. **AWS SNS / Apache Kafka:** Hệ thống nhắn tin/streaming được sử dụng để phân phối các sự kiện (ví dụ: sự kiện Entity Resolution với master profile đã giải quyết).

11. **F3: Notify event: Resolution is finished (Lambda):** Một Lambda function được kích hoạt bởi sự kiện từ SNS/Kafka, thông báo khi quá trình nhận dạng hoàn tất cho một thực thể.

12. **Real-time Engagement Channels / AI Agents:** Các hệ thống tiêu thụ dữ liệu thực thể đã giải quyết hoặc các sự kiện thông báo để thực hiện các hoạt động engagement (ví dụ: gửi thông báo Zalo, SMS, Push Notification, tương tác Chatbot).

13. **Monitor Real-time Entity Resolution Service:** Thành phần giám sát hiệu suất và trạng thái của dịch vụ nhận dạng thực thể.

14. **AWS Athena:** Dịch vụ truy vấn dữ liệu trực tiếp trên Data Lake (S3) bằng SQL, được sử dụng cho các báo cáo Ad-hoc.

15. **ElastiCache:** Dịch vụ caching, có thể được sử dụng để lưu trữ các thực thể profile hoặc kết quả nhận dạng thường xuyên truy cập để giảm độ trễ.

16. **Apache Superset / Analytics Dashboard / Data Analyst:** Bộ công cụ và người dùng cuối cho phân tích dữ liệu, truy vấn dữ liệu đã giải quyết hoặc dữ liệu thô trong Data Lake.

## Luồng Xử lý Dữ liệu Chính

1.  Sự kiện được tạo ra tại các **Touchpoints** và gửi từ **Event Sources**.

2.  Sự kiện được thu thập bởi **AWS Firehose**.

3.  Firehose đẩy dữ liệu sự kiện vào **Raw Data Lake (AWS S3)** để lưu trữ lâu dài.

4.  **F2: Convert Event To Entity (Lambda)** kéo dữ liệu từ hàng đợi dữ liệu (có thể là một Kinesis Stream hoặc đọc trực tiếp từ S3/Firehose buffer), chuyển đổi, xác thực và xây dựng các thực thể profile.

5.  Các thực thể profile được lưu vào **Entity Resolution Service (PostgreSQL)**.

6.  Logic nhận dạng thực thể chạy trong **PostgreSQL** để hợp nhất các thực thể profile thành các thực thể duy nhất.

7.  Metadata về các thuộc tính profile được quản lý và cập nhật thông qua **CDP Admin DB** và **F1: Profile Attributes (Lambda)**.

8.  Khi quá trình nhận dạng hoàn tất, một sự kiện thông báo được gửi qua **AWS SNS / Apache Kafka**.

9.  **F3: Notify event: Resolution is finished (Lambda)** nhận thông báo và thực hiện các hành động cần thiết (ví dụ: thông báo cho các hệ thống khác).

10. Các kênh **Real-time Engagement Channels / AI Agents** sử dụng dữ liệu thực thể đã giải quyết và các sự kiện thông báo để tương tác với khách hàng.

## Quá Trình Nhận Dạng Thực Thể trong Database

Quá trình nhận dạng thực thể chi tiết được thực thi trong cơ sở dữ liệu PostgreSQL bao gồm các bước:

1. **Raw Data Ingestion:** Dữ liệu thô được đưa vào database (từ F2 Lambda).

2. **Initiate Resolution:** Bắt đầu quá trình nhận dạng (có thể bằng trigger hoặc lịch trình).

3. **Select Data for Processing:** Chọn các bản ghi dữ liệu thô cần xử lý (ví dụ: các bản ghi mới hoặc chưa xử lý).

4. **Load Existing Context & Rules:** Tải các thực thể đã có và các quy tắc nhận dạng (từ bảng master, links, và profile attributes).

5. **Execute Resolution Logic:** Thực thi logic so sánh, ghép nối và đưa ra quyết định hợp nhất.

6. **Persist Resolved State:** Lưu trạng thái đã giải quyết (cập nhật master profiles, ghi links).

7. **Finalize Source Data:** Đánh dấu hoặc xử lý dữ liệu thô đã được xử lý.

8. **Expose Resolved Data:** Chuẩn bị dữ liệu đã giải quyết cho các hệ thống tiêu thụ.

## Phân tích Dữ liệu

- Dữ liệu thô trong **Raw Data Lake (S3)** có thể được truy vấn trực tiếp bằng **AWS Athena** cho các báo cáo Ad-hoc.

- Dữ liệu thực thể đã giải quyết trong **PostgreSQL** có thể được truy cập bởi **Apache Superset** hoặc các **Analytics Dashboard** khác để phân tích bởi **Data Analyst**.

- **ElastiCache** có thể tăng tốc truy vấn cho các dữ liệu thường xuyên được truy cập.

Giải pháp này cung cấp một framework toàn diện cho nhận dạng thực thể theo thời gian thực, tận dụng nhiều dịch vụ quản lý của AWS để đảm bảo khả năng mở rộng, độ tin cậy và hiệu suất
