# syntax=docker/dockerfile:1

ARG PYTHON_VERSION=3.12

# ---- builder: Python依存とブラウザ本体を取得 ----
FROM public.ecr.aws/docker/library/python:${PYTHON_VERSION}-bookworm AS builder

ENV PIP_NO_CACHE_DIR=1 \
    PYTHONPATH=/opt/python \
    PLAYWRIGHT_BROWSERS_PATH=/playwright

WORKDIR /build

COPY requirements.txt .

# 依存を /opt/python へ集約（Lambdaに持ち込む）
RUN python -m pip install --upgrade pip && \
    python -m pip install --target /opt/python -r requirements.txt

# Chromium を PLAYWRIGHT_BROWSERS_PATH にインストール
RUN python -m playwright install chromium


# ---- runtime: 実行時依存だけ入れて軽量化 ----
FROM public.ecr.aws/docker/library/python:${PYTHON_VERSION}-slim AS runtime

# Lambda で Playwright が書き込みに使いがちな場所を /tmp に寄せる
# （Connection closed while reading from the driver 対策として効くことが多い）
ENV PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1 \
    PYTHONPATH=/opt/python \
    PLAYWRIGHT_BROWSERS_PATH=/playwright \
    HOME=/tmp \
    XDG_CACHE_HOME=/tmp \
    XDG_CONFIG_HOME=/tmp \
    XDG_DATA_HOME=/tmp

WORKDIR /var/task

# builder成果物をコピー
COPY --from=builder /opt/python /opt/python
COPY --from=builder /playwright /playwright

# Playwright(Chromium) のOS依存を導入
# ※ slim でも apt は使える。install-deps は apt を呼ぶので runtime 側でやるのが自然
RUN apt-get update && \
    python -m playwright install-deps chromium && \
    rm -rf /var/lib/apt/lists/*

# アプリコード
COPY app/ ./app/

# Lambda Runtime Interface Client で Lambda 互換化
# ※ requirements.txt に awslambdaric が必要
ENTRYPOINT ["python", "-m", "awslambdaric"]
CMD ["app.handler.lambda_handler"]
