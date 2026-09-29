# Phiếu Phản Ánh — K4 Level 3B, Ngày 12

> **Bài làm cá nhân.** Trả lời bằng lời của chính bạn, dựa trên những gì bạn
> quan sát được khi chạy code — không sao chép đáp án của người khác.
>
> Cách trả lời: điền câu trả lời của bạn vào sau dấu `>` ở từng câu hỏi.
> `grade.py` đếm số câu đã trả lời (15 điểm cho 10 câu).
>
> Họ và tên: Nguyễn Phúc Huy  Mã học viên: 2A202602911

---

### Câu 1 — Fail fast (CP1)

Trong `Settings`, `agent_api_key` không có giá trị mặc định nên app chết ngay
khi khởi động nếu thiếu biến môi trường. Hãy mô tả một tình huống cụ thể mà
việc "chết sớm" này cứu bạn, so với việc để mặc định `"changeme"`.

> Tôi deploy lên Render và quên set `AGENT_API_KEY` trong dashboard (nó khai báo
> `sync: false` nên Render chỉ hỏi đúng một lần lúc tạo Blueprint — bỏ qua lần
> đó là mất). Với `agent_api_key: str` không mặc định, pydantic-settings ném
> `ValidationError: agent_api_key Field required` **ngay lúc process khởi động**,
> trước khi uvicorn kịp nhận request nào. Render báo deploy failed và tôi thấy
> nguyên nhân trong log chỉ sau vài giây, lúc tôi vẫn đang ngồi trước màn hình.
>
> Nếu để mặc định `"changeme"` thì chuỗi sự kiện sẽ khác hẳn: app khởi động
> thành công, health check xanh, service nhận traffic bình thường. Nhưng URL là
> công khai, bot quét Internet tìm ra endpoint mới trong vài giờ, và chúng gọi
> `/ask` bằng khóa `"changeme"` — hợp lệ. Hóa đơn LLM do tôi trả, và tôi chỉ
> biết khi nhìn dashboard chi phí, lúc đó đã muộn. Điểm mấu chốt: **lỗi cấu hình
> phải nổ ở thời điểm tôi còn đang nhìn, không phải ở thời điểm tôi đã đi ngủ.**

---

### Câu 2 — Log cho máy đọc (CP1)

Chạy service và gọi `/ask` vài lần. Dán một dòng log JSON bạn thu được, rồi
nêu **hai** việc bạn làm được với dòng log đó mà `print("đã trả lời xong")`
không làm được.

> Dòng log thật lấy từ `docker compose logs agent` sau khi gọi `/ask`:
>
> ```json
> {"event": "ask_completed", "level": "info", "timestamp": "2026-09-29T04:55:32.420976+00:00", "user_id": "sv-log", "tokens_in": 4, "tokens_out": 38, "cost_usd": 2.34e-05}
> ```
>
> **Việc 1 — tổng hợp số liệu theo trường, không cần đọc bằng mắt.** Vì mỗi
> dòng là một JSON object, tôi lọc và tính được:
>
> ```bash
> docker compose logs agent | grep -o '{"event": "ask_completed".*}' \
>   | jq -r '.cost_usd' | paste -sd+ | bc
> ```
>
> ra tổng tiền đã tiêu; đổi `.user_id` là biết **user nào tiêu nhiều nhất**;
> lọc `.level == "error"` trong 5 phút gần nhất là ra tỉ lệ lỗi. Với
> `print("đã trả lời xong")` thì chuỗi đó không có trường nào cả — muốn thống kê
> phải viết regex bắt chữ, và mọi thay đổi câu chữ trong log sẽ làm hỏng script.
>
> **Việc 2 — đặt cảnh báo tự động trên cloud.** Railway/Render/Datadog/Loki đều
> parse log theo JSON. Tôi đặt được alert kiểu *"báo tôi khi có dòng
> `level == "error"`"* hoặc *"báo khi `cost_usd` một ngày vượt 1 USD"*. Với log
> dạng văn xuôi, hệ thống không có khóa nào để so sánh nên không thể tạo cảnh
> báo — tôi chỉ biết có sự cố khi người dùng phàn nàn.
>
> Thêm một chi tiết tôi phải xử lý: `json.dumps(..., ensure_ascii=False)`. Nếu
> quên, tiếng Việt trong log bị escape thành `\u1ea1` — máy vẫn đọc được nhưng
> người đọc log thì không.

---

### Câu 3 — Kích thước image (CP2)

Build cả hai phiên bản và ghi lại số đo thật:

```bash
docker build -f <Dockerfile-1-stage> -t agent:single .
docker build -t agent:multi .
docker images | grep agent
```

| Bản | Dung lượng |
|-----|-----------|
| 1 stage (bản đầu) | **1.73 GB** |
| Multi-stage | **271 MB** |

Giải thích: phần dung lượng chênh lệch đó là những gì?

> Chênh lệch **1.73 GB − 271 MB ≈ 1.46 GB**, gấp hơn 6 lần. Ba nguồn:
>
> **1. Base image.** Bản 1-stage dùng `python:3.11` (Debian đầy đủ, có sẵn
> gcc/make, header, apt cache, đủ thứ công cụ để build). Bản của tôi dùng
> `python:3.11-slim` cho **cả hai stage** — slim chỉ có Python runtime và thư
> viện tối thiểu. Đây là phần chênh lệch lớn nhất.
>
> **2. Thư viện + build artifact.** Ở bản 1-stage, `pip install` cài thẳng vào
> site-packages của image và để lại mọi thứ nó cần để build wheel. Ở bản
> multi-stage, việc cài đặt xảy ra trong stage `builder` và tôi chỉ
> `COPY --from=builder /install /usr/local` — tức là chỉ mang **kết quả đã cài**
> sang. Stage `builder` (với compiler, apt list, cache) bị vứt đi hoàn toàn,
> không nằm trong image cuối.
>
> **3. Cache và rác của quá trình cài đặt.** Bản 1-stage dùng
> `RUN pip install -r requirements.txt` không có `--no-cache-dir`, nên toàn bộ
> pip cache nằm lại trong layer. Bản multi-stage dùng
> `pip install --no-cache-dir --prefix=/install` nên không giữ cache.
>
> Kiểm tra lại được bằng: `docker images --format "{{.Repository}}:{{.Tag}} {{.Size}}" | grep day12-agent`.

---

### Câu 4 — Thứ tự lệnh trong Dockerfile (CP2)

Sửa một ký tự trong `app/main.py` rồi build lại. Với Dockerfile của bạn, những
layer nào được dùng lại từ cache, layer nào phải chạy lại? Nếu bạn đặt
`COPY . .` lên trước `RUN pip install` thì kết quả khác thế nào?

> Tôi thêm một dòng comment vào `app/main.py` rồi build lại. Log thật:
>
> ```
> #6  [builder 2/4] WORKDIR /app                                    CACHED
> #7  [builder 3/4] COPY requirements.txt .                        CACHED
> #8  [builder 4/4] RUN pip install --no-cache-dir --prefix=/install -r requirements.txt   CACHED
> #9  [runtime 3/6] COPY --from=builder /install /usr/local         CACHED
> #10 [runtime 4/6] RUN useradd --create-home --uid 10001 appuser   CACHED
> #11 [runtime 5/6] COPY --chown=appuser:appuser app ./app          DONE 0.3s
> #12 [runtime 6/6] COPY --chown=appuser:appuser utils ./utils      DONE 0.3s
> ```
>
> **Dùng lại cache:** 5 layer `#6`–`#10` — `WORKDIR`, `COPY requirements.txt`,
> `pip install`, `COPY --from=builder /install`, `useradd`. Lý do: Docker cache
> theo **nội dung** của từng layer. `requirements.txt` và `Dockerfile` không đổi
> nên layer `#7` giữ nguyên checksum, và mọi layer sau nó chỉ phụ thuộc vào layer
> trước đó → vẫn khớp cache. Việc cài thư viện không chạy lại.
>
> **Chạy lại:** `#11` và `#12` — đúng hai layer `COPY` chứa source code. Toàn bộ
> lần build lại mất **1.6 giây**, trong khi cài lại toàn bộ thư viện mất vài phút.
>
> **Nếu đặt `COPY . .` trước `RUN pip install`:** layer `COPY . .` sẽ đổi
> checksum mỗi khi tôi sửa **bất kỳ** file nào trong build context — kể cả một
> dấu phẩy trong code. Docker hủy cache từ layer đầu tiên thay đổi trở đi, nên
> nó cũng hủy luôn cache của `RUN pip install` ngay sau đó. Kết quả: mỗi lần sửa
> một ký tự là cài lại toàn bộ thư viện. Với vòng lặp sửa–build–sửa của tôi, đó
> là khác biệt giữa 2 giây và vài phút cho mỗi lần. Đây là lý do thứ tự layer
> trong Dockerfile là chuyện tốc độ, không phải chuyện thẩm mỹ.

---

### Câu 5 — Vì sao không chạy bằng root (CP2)

Container mặc định chạy bằng root. Mô tả chuỗi sự kiện dẫn từ "một lỗ hổng
trong code Python của bạn" tới "kẻ tấn công có quyền cao trên máy host", và
lệnh `USER` cắt đứt chuỗi đó ở chỗ nào.

> **Chuỗi sự kiện khi container chạy root (uid 0):**
>
> 1. Code Python của tôi có lỗ hổng — ví dụ một dependency bị RCE, hoặc tôi lỡ
>    dùng `eval()`/`pickle.loads()` trên dữ liệu người dùng gửi vào.
> 2. Kẻ tấn công khai thác qua endpoint công khai và **chạy được lệnh tuỳ ý
>    trong container**. Lệnh đó chạy dưới quyền của PID 1 — mà PID 1 là root.
> 3. Với quyền root **trong container**, họ đọc được mọi file, đọc biến môi
>    trường (trong đó có secret), cài thêm công cụ, và quan trọng nhất: họ có
>    `CAP_SYS_ADMIN`-ish capabilities cùng quyền ghi lên các mount.
> 4. Bước leo thang ra host: nếu container mount một thư mục từ host (volume,
>    docker socket, hoặc hostPath) thì root trong container sửa được file của
>    host. Nếu không có mount, họ vẫn có bề mặt tấn công lớn hơn nhiều: lỗ hổng
>    kernel, lỗ hổng `runc`/container runtime, hay lỗi cấu hình `--privileged`.
>    Root trong container là điều kiện gần như bắt buộc cho các kỹ thuật
>    container escape.
> 5. Kết quả cuối: quyền cao trên máy host, và từ đó sang các máy khác trong
>    cùng mạng nội bộ.
>
> **`USER` cắt chuỗi ở bước 2→3.** Trong Dockerfile tôi có:
>
> ```dockerfile
> RUN useradd --create-home --uid 10001 appuser
> USER appuser
> ```
>
> Kiểm chứng thật trên container đang chạy:
>
> ```
> $ docker compose exec agent id
> uid=10001(appuser) gid=10001(appuser) groups=10001(appuser)
> ```
>
> Sau khi bị RCE, kẻ tấn công chỉ có **uid 10001**. Họ không đọc được file của
> root, không `apt install` được, không mount được, không sửa được file hệ thống.
> Các kỹ thuật container escape đòi quyền cao đều thất bại ngay từ bước đầu.
> Lỗ hổng vẫn là lỗ hổng — nhưng nó bị **giới hạn trong một process quyền thấp**
> thay vì mở toang cả máy host. Đây là nguyên tắc least privilege, và `USER` là
> cách rẻ nhất để áp nó cho container.

---

### Câu 6 — Cửa sổ trượt (CP3)

Rate limit của bạn dùng sliding window 60 giây. Nếu thay bằng cách đếm theo
phút đồng hồ (reset lúc giây 00), một người dùng có thể gửi tối đa bao nhiêu
request trong 2 giây liên tiếp khi hạn mức là 10/phút? Giải thích cách đạt được
con số đó.

> Tối đa **20 request trong 2 giây**.
>
> Cách đạt được: bộ đếm theo phút đồng hồ bị reset về 0 vào lúc giây `00` của
> mỗi phút, nên nó chỉ quan tâm request nằm trong *phút dương lịch*, không quan
> tâm khoảng cách giữa các request.
>
> ```
> 10:00:59  →  gửi 10 request   (phút 10:00, bộ đếm: 10/10 — vừa đủ hạn mức)
> 10:01:00  →  bộ đếm reset về 0
> 10:01:01  →  gửi 10 request   (phút 10:01, bộ đếm: 10/10 — lại vừa đủ hạn mức)
> ```
>
> Tổng: 20 request rơi vào khoảng **2 giây** (10:00:59 → 10:01:01), và cả hai lô
> đều "hợp lệ" theo luật đếm-theo-phút. Kẻ tấn công chỉ cần canh đồng hồ, không
> cần làm gì thông minh cả.
>
> Sliding window của tôi không có kẽ hở đó vì nó không reset theo mốc thời gian
> nào. Nó lưu timestamp từng request vào ZSET rồi ở mỗi lần kiểm tra chạy
> `zremrangebyscore(key, 0, now - 60)` — vứt đi những request **cũ hơn 60 giây
> tính từ chính thời điểm hiện tại**, rồi `zcard` đếm phần còn lại. Ở thời điểm
> 10:01:01, 10 request lúc 10:00:59 vẫn còn nằm trong cửa sổ (mới 2 giây), nên
> request thứ 11 bị chặn bằng 429. Muốn vượt, người dùng phải chờ thật sự cho
> các request cũ trượt ra khỏi cửa sổ.
>
> Đánh đổi: sliding window tốn bộ nhớ hơn (mỗi request một entry trong ZSET thay
> vì một biến đếm), nhưng đúng hơn. Với hạn mức theo user thì chi phí đó không
> đáng kể.

---

### Câu 7 — Rate limit và cost guard (CP3)

Hai cơ chế này khác nhau ở điểm nào? Cho một tình huống mà rate limit cho qua
nhưng cost guard phải chặn, và một tình huống ngược lại.

> Chúng đo hai đại lượng khác nhau:
>
> | | Rate limit | Cost guard |
> |---|---|---|
> | Giới hạn cái gì | **Số lượng** request trong 60 giây | **Số tiền** trong một tháng |
> | Đơn vị | request/phút/user | USD/tháng/user |
> | Mã lỗi | 429 Too Many Requests | 402 Payment Required |
> | Redis key | `ratelimit:<user>` (ZSET, TTL 60s) | `cost:<user>:<YYYY-MM>` (float, TTL 40 ngày) |
>
> Chúng **không thay thế nhau** vì một request có thể rất rẻ hoặc rất đắt.
>
> **Rate limit cho qua, cost guard chặn:** một user gửi đúng 10 request/phút —
> hoàn toàn hợp lệ về số lượng. Nhưng nếu mỗi request đẩy vào một prompt khổng
> lồ (50.000 token input) thì mỗi request tốn cỡ 0,5 USD. Chưa hết một phút thứ
> hai, tổng chi tiêu đã vượt ngân sách 10 USD/tháng → cost guard trả **402** dù
> rate limiter vẫn thấy "user này gọi rất lịch sự". Nếu chỉ có rate limit, ngân
> sách tháng bay trong vài phút.
>
> **Cost guard cho qua, rate limit chặn:** user còn nguyên ngân sách 10 USD
> (chưa tiêu gì) nhưng bắn 200 request trong 10 giây. Mỗi câu trả lời của mock
> LLM chỉ tốn ~2,3e-05 USD (đo được ở Câu 2), nên 200 request mới hết ~0,005 USD
> — cost guard hoàn toàn thoải mái. Nhưng rate limiter chặn ở request thứ 11
> bằng **429**, vì vấn đề ở đây không phải tiền mà là tài nguyên và khả năng
> phục vụ của service.
>
> Bằng chứng đo trên bản deploy thật: gọi 15 lần liên tiếp cùng một `X-User-Id`
> với hạn mức 10/phút cho kết quả `200 ×10` rồi `429 ×5`, trong khi `cost_usd`
> mỗi request chỉ ~2,1e-05 USD — tức là **rate limit đã chặn trước khi tiền kịp
> thành vấn đề**. Đó chính là lý do phải có cả hai lớp.

---

### Câu 8 — /health khác /ready (CP4)

Nếu gộp hai endpoint làm một và cho nó kiểm tra Redis, chuyện gì xảy ra với cụm
3 container khi Redis mất kết nối 30 giây? Trả lời theo đúng thứ tự sự kiện.

> Thứ tự sự kiện, với cụm 3 container sau load balancer, endpoint gộp gọi
> `store.ping()`:
>
> 1. **t = 0s — Redis mất kết nối.** Cả 3 container đều gọi `ping()` và nhận
>    timeout/connection refused.
> 2. **t ≈ 0–5s — cả 3 container trả 503** cho endpoint gộp.
> 3. **t ≈ 5–35s — orchestrator đọc 503 này là liveness failure.** Vì endpoint
>    gộp đóng vai trò liveness, phản ứng đúng theo hợp đồng là **restart
>    container**. Cả 3 bị restart **cùng lúc** (chúng cùng thấy Redis chết ở cùng
>    thời điểm).
> 4. **Trong lúc restart — không còn container nào phục vụ.** Load balancer
>    không có backend nào healthy, nên **mọi** request của người dùng nhận
>    502/503 — kể cả những request không hề cần Redis (như `GET /health` của
>    chính platform, hay các endpoint chỉ đọc cấu hình). Sự cố Redis 30 giây vừa
>    biến thành sự cố toàn hệ thống.
> 5. **t = 30s — Redis sống lại.** Nhưng 3 container vẫn đang trong quá trình
>    khởi động lại (kéo image, chạy `lifespan`, kết nối lại Redis). Downtime thực
>    tế dài hơn 30 giây — có thể 1–2 phút.
> 6. **Nếu Redis chết lâu hơn thời gian khởi động:** container restart xong, gọi
>    `ping()` lại vẫn fail, lại trả 503, lại bị restart. Vòng lặp
>    **CrashLoopBackOff** — hệ thống tự đập mình liên tục và không bao giờ hồi
>    phục, dù bản thân app không hề có lỗi gì.
>
> **Thiết kế đúng mà tôi đã làm tách hai câu hỏi ra:**
>
> | | `/health` (liveness) | `/ready` (readiness) |
> |---|---|---|
> | Câu hỏi | Process còn sống không? | Nhận traffic được chưa? |
> | Kiểm tra Redis | **Không** | **Có** (`store.ping()`) |
> | Trả 503 → | Orchestrator **restart** container | LB **ngừng đẩy** request vào, **không** restart |
>
> Với thiết kế tách đúng, cùng sự cố Redis 30 giây diễn ra thế này: `/health`
> vẫn 200 (process vẫn sống, không ai restart), `/ready` trả 503 nên load
> balancer chỉ tạm rút instance ra khỏi vòng xoay, và khi Redis trở lại thì
> `/ready` tự xanh mà **không cần restart gì cả**. Cùng một sự cố, một bên là
> downtime toàn hệ thống, một bên là vài giây suy giảm. Đây chính là điều tôi
> kiểm chứng được trên bản deploy: `/health` 200 trong khi `/ready` từng trả
> 503 `{"status":"not ready","redis":false}` — hai endpoint thật sự độc lập.

---

### Câu 9 — Stateless (CP4)

Chạy `docker compose up --scale agent=3` rồi gọi `/ask` nhiều lần với cùng một
`X-User-Id`. Quan sát `history_length` trong response. Nếu lịch sử được lưu
trong một dict Python thay vì Redis, bạn sẽ thấy con số đó thay đổi thế nào?

> Lưu ý trước: `docker-compose.yml` publish cố định cổng host `8000`, mà 3
> container không thể cùng chiếm một cổng host — lệnh `--scale` sẽ báo
> "port is already allocated". Nên tôi thêm `docker-compose.scale.yml`: bỏ
> publish cổng của `agent` (chỉ nginx lộ ra ngoài) rồi chạy
>
> ```bash
> docker compose -f docker-compose.yml -f docker-compose.scale.yml up -d --scale agent=3
> curl http://localhost:8080/health   # qua nginx
> ```
>
> Trạng thái thật: `agent Up (healthy) ×3`, `nginx Up`, `redis Up (healthy)`.
> Gọi 5 lần liên tiếp qua nginx với cùng `X-User-Id: sv-scale`:
>
> ```
> câu 1 → history_length = 0
> câu 2 → history_length = 2
> câu 3 → history_length = 4
> câu 4 → history_length = 6
> câu 5 → history_length = 8
> ```
>
> Và log cho thấy request **thật sự rơi vào cả 3 container**:
>
> ```
> day12scale-agent-1: 1 request
> day12scale-agent-2: 2 request
> day12scale-agent-3: 2 request
> ```
>
> Tức là container B đọc được lịch sử do container A ghi. Vì `append` ghi vào
> Redis List `history:<user_id>` — nơi mọi instance cùng nhìn thấy — nên con số
> tăng đều 2 đơn vị mỗi lượt (1 user + 1 assistant) bất kể request rơi vào
> container nào.
>
> **Nếu lịch sử nằm trong một dict Python (`conversation_history = {}`):** mỗi
> container có RAM riêng, và dict đó chỉ chứa những gì **chính container đó** đã
> ghi. Con số sẽ không tăng đều mà dao động theo round-robin của nginx. Ví dụ
> với 3 container A/B/C và user hỏi 5 câu liên tiếp:
>
> ```
> request 1 → A  (A chưa có gì)          history_length = 0
> request 2 → B  (B chưa có gì)          history_length = 0   ← đáng lẽ phải là 2
> request 3 → C  (C chưa có gì)          history_length = 0   ← đáng lẽ phải là 4
> request 4 → A  (A có 1 lượt = 2 msg)   history_length = 2
> request 5 → B  (B có 1 lượt = 2 msg)   history_length = 2
> ```
>
> Triệu chứng người dùng thấy là **agent "mất trí nhớ" ngẫu nhiên**: hỏi câu 2
> thì nó nhớ câu 1, hỏi câu 3 thì nó quên sạch. Tệ hơn nữa là mỗi lần platform
> restart container (deploy bản mới, vá lỗi, dời máy) thì dict reset về rỗng —
> lịch sử mất sạch. Và không có cách nào đoán trước, vì nó phụ thuộc vào việc
> request rơi vào container nào. Tôi còn kiểm chứng thêm một biến thể: restart
> container `agent` rồi hỏi tiếp cùng user, `history_length` vẫn là **6** —
> process mới hoàn toàn nhưng state vẫn còn, vì nó nằm ở Redis chứ không nằm
> trong process.

---

### Câu 10 — Deploy thật (CP5)

Ghi lại **một** lỗi bạn gặp khi deploy lên cloud (build fail, health check
timeout, sai REDIS_URL, app không đọc `$PORT`...): thông báo lỗi là gì, bạn
tìm ra nguyên nhân bằng cách nào, và sửa ra sao?

> **Lỗi: `/health` trả 200 nhưng `/ready` trả 503.**
>
> Lần deploy đầu tiên tôi tạo Web Service thủ công trên Render (chọn repo +
> Docker) và lấy được URL. Gọi thử:
>
> ```
> $ curl -i https://...onrender.com/health
> HTTP/2 200
> {"status":"ok","service":"day12-agent","version":"1.0.0"}
>
> $ curl -i https://...onrender.com/ready
> HTTP/2 503
> {"status":"not ready","redis":false}
> ```
>
> **Thông báo lỗi rất "im lặng":** không có stack trace, không có exception,
> chỉ một JSON `{"status":"not ready","redis":false}`. Đây là loại lỗi khó nhất
> vì service có vẻ vẫn chạy.
>
> **Cách tôi tìm ra nguyên nhân — suy luận từ hai endpoint:**
>
> 1. `/health` trả 200 chứng tỏ **build thành công**, container khởi động được,
>    uvicorn bind đúng cổng, và Cloudflare route được vào service. Nên tôi loại
>    ngay các nghi phạm: build fail, sai `$PORT`, firewall.
> 2. `redis: false` là giá trị do chính code tôi trả về khi
>    `store.ping()` fail. Vậy vấn đề nằm ở kết nối Redis, không phải ở app.
> 3. Mở lại `app/store.py` xem `get_redis_client()` lấy URL từ đâu:
>
>    ```python
>    url = url or get_settings().redis_url
>    ```
>
>    và `Settings.redis_url` có **giá trị mặc định** `redis://localhost:6379/0`.
> 4. Suy ra: biến `REDIS_URL` **chưa được set** trên Render, nên app rơi về giá
>    trị mặc định. Trong container, `localhost` là **chính container đó**, không
>    phải Redis → connection refused → `ping()` trả `False`.
>
> Chẩn đoán này khớp hoàn toàn với một chi tiết nữa: tôi tạo Web Service thủ
> công nên phần `fromService` nối Redis trong `render.yaml` **không được áp
> dụng** — chưa có service Redis nào tồn tại để nối vào.
>
> **Cách sửa:** deploy lại bằng **Blueprint** từ `render.yaml`. Render đọc file
> và tạo luôn cả hai service:
>
> - `day12-agent` (Web Service, Docker, Free)
> - `day12-redis` (Render Key Value, Free)
>
> và nối biến tự động:
>
> ```yaml
> - key: REDIS_URL
>   fromService:
>     name: day12-redis
>     type: keyvalue
>     property: connectionString
> ```
>
> `connectionString` trả về **internal URL** dạng `redis://red-xxxxxxxx:6379` —
> đi qua private network, không qua Internet. Sau khi deploy lại:
>
> ```
> $ curl -i https://day12-agent-5wrs.onrender.com/ready
> HTTP/2 200
> {"status":"ready","redis":true}
> ```
>
> **Bài học tôi rút ra:** (1) *liveness 200 không có nghĩa là service dùng được* —
> phải luôn kiểm tra readiness riêng, vì hai endpoint trả lời hai câu hỏi khác
> nhau; (2) giá trị mặc định "tiện lúc phát triển" chính là cái bẫy trên cloud —
> `localhost` đúng khi mọi thứ chạy trên một máy, và sai ngay khi có container;
> đây đúng là tinh thần 12-Factor: **config phải đến từ môi trường, không nằm
> trong code**; (3) với platform có cơ chế infrastructure-as-code (Blueprint,
> compose, Helm) thì nên dùng nó thay vì click tay — nối Redis thủ công dễ sót
> đúng một biến và lỗi lại rất im lặng.
