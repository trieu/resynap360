# Customer 360 profile track for ID Resolution

# ✅ Key Updates:

* Need Redis initialization in `WebEventProcessor`.
* Use `_get_persona_profiles()` to query Redis with key pattern like `persona_profiles:{visitor_id}`.

# 🔧 Notes for Deployment:

* Make sure your Lambda has network access to Redis (VPC + subnet + security group).
* Set `REDIS_HOST` and `REDIS_PORT` via environment variables.
* Preload Redis with data like:

  ```bash
  SET persona_profiles:abc123 '["persona_a", "persona_b"]'
  ```