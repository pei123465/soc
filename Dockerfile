# syntax=docker/dockerfile:1

ARG PYTHON_VERSION=3.12

# ---- builder: Python依存とブラウザ本体を取得 ----
FROM python:${PYTHON_VERSION}-bookworm AS builder

ENV PIP_NO_CACHE_DIR=1 \
    PLAYWRIGHT_BROWSERS_PATH=/playwright \
    PYTHONPATH=/opt/python

WORKDIR /build

COPY requirements.txt .

# 依存を /opt/python へ集約（Lambdaに持ち込む）
RUN python -m pip install --upgrade pip && \
    python -m pip install --target /opt/python -r requirements.txt

# /opt/python を PYTHONPATH に載せたので playwright が実行できる
RUN python -m playwright install chromium

# ---- runtime: 実行時依存だけ入れて軽量化 ----
FROM python:${PYTHON_VERSION}-slim AS runtime

ENV PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1 \
    PLAYWRIGHT_BROWSERS_PATH=/playwright \
    PYTHONPATH=/opt/python

WORKDIR /var/task

# builder成果物をコピー
COPY --from=builder /opt/python /opt/python
COPY --from=builder /playwright /playwright

# Playwright(Chromium) のOS依存を導入
# ※ apt キャッシュ削除でサイズ削減
RUN python -m playwright install-deps chromium && \
    rm -rf /var/lib/apt/lists/*

# アプリコード
COPY app/ ./app/

# Lambda Runtime Interface Client で Lambda 互換化
# ※ requirements.txt に awslambdaric が必要です
ENTRYPOINT ["python", "-m", "awslambdaric"]
CMD ["app.handler.lambda_handler"]
