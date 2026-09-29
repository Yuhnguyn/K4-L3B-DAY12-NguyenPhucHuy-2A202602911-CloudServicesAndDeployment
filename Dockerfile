# ═══════════════════════════════════════════════════════════════════
# CP2 — Containerization (bản production-ready)
#
# Multi-stage: stage `builder` cài dependency (được phép nặng, sẽ bị vứt),
# stage `runtime` chỉ copy KẾT QUẢ sang → không mang theo compiler.
#
# Thứ tự layer: COPY requirements.txt → pip install → mới COPY source.
# Docker cache theo layer và hủy cache từ layer đầu tiên thay đổi trở đi,
# nên sửa 1 dòng code không phải cài lại toàn bộ thư viện.
#
# Build thử: docker build -t day12-agent:prod .
#            docker images day12-agent:prod
# ═══════════════════════════════════════════════════════════════════

# ── Stage 1: builder ────────────────────────────────────────────────
FROM python:3.11-slim AS builder

WORKDIR /app

# Đúng một dòng riêng cho requirements: layer này chỉ mất cache khi
# requirements.txt đổi, không phải khi code đổi.
COPY requirements.txt .
RUN pip install --no-cache-dir --prefix=/install -r requirements.txt


# ── Stage 2: runtime ────────────────────────────────────────────────
FROM python:3.11-slim AS runtime

# PYTHONUNBUFFERED: log ra ngay, không bị đệm trong buffer của container
# PYTHONDONTWRITEBYTECODE: không sinh __pycache__ trong image
ENV PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1 \
    PORT=8000

WORKDIR /app

# Chỉ lấy thư viện đã cài, không lấy compiler/apt cache của stage builder
COPY --from=builder /install /usr/local

# User thường: thoát được khỏi app Python cũng không thành root trên host
RUN useradd --create-home --uid 10001 appuser

COPY --chown=appuser:appuser app ./app
COPY --chown=appuser:appuser utils ./utils

USER appuser

EXPOSE 8000

# dùng python thay vì curl: image slim không có curl
HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
    CMD python -c "import os,urllib.request; urllib.request.urlopen('http://127.0.0.1:'+os.environ.get('PORT','8000')+'/health').read()" || exit 1

# $PORT do platform gán (Railway/Render/Cloud Run). 0.0.0.0 để gọi được
# từ ngoài container — bind 127.0.0.1 thì bên ngoài không vào được.
#
# `exec` là BẮT BUỘC: không có nó, PID 1 là `sh`, mà sh không forward
# SIGTERM cho tiến trình con → uvicorn không bao giờ nhận được tín hiệu
# tắt → mọi request đang xử lý dở bị cắt giữa chừng mỗi lần deploy.
# `exec` thay thế sh bằng uvicorn, để uvicorn thành PID 1 và nhận SIGTERM.
CMD ["sh", "-c", "exec uvicorn app.main:app --host 0.0.0.0 --port ${PORT:-8000}"]
