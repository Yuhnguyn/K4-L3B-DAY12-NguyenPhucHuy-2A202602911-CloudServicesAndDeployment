# Thông Tin Deploy — Checkpoint 5

> `pytest tests/test_cp5.py` đọc file này để tìm địa chỉ service và gọi thử.
>
> **Chỉ ghi TÊN biến môi trường, tuyệt đối không dán giá trị API key vào đây.**
> Repo này công khai — dán khóa vào là mất khóa.

## Thông Tin Học Viên

| Mục | Nội dung |
|-----|----------|
| Họ và tên | Nguyễn Phúc Huy |
| Mã học viên | 2A202602911 |
| Repo | https://github.com/Yuhnguyn/K4-L3B-DAY12-NguyenPhucHuy-2A202602911-CloudServicesAndDeployment |

## Service

| Mục | Nội dung |
|-----|----------|
| Public URL | https://day12-agent-5wrs.onrender.com |
| Platform | Render — deploy bằng Blueprint từ `render.yaml` trong repo |
| Ngày deploy | 2026-09-29 |
| Loại service | Web Service, runtime Docker (build từ `Dockerfile` multi-stage) |
| Health check path | `/health` |

Bản deploy gồm **2 service** trong cùng một Blueprint:

| Service | Loại | Plan | Vai trò |
|---------|------|------|---------|
| `day12-agent` | Web Service (Docker) | Free | Chạy app FastAPI |
| `day12-redis` | Render Key Value | Free | Redis-compatible, lưu history / rate limit / cost |

## Biến Môi Trường Đã Set Trên Cloud

Ghi tên biến và **nguồn giá trị**, không ghi giá trị:

| Biến | Đã set | Nguồn giá trị |
|------|--------|---------------|
| `PORT` | ✅ | Render tự gán; app đọc `${PORT:-8000}` trong `Dockerfile` — không hardcode |
| `AGENT_API_KEY` | ✅ | Khai báo `sync: false` trong `render.yaml` → Render hỏi lúc tạo Blueprint. **Giá trị không nằm trong repo** |
| `REDIS_URL` | ✅ | Nối tự động từ `day12-redis` qua `fromService` + `property: connectionString` (internal URL `redis://red-...:6379`, không qua Internet) |
| `RATE_LIMIT_PER_MINUTE` | ✅ | `10` — khai báo trong `render.yaml` |
| `MONTHLY_BUDGET_USD` | ✅ | `10.0` — khai báo trong `render.yaml` |
| `LOG_LEVEL` | ✅ | `INFO` — khai báo trong `render.yaml` |

## Lệnh Kiểm Tra

```bash
URL=https://day12-agent-5wrs.onrender.com

# 1. Liveness — mong đợi 200 {"status":"ok"}
curl -i $URL/health

# 2. Readiness — mong đợi 200 {"status":"ready"} (đã nối được Redis)
curl -i $URL/ready

# 3. Không có API key — mong đợi 401
curl -i -X POST $URL/ask \
  -H "Content-Type: application/json" \
  -d '{"question":"Hello"}'

# 4. Có API key — mong đợi 200 kèm câu trả lời
curl -i -X POST $URL/ask \
  -H "Content-Type: application/json" \
  -H "X-API-Key: $AGENT_API_KEY" \
  -H "X-User-Id: sv-test" \
  -d '{"question":"Deploy là gì?"}'

# 5. Rate limit — gọi 15 lần, những lần cuối phải trả 429
for i in $(seq 1 15); do
  curl -s -o /dev/null -w "%{http_code} " -X POST $URL/ask \
    -H "Content-Type: application/json" \
    -H "X-API-Key: $AGENT_API_KEY" \
    -H "X-User-Id: sv-test" \
    -d '{"question":"test"}'
done; echo
```

## Kết Quả Chạy Thật

```text
$ curl -i https://day12-agent-5wrs.onrender.com/health
HTTP/2 200
x-render-origin-server: uvicorn
{"status":"ok","service":"day12-agent","version":"1.0.0"}

$ curl -i https://day12-agent-5wrs.onrender.com/ready
HTTP/2 200
{"status":"ready","redis":true}

$ curl -i -X POST https://day12-agent-5wrs.onrender.com/ask -H "Content-Type: application/json" -d '{"question":"Hello"}'
HTTP/2 401
{"detail":"invalid or missing API key"}

$ curl -i -X POST https://day12-agent-5wrs.onrender.com/ask \
    -H "Content-Type: application/json" -H "X-API-Key: $AGENT_API_KEY" -H "X-User-Id: cp5-test" \
    -d '{"question":"Deploy là gì?"}'
HTTP/2 200
{"answer":"Câu hỏi hay. Deploy là gì thường được giải quyết bằng cách chuẩn hóa môi trường chạy: cùng một image chạy giống nhau ở laptop và trên cloud.","user_id":"cp5-test","history_length":0,"cost_usd":2.145e-05,"tokens":{"in":3,"out":35}}

$ # Gọi 15 lần liên tiếp, hạn mức 10 request/phút/user
200 200 200 200 200 200 200 200 200 200 429 429 429 429 429

$ # Lượt thứ hai với cùng user → history được đọc lại từ Redis trên cloud
$ curl -s -X POST .../ask -H "X-User-Id: sv-cp5-doc" -d '{"question":"Chi phí?"}'
{"answer":"...","user_id":"sv-cp5-doc","history_length":0,"cost_usd":2.01e-05,"tokens":{"in":2,"out":33}}
```

## Ảnh Chụp Màn Hình

Đặt trong thư mục `screenshots/`:

- `screenshots/dashboard.png` — trang quản lý service trên Render (Blueprint `day12-agent` + `day12-redis`)
- `screenshots/health.png` — kết quả gọi `/health` từ trình duyệt

## Ghi Chú Về Plan Free Của Render

Hai giới hạn của plan Free, ghi lại để người chấm biết đây là giới hạn của
platform chứ không phải lỗi của app:

1. **Web service Free ngủ sau 15 phút** không có traffic. Request đầu tiên sau
   đó mất ~30–60 giây để đánh thức (cold start). Các request sau bình thường.
2. **Key Value Free không persist** — Render ghi rõ plan free "data persistence
   is not available". Mọi restart/maintenance của Render sẽ xoá history,
   cost và rate limit. Với bài lab thì chấp nhận được; production thì phải
   trả phí để có persistence, hoặc thay bằng Redis có persistence.
3. **App vẫn stateless đúng thiết kế**: state nằm ở Redis, không nằm trong
   process. Restart container không làm mất state (chỉ mất khi chính Redis
   của plan free bị Render restart).

## Lịch Sử Deploy

- Lần đầu tạo Web Service thủ công → `/ready` trả **503 `{"status":"not ready","redis":false}"`**
  vì chưa set `REDIS_URL`, app rơi về giá trị mặc định `redis://localhost:6379/0`
  và trong container thì `localhost` là chính container đó. `/health` vẫn 200
  vì liveness cố ý **không** kiểm tra dependency — đúng như thiết kế CP1/CP4.
- Sau đó deploy lại bằng Blueprint: Render tạo luôn `day12-redis` và nối
  `REDIS_URL` tự động qua `fromService` → `/ready` trả 200.

## Phương Án Dự Phòng

Không dùng. Bài đã deploy thật lên Render và `LOCAL_FALLBACK=false` trong `.env`.
