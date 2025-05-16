# Tài liệu các Trường tính điểm trong CDP Master Profiles

Tài liệu này giải thích các trường tính điểm chính trong bảng `cdp_master_profiles`, bao gồm logic tính toán, giá trị mẫu và các trường hợp sử dụng. Các trường này giúp tăng cường khả năng cá nhân hóa, phân khúc và phân tích dự đoán.

-----

## 1\. `engagement_score` (INT - Số nguyên)

**Tiếng Việt:** Điểm Tương Tác

**Mô tả:** Chỉ số tổng hợp phản ánh mức độ tích cực của khách hàng khi tương tác trên các điểm chạm (touchpoints) khác nhau. Điểm càng cao cho thấy khách hàng càng tương tác nhiều.

**Giá trị mẫu:** `73`

**Logic tính toán:** Dựa trên việc tổng hợp có trọng số của các hành động:

  * `pageviews`: Số lần xem trang.
  * `session_duration`: Thời lượng phiên truy cập.
  * `clicks`: Số lần nhấp chuột.
  * `video_views`: Số lần xem video.
  * `scroll_depth`: Độ sâu cuộn trang.

**Giải thích chi tiết hơn:**
Điểm tương tác được tính bằng cách gán trọng số khác nhau cho từng loại hành động của người dùng. Ví dụ, một "click" có thể được coi là quan trọng hơn một "pageview" đơn thuần, và do đó có trọng số cao hơn. Thời gian người dùng ở lại trang (`session_time`) cũng đóng góp vào điểm số này, nhưng có thể với trọng số thấp hơn trên mỗi đơn vị thời gian so với các hành động chủ động khác. Hàm `LEAST` được sử dụng để giới hạn giá trị tối đa của mỗi sự kiện, tránh trường hợp một sự kiện đơn lẻ có giá trị quá lớn làm sai lệch điểm số tổng thể.

**Công thức mẫu (SQL):**

```sql
engagement_score = (
    LEAST(event_summary->>'page_view')::INT * 1 +  -- Số lượt xem trang nhân với trọng số 1
    LEAST(event_summary->>'click')::INT * 2 +      -- Số lượt click nhân với trọng số 2
    LEAST(event_summary->>'session_time')::INT * 0.1 -- Thời gian phiên (giây) nhân với trọng số 0.1
)::INT -- Kết quả cuối cùng là một số nguyên
```

**Dữ liệu mẫu (cho `event_summary` trong `cdp_master_profiles`):**

```json
{
  "page_view": 15,
  "click": 5,
  "session_time": 300, // tính bằng giây
  "video_views": 2,
  "scroll_depth": 75 // phần trăm
}
```

**Unit Test (Python):**

```python
import unittest
import json

def calculate_engagement_score(event_summary_json_str):
    """
    Tính toán điểm tương tác dựa trên event_summary.
    """
    if not event_summary_json_str:
        return 0
    try:
        event_summary = json.loads(event_summary_json_str)
    except json.JSONDecodeError:
        return 0 # Hoặc xử lý lỗi theo cách khác

    page_views = int(event_summary.get('page_view', 0))
    clicks = int(event_summary.get('click', 0))
    session_time = int(event_summary.get('session_time', 0)) # Giả sử session_time tính bằng giây

    # Áp dụng công thức mẫu, hàm LEAST được ngầm hiểu là giá trị không vượt quá một ngưỡng nào đó
    # Trong ví dụ này, chúng ta lấy trực tiếp giá trị
    # Để đơn giản, không dùng LEAST ở đây, nhưng trong thực tế có thể có giới hạn trên
    score = (page_views * 1) + (clicks * 2) + (session_time * 0.1)
    return int(score)

class TestEngagementScore(unittest.TestCase):
    def test_calculate_engagement_score(self):
        event_summary_data = {
            "page_view": 15,
            "click": 5,
            "session_time": 300, # 300 giây = 5 phút
            "video_views": 2,
            "scroll_depth": 75
        }
        event_summary_json = json.dumps(event_summary_data)
        expected_score = int((15 * 1) + (5 * 2) + (300 * 0.1)) # 15 + 10 + 30 = 55
        self.assertEqual(calculate_engagement_score(event_summary_json), expected_score)

    def test_missing_fields(self):
        event_summary_data = {
            "page_view": 10
            # click và session_time bị thiếu
        }
        event_summary_json = json.dumps(event_summary_data)
        expected_score = int((10 * 1) + (0 * 2) + (0 * 0.1)) # 10
        self.assertEqual(calculate_engagement_score(event_summary_json), expected_score)

    def test_empty_summary(self):
        self.assertEqual(calculate_engagement_score(None), 0)
        self.assertEqual(calculate_engagement_score(""), 0)
        self.assertEqual(calculate_engagement_score("{}"), 0)

# Để chạy unit test (ví dụ trong một file .py):
# if __name__ == '__main__':
#     unittest.main(argv=['first-arg-is-ignored'], exit=False)
```

**Trường hợp sử dụng:**

  * **Cá nhân hóa nội dung:** Hiển thị nội dung phù hợp với mức độ tương tác của khách hàng. Khách hàng có điểm tương tác cao có thể được hiển thị nội dung chuyên sâu hơn hoặc các ưu đãi đặc biệt.
  * **Phân khúc đối tượng:** Nhóm khách hàng dựa trên mức độ tương tác (ví dụ: "rất năng động", "khá năng động", "ít năng động") để có các chiến dịch marketing phù hợp.
  * **Dự đoán lòng trung thành:** Khách hàng có điểm tương tác cao thường có xu hướng trung thành hơn.

-----

## 2\. `lead_score` (INT - Số nguyên)

**Tiếng Việt:** Điểm Tiềm Năng (Lead)

**Mô tả:** Xác suất (từ 0 đến 100) mà một liên hệ (contact) có khả năng chuyển đổi thành khách hàng thực sự hoặc thể hiện ý định mua hàng. Điểm càng cao, tiềm năng càng lớn.

**Giá trị mẫu:** `85`

**Logic tính toán:** Được tính toán thông qua một mô hình chấm điểm tiềm năng (lead scoring model) sử dụng dữ liệu hành vi, nhân khẩu học và giao dịch.

**Giải thích chi tiết hơn:**
Điểm tiềm năng giúp đội ngũ bán hàng và marketing tập trung vào những liên hệ có khả năng chuyển đổi cao nhất. Mô hình này thường là một mô hình học máy (Machine Learning - ML) được huấn luyện trên dữ liệu lịch sử. Các "features" (đặc điểm) đầu vào cho mô hình này rất đa dạng, phản ánh nhiều khía cạnh của một tiềm năng.

**Các đặc điểm (Features) có thể bao gồm:**

  * Mức độ gần đây của tương tác cuối (`recency_score` - điểm gần đây).
  * `total_sessions`: Tổng số phiên truy cập.
  * `avg_order_value`: Giá trị đơn hàng trung bình.
  * `email_open_rate`: Tỷ lệ mở email.
  * Mức độ hoàn thiện hồ sơ (Profile completeness).
  * Nguồn của tiềm năng (ví dụ: từ webinar, form đăng ký, quảng cáo).
  * Chức danh, công ty (cho B2B).
  * Số trang sản phẩm đã xem.

**Công thức (Ví dụ trong một quy trình ML):**

```python
# profile_features là một vector chứa các giá trị đặc điểm của hồ sơ
# model.predict_proba(profile_features) trả về một mảng xác suất cho mỗi lớp (ví dụ: [P(không chuyển đổi), P(chuyển đổi)])
# Chúng ta lấy P(chuyển đổi) (thường là phần tử thứ 2, index 1) và nhân với 100
lead_score = int(model.predict_proba(profile_features)[0][1] * 100) # Giả sử model.predict_proba trả về [[P0, P1]]
```

**Dữ liệu mẫu (các trường có thể dùng để tính `lead_score`):**

Một hồ sơ khách hàng có thể có các thông tin sau:

  * `master_profile_id`: `uuid_example_123`
  * `recency_score`: `80`
  * `total_sessions`: `25`
  * `avg_order_value`: `1500000` (VND)
  * `email_open_rate`: `0.65` (65%)
  * `profile_completeness_percent`: `90` (tính toán từ việc điền các trường thông tin)
  * `last_form_submission`: `'contact_us'`
  * `pages_viewed_product_X`: `5`

**Unit Test (Python):**

```python
import unittest
import numpy as np

# Giả lập một mô hình ML đơn giản
class MockLeadScoringModel:
    def predict_proba(self, profile_features):
        # Logic giả lập: ví dụ, nếu 'recency_score' > 70 và 'total_sessions' > 20
        # thì xác suất chuyển đổi cao.
        # profile_features nên là một mảng numpy 2D [[feature1, feature2, ...]]
        if not isinstance(profile_features, np.ndarray) or profile_features.ndim != 2:
            raise ValueError("profile_features phải là một mảng numpy 2D")

        probabilities = []
        for features_row in profile_features:
            # Giả sử thứ tự đặc điểm: [recency_score, total_sessions, avg_order_value, email_open_rate]
            recency = features_row[0]
            sessions = features_row[1]
            # avg_order_value = features_row[2] # Không dùng trong logic giả lập này
            # email_open_rate = features_row[3] # Không dùng trong logic giả lập này

            # Đây là logic rất đơn giản, mô hình thực tế sẽ phức tạp hơn nhiều
            if recency > 70 and sessions > 20:
                prob_conversion = 0.85  # Xác suất chuyển đổi cao
            elif recency > 50 or sessions > 10:
                prob_conversion = 0.50  # Xác suất trung bình
            else:
                prob_conversion = 0.15  # Xác suất thấp
            probabilities.append([1 - prob_conversion, prob_conversion])
        return np.array(probabilities)

def calculate_lead_score(model, profile_features_dict):
    """
    Tính toán điểm tiềm năng sử dụng mô hình ML giả lập.
    profile_features_dict: một dictionary chứa các đặc điểm.
    """
    # Chuyển đổi dict thành mảng theo đúng thứ tự mà mô hình mong đợi
    # Giả sử thứ tự: [recency_score, total_sessions, avg_order_value, email_open_rate]
    # Cần xử lý trường hợp thiếu key một cách cẩn thận hơn trong thực tế
    features_array = np.array([[
        profile_features_dict.get('recency_score', 0),
        profile_features_dict.get('total_sessions', 0),
        profile_features_dict.get('avg_order_value', 0),
        profile_features_dict.get('email_open_rate', 0.0)
    ]])

    # model.predict_proba trả về [[P(không chuyển đổi), P(chuyển đổi)]]
    probability_of_conversion = model.predict_proba(features_array)[0][1]
    return int(probability_of_conversion * 100)

class TestLeadScore(unittest.TestCase):
    def setUp(self):
        self.model = MockLeadScoringModel()

    def test_high_potential_lead(self):
        profile_features = {
            'recency_score': 80,
            'total_sessions': 25,
            'avg_order_value': 1500000,
            'email_open_rate': 0.65
        }
        expected_score = 85 # Theo logic giả lập của MockLeadScoringModel
        self.assertEqual(calculate_lead_score(self.model, profile_features), expected_score)

    def test_medium_potential_lead(self):
        profile_features = {
            'recency_score': 60,
            'total_sessions': 15,
            'avg_order_value': 500000,
            'email_open_rate': 0.30
        }
        expected_score = 50 # Theo logic giả lập
        self.assertEqual(calculate_lead_score(self.model, profile_features), expected_score)

    def test_low_potential_lead(self):
        profile_features = {
            'recency_score': 30,
            'total_sessions': 5,
            'avg_order_value': 100000,
            'email_open_rate': 0.10
        }
        expected_score = 15 # Theo logic giả lập
        self.assertEqual(calculate_lead_score(self.model, profile_features), expected_score)

# Để chạy unit test:
# if __name__ == '__main__':
#     unittest.main(argv=['first-arg-is-ignored'], exit=False)
```

**Siêu dữ liệu (Metadata):**

  * `lead_score_model_version`: Phiên bản của mô hình chấm điểm tiềm năng được sử dụng. Quan trọng để theo dõi hiệu suất và cập nhật mô hình.
  * `lead_score_last_updated`: Thời điểm cuối cùng điểm tiềm năng được cập nhật.

**Trường hợp sử dụng:**

  * **Ưu tiên bán hàng (Sales prioritization):** Giúp đội ngũ bán hàng tập trung vào các tiềm năng có điểm số cao nhất.
  * **Tự động hóa chiến dịch (Campaign automation):** Tự động gửi email marketing, tin nhắn hoặc các tương tác khác dựa trên điểm tiềm năng. Ví dụ, tiềm năng có điểm cao có thể nhận được cuộc gọi từ sale, trong khi tiềm năng điểm thấp hơn có thể nhận email nuôi dưỡng.
  * **Chấm điểm trong CRM (CRM scoring):** Tích hợp điểm tiềm năng vào hệ thống CRM để cung cấp cái nhìn toàn diện về khách hàng.

-----

## 3\. `recency_score` (INT - Số nguyên)

**Tiếng Việt:** Điểm Gần Đây

**Mô tả:** Điểm số cho biết khách hàng hoạt động gần đây như thế nào. Điểm cao hơn có nghĩa là hoạt động gần đây hơn. Thang điểm thường từ 0-100.

**Giá trị mẫu:** `90`

**Logic tính toán:** Được suy ra từ `last_seen_at` (thời điểm nhìn thấy lần cuối). Hoạt động gần đây dẫn đến điểm số cao hơn.

**Giải thích chi tiết hơn:**
Điểm này rất quan trọng vì khách hàng tương tác gần đây thường dễ tiếp cận và có nhiều khả năng phản hồi hơn với các chiến dịch marketing. Logic tính toán thường dựa trên các khoảng thời gian xác định trước.

**Chấm điểm dựa trên quy tắc mẫu (SQL):**

```sql
CASE
  WHEN last_seen_at >= NOW() - INTERVAL '7 days' THEN 100 -- Hoạt động trong vòng 7 ngày gần nhất
  WHEN last_seen_at >= NOW() - INTERVAL '30 days' THEN 75 -- Hoạt động trong vòng 30 ngày gần nhất
  WHEN last_seen_at >= NOW() - INTERVAL '90 days' THEN 50 -- Hoạt động trong vòng 90 ngày gần nhất
  WHEN last_seen_at >= NOW() - INTERVAL '180 days' THEN 25 -- Hoạt động trong vòng 180 ngày gần nhất
  ELSE 0 -- Hoạt động hơn 180 ngày trước hoặc không có dữ liệu
END AS recency_score
```

**Dữ liệu mẫu (cho trường `last_seen_at` trong `cdp_master_profiles`):**

Giả sử thời điểm hiện tại (NOW) là `2025-05-15 10:00:00 UTC`.

  * Hồ sơ 1: `last_seen_at` = `2025-05-10 12:00:00 UTC` (Cách đây 5 ngày)
  * Hồ sơ 2: `last_seen_at` = `2025-04-20 08:00:00 UTC` (Cách đây 25 ngày)
  * Hồ sơ 3: `last_seen_at` = `2025-01-15 15:00:00 UTC` (Cách đây 120 ngày)
  * Hồ sơ 4: `last_seen_at` = `2024-05-15 10:00:00 UTC` (Cách đây 365 ngày)
  * Hồ sơ 5: `last_seen_at` = `NULL`

**Unit Test (Python):**

```python
import unittest
from datetime import datetime, timedelta, timezone

def calculate_recency_score(last_seen_at_str, current_time_str):
    """
    Tính toán điểm gần đây dựa trên last_seen_at.
    last_seen_at_str: Chuỗi thời gian ISO format (ví dụ: '2025-05-10T12:00:00Z')
    current_time_str: Chuỗi thời gian hiện tại ISO format
    """
    if not last_seen_at_str:
        return 0

    try:
        # Chuyển đổi chuỗi thời gian sang đối tượng datetime có thông tin timezone
        # Giả sử đầu vào là UTC (có 'Z' hoặc +00:00)
        last_seen_at = datetime.fromisoformat(last_seen_at_str.replace('Z', '+00:00'))
        current_time = datetime.fromisoformat(current_time_str.replace('Z', '+00:00'))
    except ValueError:
        return 0 # Xử lý lỗi nếu định dạng thời gian không đúng

    # Đảm bảo cả hai đều là timezone-aware (UTC) để so sánh
    if last_seen_at.tzinfo is None:
        last_seen_at = last_seen_at.replace(tzinfo=timezone.utc)
    if current_time.tzinfo is None:
        current_time = current_time.replace(tzinfo=timezone.utc)

    if last_seen_at >= current_time - timedelta(days=7):
        return 100
    elif last_seen_at >= current_time - timedelta(days=30):
        return 75
    elif last_seen_at >= current_time - timedelta(days=90):
        return 50
    elif last_seen_at >= current_time - timedelta(days=180):
        return 25
    else:
        return 0

class TestRecencyScore(unittest.TestCase):
    def setUp(self):
        self.current_time_fixed = "2025-05-15T10:00:00Z"

    def test_within_7_days(self):
        last_seen = (datetime.fromisoformat(self.current_time_fixed.replace('Z', '+00:00')) - timedelta(days=5)).isoformat() + "Z"
        self.assertEqual(calculate_recency_score(last_seen, self.current_time_fixed), 100)

    def test_within_30_days(self):
        last_seen = (datetime.fromisoformat(self.current_time_fixed.replace('Z', '+00:00')) - timedelta(days=25)).isoformat() + "Z"
        self.assertEqual(calculate_recency_score(last_seen, self.current_time_fixed), 75)

    def test_within_90_days(self):
        last_seen = (datetime.fromisoformat(self.current_time_fixed.replace('Z', '+00:00')) - timedelta(days=80)).isoformat() + "Z"
        self.assertEqual(calculate_recency_score(last_seen, self.current_time_fixed), 50)

    def test_within_180_days(self):
        last_seen = (datetime.fromisoformat(self.current_time_fixed.replace('Z', '+00:00')) - timedelta(days=150)).isoformat() + "Z"
        self.assertEqual(calculate_recency_score(last_seen, self.current_time_fixed), 25)

    def test_older_than_180_days(self):
        last_seen = (datetime.fromisoformat(self.current_time_fixed.replace('Z', '+00:00')) - timedelta(days=200)).isoformat() + "Z"
        self.assertEqual(calculate_recency_score(last_seen, self.current_time_fixed), 0)

    def test_null_last_seen(self):
        self.assertEqual(calculate_recency_score(None, self.current_time_fixed), 0)
        self.assertEqual(calculate_recency_score("", self.current_time_fixed), 0)

# Để chạy unit test:
# if __name__ == '__main__':
#     unittest.main(argv=['first-arg-is-ignored'], exit=False)
```

**Trường hợp sử dụng:**

  * **Chiến dịch giành lại khách hàng (Win-back campaigns):** Nhắm mục tiêu vào những khách hàng có điểm gần đây thấp (hoạt động từ lâu) với các ưu đãi đặc biệt để khuyến khích họ quay lại.
  * **Phân khúc dựa trên hoạt động:** Tạo các phân khúc như "khách hàng tích cực gần đây", "khách hàng ngủ đông" để gửi thông điệp phù hợp.
  * **Phân loại giai đoạn hành trình (Journey stage classification):** Xác định xem khách hàng đang ở giai đoạn nào trong hành trình của họ (ví dụ: mới, đang hoạt động, có nguy cơ rời bỏ) dựa trên mức độ hoạt động gần đây.

-----

## 4\. `churn_probability` (NUMERIC - Số thập phân)

**Tiếng Việt:** Xác Suất Rời Bỏ (Churn)

**Mô tả:** Xác suất dự đoán khách hàng sẽ rời bỏ (ngừng sử dụng dịch vụ, không mua hàng nữa). Được biểu thị dưới dạng số thập phân từ 0.0000 đến 1.0000. Ví dụ, 0.8723 có nghĩa là 87.23% khả năng khách hàng sẽ rời bỏ.

**Giá trị mẫu:** `0.8723`

**Logic tính toán:** Là đầu ra của một mô hình phân loại (classification model) sử dụng dữ liệu hành vi lịch sử, tình trạng không hoạt động của sự kiện và sự suy giảm của hồ sơ.

**Giải thích chi tiết hơn:**
Dự đoán churn là một ứng dụng quan trọng của CDP và học máy. Bằng cách xác định sớm những khách hàng có nguy cơ rời bỏ cao, doanh nghiệp có thể triển khai các biện pháp giữ chân chủ động. Mô hình này học từ các mẫu hành vi của những khách hàng đã rời bỏ trong quá khứ.

**Các đặc điểm (Features) có thể bao gồm:**

  * Số ngày kể từ lần mua hàng cuối cùng.
  * Sự sụt giảm trong điểm tương tác (`engagement_score`).
  * Tần suất tương tác/mua hàng giảm trong 90 ngày qua.
  * Số lượng khiếu nại hoặc phản hồi NPS (Net Promoter Score) tiêu cực.
  * Thời gian sử dụng dịch vụ (customer tenure).
  * Thay đổi trong việc sử dụng các tính năng chính của sản phẩm/dịch vụ.
  * Số lần đăng nhập giảm.
  * Không mở email marketing gần đây.

**Công thức (Ví dụ trong một quy trình ML):**
Tương tự như `lead_score`, `churn_probability` thường được tính bằng một mô hình học máy.

```python
# churn_model là mô hình phân loại đã được huấn luyện
# customer_features là vector đặc điểm của khách hàng liên quan đến khả năng churn
# model.predict_proba(customer_features) trả về [P(không churn), P(churn)]
churn_probability = churn_model.predict_proba(customer_features)[0][1] # Lấy xác suất churn
```

**Dữ liệu mẫu (các trường có thể dùng để tính `churn_probability`):**

  * `master_profile_id`: `uuid_example_456`
  * `days_since_last_purchase`: `120`
  * `engagement_score_trend`: `-15` (điểm tương tác giảm 15 điểm so với giai đoạn trước)
  * `purchase_frequency_last_90_days`: `0` (không mua hàng trong 90 ngày)
  * `number_of_complaints`: `2`
  * `nps_score`: `3` (thấp)
  * `login_frequency_drop_percentage`: `0.5` (tần suất đăng nhập giảm 50%)

**Unit Test (Python):**

```python
import unittest
import numpy as np

# Giả lập một mô hình ML dự đoán churn
class MockChurnModel:
    def predict_proba(self, customer_features):
        # customer_features nên là một mảng numpy 2D [[feature1, feature2, ...]]
        if not isinstance(customer_features, np.ndarray) or customer_features.ndim != 2:
            raise ValueError("customer_features phải là một mảng numpy 2D")

        probabilities = []
        for features_row in customer_features:
            # Giả sử thứ tự đặc điểm:
            # [days_since_last_purchase, engagement_score_trend_negative, purchase_freq_90d, num_complaints]
            days_last_purchase = features_row[0]
            engagement_drop = features_row[1] # Giá trị dương nếu có sụt giảm
            purchase_freq = features_row[2]
            complaints = features_row[3]

            # Logic giả lập rất đơn giản
            prob_churn = 0.1 # Mặc định
            if days_last_purchase > 90: prob_churn += 0.2
            if engagement_drop > 10: prob_churn += 0.2
            if purchase_freq == 0 and days_last_purchase > 60 : prob_churn += 0.3
            if complaints > 1: prob_churn += 0.2

            prob_churn = min(prob_churn, 0.95) # Giới hạn xác suất tối đa
            probabilities.append([1 - prob_churn, prob_churn])
        return np.array(probabilities)


def calculate_churn_probability(model, customer_features_dict):
    """
    Tính toán xác suất churn sử dụng mô hình ML giả lập.
    customer_features_dict: một dictionary chứa các đặc điểm.
    """
    # Chuyển đổi dict thành mảng theo đúng thứ tự mà mô hình mong đợi
    # Giả sử thứ tự: [days_since_last_purchase, engagement_score_trend_negative, purchase_freq_90d, num_complaints]
    features_array = np.array([[
        customer_features_dict.get('days_since_last_purchase', 0),
        abs(customer_features_dict.get('engagement_score_trend', 0)) if customer_features_dict.get('engagement_score_trend', 0) < 0 else 0, # Chỉ lấy giá trị sụt giảm (dương)
        customer_features_dict.get('purchase_frequency_last_90_days', 0),
        customer_features_dict.get('number_of_complaints', 0)
    ]])

    probability_of_churn = model.predict_proba(features_array)[0][1]
    return round(probability_of_churn, 4) # Làm tròn đến 4 chữ số thập phân

class TestChurnProbability(unittest.TestCase):
    def setUp(self):
        self.model = MockChurnModel()

    def test_high_churn_risk(self):
        customer_features = {
            'days_since_last_purchase': 120,      # +0.2
            'engagement_score_trend': -15,       # +0.2 (engagement_drop = 15)
            'purchase_frequency_last_90_days': 0,# +0.3
            'number_of_complaints': 2            # +0.2
        }
        # Expected: 0.1 (base) + 0.2 + 0.2 + 0.3 + 0.2 = 1.0, capped at 0.95
        expected_probability = 0.9500
        self.assertEqual(calculate_churn_probability(self.model, customer_features), expected_probability)

    def test_medium_churn_risk(self):
        customer_features = {
            'days_since_last_purchase': 70,      # 0
            'engagement_score_trend': -5,        # 0
            'purchase_frequency_last_90_days': 1,# 0 (days_last_purchase > 60 but purchase_freq != 0)
            'number_of_complaints': 1            # 0
        }
        # Expected: 0.1 (base)
        expected_probability = 0.1000
        self.assertEqual(calculate_churn_probability(self.model, customer_features), expected_probability)

    def test_low_churn_risk(self):
        customer_features = {
            'days_since_last_purchase': 10,
            'engagement_score_trend': 5, # Tăng
            'purchase_frequency_last_90_days': 3,
            'number_of_complaints': 0
        }
        # Expected: 0.1 (base)
        expected_probability = 0.1000
        self.assertEqual(calculate_churn_probability(self.model, customer_features), expected_probability)

# Để chạy unit test:
# if __name__ == '__main__':
#     unittest.main(argv=['first-arg-is-ignored'], exit=False)
```

**Trường hợp sử dụng:**

  * **Chiến dịch giữ chân khách hàng (Retention campaigns):** Nhắm mục tiêu vào những khách hàng có xác suất rời bỏ cao với các ưu đãi cá nhân hóa, hỗ trợ đặc biệt hoặc nội dung giá trị để khuyến khích họ ở lại.
  * **Theo dõi sức khỏe khách hàng dự đoán (Predictive customer health monitoring):** Liên tục theo dõi xác suất churn để phát hiện sớm các dấu hiệu tiêu cực và can thiệp kịp thời.

-----

## 5\. `customer_lifetime_value` (NUMERIC - Số thập phân)

**Tiếng Việt:** Giá Trị Vòng Đời Khách Hàng (CLV hoặc LTV)

**Mô tả:** Tổng doanh thu dự kiến mà một khách hàng sẽ mang lại cho doanh nghiệp trong suốt toàn bộ thời gian họ còn là khách hàng.

**Giá trị mẫu:** `10500000.00` (VND)

**Logic tính toán:**

**Công thức cơ bản (SQL):**

```sql
CLV = avg_order_value * purchase_frequency * expected_customer_lifetime_years
```

Trong đó:

  * `avg_order_value`: Giá trị đơn hàng trung bình của khách hàng.
  * `purchase_frequency`: Tần suất mua hàng trung bình (ví dụ: số lần mua hàng mỗi năm).
  * `expected_customer_lifetime_years`: Số năm dự kiến khách hàng sẽ tiếp tục mua hàng. Đây là thành phần khó ước tính nhất và thường dựa trên dữ liệu lịch sử hoặc mô hình dự đoán.

**Công thức ML nâng cao:**
Sử dụng các mô hình học máy để dự đoán CLV dựa trên một loạt các đặc điểm của khách hàng.

```python
clv = model.predict(customer_features)
```

Các đặc điểm này có thể bao gồm lịch sử mua hàng, hành vi tương tác, thông tin nhân khẩu học, v.v.

**Giải thích chi tiết hơn:**
CLV là một chỉ số quan trọng giúp doanh nghiệp hiểu được giá trị dài hạn của từng khách hàng. Điều này cho phép họ đưa ra quyết định tốt hơn về việc đầu tư vào việc thu hút và giữ chân khách hàng.

**Dữ liệu mẫu (các trường có thể dùng để tính CLV cơ bản):**

  * `master_profile_id`: `uuid_example_789`
  * `avg_order_value` (từ bảng `cdp_master_profiles` hoặc tính toán): `1500000.00` (VND)
  * `total_purchases` (từ `cdp_master_profiles`): `10`
  * `first_purchase_date`: `2022-01-15`
  * `last_purchase_date`: `2024-12-15`
  * `expected_customer_lifetime_years` (ước tính hoặc từ mô hình): `5` (năm)

Để tính `purchase_frequency` (số lần mua hàng mỗi năm):
Số năm khách hàng đã hoạt động = (last\_purchase\_date - first\_purchase\_date) / 365.25
Ví dụ: (2024-12-15 - 2022-01-15) là khoảng 2.91 năm.
`purchase_frequency` = `total_purchases` / số năm khách hàng đã hoạt động = 10 / 2.91 ≈ 3.43 lần/năm.

**Unit Test (Python - cho công thức cơ bản):**

```python
import unittest
from datetime import date

def calculate_clv_basic(avg_order_value_input, total_purchases, first_purchase_date_str, last_purchase_date_str, expected_lifetime_years):
    """
    Tính toán CLV cơ bản.
    avg_order_value_input: Có thể là giá trị trực tiếp hoặc None (nếu cần tính từ total_value / total_purchases)
    """
    if not all([total_purchases, first_purchase_date_str, last_purchase_date_str, expected_lifetime_years]):
        return 0.0
    if total_purchases <= 0: # Cần có ít nhất 1 giao dịch để tính AOV hợp lý
        return 0.0

    try:
        first_purchase_date = date.fromisoformat(first_purchase_date_str)
        last_purchase_date = date.fromisoformat(last_purchase_date_str)
    except ValueError:
        return 0.0 # Lỗi định dạng ngày

    # Tính purchase_frequency (số lần mua mỗi năm)
    # Nếu first_purchase_date == last_purchase_date, giả sử là 1 năm hoặc cần logic khác
    customer_active_duration_days = (last_purchase_date - first_purchase_date).days
    if customer_active_duration_days <= 0: # Nếu chỉ có 1 giao dịch hoặc ngày không hợp lệ
        # Nếu chỉ có 1 giao dịch, tần suất khó xác định, có thể giả định 1 lần/năm hoặc theo quy tắc nghiệp vụ
        if total_purchases == 1:
             purchase_frequency_per_year = 1 # Giả định
        else: # Nhiều giao dịch trong cùng 1 ngày, vẫn là tần suất cao trong ngày đó
            purchase_frequency_per_year = total_purchases # Hoặc một cách tính khác
    else:
        customer_active_duration_years = customer_active_duration_days / 365.25
        if customer_active_duration_years == 0: # Tránh chia cho 0 nếu thời gian quá ngắn
            purchase_frequency_per_year = total_purchases # Nếu tất cả giao dịch trong <1 năm
        else:
            purchase_frequency_per_year = total_purchases / customer_active_duration_years

    if avg_order_value_input is None:
        # Cần có tổng giá trị các đơn hàng (total_order_value) để tính avg_order_value
        # Giả sử chúng ta có avg_order_value trực tiếp cho ví dụ này
        return 0.0 # Hoặc raise lỗi
    avg_order_value = float(avg_order_value_input)


    clv = avg_order_value * purchase_frequency_per_year * float(expected_lifetime_years)
    return round(clv, 2)

class TestCLV(unittest.TestCase):
    def test_calculate_clv(self):
        avg_order_value = 1500000.00
        total_purchases = 10
        first_purchase_date = "2022-01-15"
        last_purchase_date = "2024-12-15" # ~2.91 năm hoạt động
        expected_lifetime_years = 5

        # Tính toán thủ công purchase_frequency:
        # duration_years = (date(2024,12,15) - date(2022,1,15)).days / 365.25 = 1065 / 365.25 = 2.9158...
        # purchase_frequency = 10 / 2.9158... = 3.4295...
        # clv = 1500000 * 3.4295... * 5 = 25721691.70...
        # Kết quả của hàm sẽ chính xác hơn
        expected_clv = 25721691.70 # Sẽ được tính chính xác bởi hàm
        calculated_clv = calculate_clv_basic(avg_order_value, total_purchases, first_purchase_date, last_purchase_date, expected_lifetime_years)
        self.assertAlmostEqual(calculated_clv, expected_clv, places=2)

    def test_clv_single_purchase(self):
        # Nếu chỉ có 1 giao dịch, purchase_frequency có thể được giả định là 1 (hoặc theo quy tắc nghiệp vụ)
        avg_order_value = 500000.00
        total_purchases = 1
        first_purchase_date = "2024-01-15"
        last_purchase_date = "2024-01-15" # Cùng ngày
        expected_lifetime_years = 3
        # purchase_frequency = 1 (do giả định)
        # clv = 500000 * 1 * 3 = 1500000
        expected_clv = 1500000.00
        self.assertEqual(calculate_clv_basic(avg_order_value, total_purchases, first_purchase_date, last_purchase_date, expected_lifetime_years), expected_clv)

    def test_clv_short_period_multiple_purchases(self):
        avg_order_value = 200000.00
        total_purchases = 3
        first_purchase_date = "2024-01-01"
        last_purchase_date = "2024-03-01" # 2 tháng
        expected_lifetime_years = 2
        # duration_days = (date(2024,3,1) - date(2024,1,1)).days = 60
        # duration_years = 60 / 365.25 = 0.16427...
        # purchase_frequency = 3 / 0.16427... = 18.26...
        # clv = 200000 * 18.26... * 2 = 7305000.00...
        expected_clv = 7304996.58
        calculated_clv = calculate_clv_basic(avg_order_value, total_purchases, first_purchase_date, last_purchase_date, expected_lifetime_years)
        self.assertAlmostEqual(calculated_clv, expected_clv, places=2)

# Để chạy unit test:
# if __name__ == '__main__':
#     unittest.main(argv=['first-arg-is-ignored'], exit=False)

```

**Trường hợp sử dụng:**

  * **Phân khúc VIP:** Xác định và ưu tiên những khách hàng có CLV cao (khách hàng VIP).
  * **Phân bổ ngân sách:** Quyết định chi bao nhiêu tiền để thu hút một khách hàng mới (Customer Acquisition Cost - CAC) dựa trên CLV dự kiến của họ. Lý tưởng nhất, CAC nên thấp hơn CLV.
  * **Nhắm mục tiêu dựa trên LTV:** Tạo các chiến dịch nhắm vào những khách hàng có tiềm năng mang lại giá trị cao trong dài hạn.

-----

## 6\. `loyalty_tier` (VARCHAR - Chuỗi ký tự)

**Tiếng Việt:** Hạng Khách Hàng Thân Thiết

**Mô tả:** Nhãn phân hạng dựa trên mức độ tương tác và giá trị giao dịch của khách hàng. Ví dụ: Đồng, Bạc, Vàng, Bạch Kim.

**Giá trị mẫu:** `'Gold'`

**Logic tính toán:** Phân hạng dựa trên quy tắc kinh doanh (business rules).

**Giải thích chi tiết hơn:**
Các chương trình khách hàng thân thiết thường phân chia khách hàng thành các hạng khác nhau để cung cấp những quyền lợi và ưu đãi tương ứng. Việc phân hạng này thường dựa trên các ngưỡng cụ thể về số lần mua hàng, tổng chi tiêu, hoặc CLV.

**Logic mẫu dựa trên quy tắc (SQL):**

```sql
CASE
  WHEN total_purchases >= 20 AND customer_lifetime_value >= 10000000 THEN 'Platinum' -- Bạch kim
  WHEN total_purchases >= 10 AND customer_lifetime_value >= 5000000 THEN 'Gold'     -- Vàng (điều chỉnh so với ví dụ gốc để phù hợp hơn)
  WHEN total_purchases >= 5 AND customer_lifetime_value >= 1000000 THEN 'Silver'   -- Bạc (điều chỉnh)
  ELSE 'Bronze' -- Đồng
END
```

*Lưu ý: Ngưỡng CLV trong ví dụ gốc cho hạng Vàng là 10 triệu, giống Bạch kim, đã được điều chỉnh lại cho hợp lý hơn.*

**Dữ liệu mẫu (các trường dùng để xác định `loyalty_tier`):**

  * Hồ sơ A: `total_purchases` = `25`, `customer_lifetime_value` = `12000000.00`
  * Hồ sơ B: `total_purchases` = `15`, `customer_lifetime_value` = `8000000.00`
  * Hồ sơ C: `total_purchases` = `8`, `customer_lifetime_value` = `3000000.00`
  * Hồ sơ D: `total_purchases` = `3`, `customer_lifetime_value` = `500000.00`
  * Hồ sơ E: `total_purchases` = `12`, `customer_lifetime_value` = `3000000.00` (Sẽ là Bronze nếu CLV không đủ cho Gold/Silver)

**Unit Test (Python):**

```python
import unittest

def determine_loyalty_tier(total_purchases, clv):
    """
    Xác định hạng khách hàng thân thiết dựa trên tổng số lần mua và CLV.
    """
    total_purchases = total_purchases or 0
    clv = clv or 0.0

    # Điều chỉnh ngưỡng cho phù hợp hơn
    if total_purchases >= 20 and clv >= 10000000:
        return 'Platinum'
    elif total_purchases >= 10 and clv >= 5000000: # Ngưỡng CLV cho Gold
        return 'Gold'
    elif total_purchases >= 5 and clv >= 1000000:  # Ngưỡng CLV cho Silver
        return 'Silver'
    else:
        return 'Bronze'

class TestLoyaltyTier(unittest.TestCase):
    def test_platinum_tier(self):
        self.assertEqual(determine_loyalty_tier(total_purchases=25, clv=12000000.00), 'Platinum')
        self.assertEqual(determine_loyalty_tier(total_purchases=20, clv=10000000.00), 'Platinum')

    def test_gold_tier(self):
        self.assertEqual(determine_loyalty_tier(total_purchases=15, clv=8000000.00), 'Gold')
        self.assertEqual(determine_loyalty_tier(total_purchases=10, clv=5000000.00), 'Gold')
        # Trường hợp total_purchases đủ nhưng CLV không đủ cho Platinum
        self.assertEqual(determine_loyalty_tier(total_purchases=22, clv=6000000.00), 'Gold')


    def test_silver_tier(self):
        self.assertEqual(determine_loyalty_tier(total_purchases=8, clv=3000000.00), 'Silver')
        self.assertEqual(determine_loyalty_tier(total_purchases=5, clv=1000000.00), 'Silver')
        # Trường hợp total_purchases đủ cho Gold nhưng CLV chỉ đủ cho Silver
        self.assertEqual(determine_loyalty_tier(total_purchases=12, clv=3000000.00), 'Silver')


    def test_bronze_tier(self):
        self.assertEqual(determine_loyalty_tier(total_purchases=3, clv=500000.00), 'Bronze')
        self.assertEqual(determine_loyalty_tier(total_purchases=6, clv=500000.00), 'Bronze') # CLV không đủ cho Silver
        self.assertEqual(determine_loyalty_tier(total_purchases=1, clv=10000.00), 'Bronze')
        self.assertEqual(determine_loyalty_tier(total_purchases=0, clv=0), 'Bronze')
        self.assertEqual(determine_loyalty_tier(None, None), 'Bronze')


# Để chạy unit test:
# if __name__ == '__main__':
#     unittest.main(argv=['first-arg-is-ignored'], exit=False)
```

**Trường hợp sử dụng:**

  * **Quyền lợi khách hàng thân thiết:** Cung cấp các quyền lợi, giảm giá, quà tặng, hoặc dịch vụ đặc biệt cho từng hạng khách hàng.
  * **Marketing theo hạng:** Gửi các thông điệp và ưu đãi được cá nhân hóa cho từng hạng khách hàng. Ví dụ, khách hàng Bạch Kim có thể nhận được lời mời tham gia sự kiện độc quyền.

-----

## 7\. `next_best_actions` (JSONB - Đối tượng JSON)

**Tiếng Việt:** Hành Động Đề Xuất Tiếp Theo Tốt Nhất

**Mô tả:** Các hành động được cá nhân hóa được đề xuất dựa trên tín hiệu từ hồ sơ khách hàng và các mô hình ML. Đây có thể là một sản phẩm nên giới thiệu, một chiến dịch nên đưa họ vào, hoặc một lời kêu gọi hành động (CTA) cụ thể.

**Giá trị mẫu:**

```json
{
  "campaign": "luxury_summer_deals", // Chiến dịch: "Ưu đãi hè sang trọng"
  "product_recommendation": ["P123", "P456"], // Gợi ý sản phẩm: mã P123, P456
  "cta": "buy_now" // Lời kêu gọi hành động: "Mua ngay"
}
```

**Giải thích chi tiết hơn:**
Đây là một trường rất mạnh mẽ, cho phép CDP không chỉ tổng hợp dữ liệu mà còn đưa ra các gợi ý hành động cụ thể để tối ưu hóa tương tác với khách hàng. Các đề xuất này có thể thay đổi linh hoạt dựa trên hành vi mới nhất của khách hàng.

**Được tạo ra bởi:**

  * **Hệ thống quy tắc (Rules engine):** Dựa trên các quy tắc định sẵn. Ví dụ: "NẾU khách hàng xem sản phẩm X NHƯNG chưa mua TRONG 24 giờ VÀ là thành viên Vàng THÌ đề xuất mã giảm giá 10% cho sản phẩm X".
  * **Mô hình ML (ví dụ: hệ thống gợi ý - recommender systems):** Dự đoán sản phẩm, dịch vụ hoặc nội dung mà khách hàng có khả năng quan tâm nhất dựa trên hành vi của họ và của những người dùng tương tự.
  * **Trình kích hoạt sự kiện (Event triggers) + Bối cảnh chân dung (Persona context):** Một sự kiện cụ thể (ví dụ: bỏ giỏ hàng) kết hợp với thông tin về chân dung khách hàng (ví dụ: người mua sắm nhạy cảm về giá) có thể kích hoạt một hành động đề xuất cụ thể (ví dụ: gửi email nhắc nhở kèm mã giảm giá).

**Dữ liệu mẫu (đầu vào để tạo `next_best_actions`):**

  * `master_profile_id`: `uuid_example_101`
  * `last_viewed_product_ids`: [`P789`, `P123`]
  * `cart_abandoned`: `true`
  * `cart_items`: [`P789`]
  * `loyalty_tier`: `'Silver'`
  * `interests`: [`'du lịch biển'`, `'ẩm thực địa phương'`]
  * `current_campaign_engagement`: `{ "summer_promo": "clicked_ad" }`

**Logic tạo `next_best_actions` (ví dụ bằng Python giả lập):**

```python
def generate_next_best_actions(profile_data, product_catalog, active_campaigns):
    """
    Tạo hành động đề xuất dựa trên dữ liệu hồ sơ, danh mục sản phẩm và các chiến dịch đang hoạt động.
    Đây là một ví dụ rất đơn giản.
    """
    actions = {}
    recommendations = []

    # Logic 1: Gợi ý sản phẩm dựa trên sản phẩm vừa xem
    if profile_data.get("last_viewed_product_ids"):
        for pid in profile_data["last_viewed_product_ids"]:
            # Giả sử có logic tìm sản phẩm liên quan hoặc bổ sung
            if pid == "P123" and "P456" in product_catalog: # P456 là phụ kiện của P123
                if "P456" not in recommendations: recommendations.append("P456")
            if pid == "P789" and "P790_bundle" in product_catalog: # Gợi ý gói combo
                 if "P790_bundle" not in recommendations: recommendations.append("P790_bundle")


    # Logic 2: Xử lý giỏ hàng bị bỏ rơi
    if profile_data.get("cart_abandoned") and profile_data.get("cart_items"):
        item_in_cart = profile_data["cart_items"][0] # Lấy sản phẩm đầu tiên
        actions["campaign"] = f"cart_recovery_{item_in_cart}"
        actions["cta"] = "complete_purchase"
        if item_in_cart not in recommendations: # Thêm lại sản phẩm trong giỏ hàng vào gợi ý nếu chưa có
            recommendations.append(item_in_cart)

    # Logic 3: Đề xuất chiến dịch dựa trên sở thích và hạng thành viên
    elif "luxury_summer_deals" in active_campaigns and \
         profile_data.get("loyalty_tier") in ['Gold', 'Platinum'] and \
         any(interest in (profile_data.get("interests") or []) for interest in ['du lịch biển', 'nghỉ dưỡng cao cấp']):
        actions["campaign"] = "luxury_summer_deals"
        actions["cta"] = "explore_deals"
        # Có thể thêm sản phẩm nổi bật của chiến dịch này vào recommendations
        if "P_LUX01" in product_catalog and "P_LUX01" not in recommendations: recommendations.append("P_LUX01")
        if "P_LUX02" in product_catalog and "P_LUX02" not in recommendations: recommendations.append("P_LUX02")


    if recommendations:
        actions["product_recommendation"] = recommendations[:2] # Giới hạn 2 gợi ý

    # Mặc định nếu không có hành động cụ thể
    if not actions:
        actions["campaign"] = "general_awareness"
        actions["cta"] = "learn_more"
        if "P_BESTSELLER1" in product_catalog and "P_BESTSELLER1" not in recommendations: recommendations.append("P_BESTSELLER1")
        if recommendations: actions["product_recommendation"] = recommendations[:1]


    return actions

class TestNextBestActions(unittest.TestCase):
    def setUp(self):
        self.product_catalog = ["P123", "P456", "P789", "P790_bundle", "P_LUX01", "P_LUX02", "P_BESTSELLER1"]
        self.active_campaigns = ["cart_recovery_P789", "luxury_summer_deals", "general_awareness"]

    def test_cart_abandonment_case(self):
        profile = {
            "master_profile_id": "uuid_example_101",
            "last_viewed_product_ids": ["P789", "P123"],
            "cart_abandoned": True,
            "cart_items": ["P789"],
            "loyalty_tier": 'Silver',
            "interests": ['du lịch biển', 'ẩm thực địa phương']
        }
        expected_actions = {
            "campaign": "cart_recovery_P789",
            "cta": "complete_purchase",
            "product_recommendation": ["P456", "P789"] # P456 từ last_viewed, P789 từ cart_items
        }
        # Order of product_recommendation might vary based on internal logic, so we check content
        generated = generate_next_best_actions(profile, self.product_catalog, self.active_campaigns)
        self.assertEqual(generated.get("campaign"), expected_actions["campaign"])
        self.assertEqual(generated.get("cta"), expected_actions["cta"])
        self.assertCountEqual(generated.get("product_recommendation"), expected_actions["product_recommendation"])


    def test_luxury_campaign_match(self):
        profile = {
            "master_profile_id": "uuid_example_102",
            "loyalty_tier": 'Gold',
            "interests": ['du lịch biển', 'nghỉ dưỡng cao cấp'],
            "last_viewed_product_ids": ["P001"] # Sản phẩm không liên quan
        }
        expected_actions = {
            "campaign": "luxury_summer_deals",
            "cta": "explore_deals",
            "product_recommendation": ["P_LUX01", "P_LUX02"]
        }
        generated = generate_next_best_actions(profile, self.product_catalog, self.active_campaigns)
        self.assertEqual(generated.get("campaign"), expected_actions["campaign"])
        self.assertEqual(generated.get("cta"), expected_actions["cta"])
        self.assertCountEqual(generated.get("product_recommendation"), expected_actions["product_recommendation"])

    def test_default_action(self):
        profile = {
            "master_profile_id": "uuid_example_103",
            "loyalty_tier": 'Bronze',
            "interests": ['đọc sách'],
        }
        expected_actions = {
            "campaign": "general_awareness",
            "cta": "learn_more",
            "product_recommendation": ["P_BESTSELLER1"]
        }
        generated = generate_next_best_actions(profile, self.product_catalog, self.active_campaigns)
        self.assertEqual(generated.get("campaign"), expected_actions["campaign"])
        self.assertEqual(generated.get("cta"), expected_actions["cta"])
        self.assertCountEqual(generated.get("product_recommendation"), expected_actions["product_recommendation"])


# Để chạy unit test:
# if __name__ == '__main__':
#     unittest.main(argv=['first-arg-is-ignored'], exit=False)

```

**Trường hợp sử dụng:**

  * **Điều phối chiến dịch đa kênh (Cross-channel campaign orchestration):** Đảm bảo rằng khách hàng nhận được thông điệp và đề xuất nhất quán trên tất cả các kênh (email, web, app, mạng xã hội).
  * **Cá nhân hóa website động (Dynamic website personalization):** Tự động thay đổi nội dung, banner, gợi ý sản phẩm trên website cho từng khách hàng dựa trên `next_best_actions` của họ.
  * **Hỗ trợ nhân viên bán hàng/CSKH:** Cung cấp gợi ý cho nhân viên về cách tương tác tốt nhất với khách hàng tại điểm bán hoặc khi hỗ trợ.
