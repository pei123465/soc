# syntax=docker/dockerfile:1

ARG PYTHON_VERSION=3.12
ARG PLAYWRIGHT_VERSION=1.58.0

# ---- builder: Python依存とブラウザ本体を取得 ----
FROM python:${PYTHON_VERSION}-bookworm AS builder

ENV PIP_NO_CACHE_DIR=1 \
    PLAYWRIGHT_BROWSERS_PATH=/playwright

WORKDIR /build

COPY requirements.txt .

# 依存（/opt/pythonへ集約）
RUN python -m pip install --upgrade pip && \
    python -m pip install --target /opt/python -r requirements.txt

# Chromiumのみダウンロード（OS依存はruntime側で入れる）
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

# OS依存のみ導入（apt前提）
# ※ Playwrightの公式手順は install-deps / install --with-deps を提示しているciteturn0search1turn7view0
RUN python -m playwright install-deps chromium && \
    rm -rf /var/lib/apt/lists/*

# アプリコード
COPY app/ ./app/

# Lambda Runtime Interface Client（非AWSベースイメージをLambda互換にする）citeturn5view1turn4view4
ENTRYPOINT [ "python", "-m", "awslambdaric" ]
CMD [ "app.handler.lambda_handler" ]
