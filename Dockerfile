# syntax=docker/dockerfile:1

ARG PYTHON_VERSION=3.12
ARG FUNCTION_DIR="/function"

FROM public.ecr.aws/docker/library/python:${PYTHON_VERSION}-slim

ARG FUNCTION_DIR

# LambdaでPlaywrightが書き込みやキャッシュに使う場所を /tmp に寄せる
# ブラウザは /playwright に入れる（root cache 回避）
ENV PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1 \
    HOME=/tmp \
    XDG_CACHE_HOME=/tmp \
    XDG_CONFIG_HOME=/tmp \
    XDG_DATA_HOME=/tmp \
    PLAYWRIGHT_BROWSERS_PATH=/playwright

# function directory
RUN mkdir -p ${FUNCTION_DIR}
WORKDIR ${FUNCTION_DIR}

# 依存
COPY requirements.txt ${FUNCTION_DIR}/requirements.txt
RUN pip install --no-cache-dir -r requirements.txt && \
    # Qiita記事と同じ：ブラウザ＋OS依存をまとめて入れる
    python -m playwright install --with-deps chromium

# アプリ
COPY app/ ${FUNCTION_DIR}/app/

# Lambda Runtime Interface Client
# ※ requirements.txt に awslambdaric が必要
ENTRYPOINT ["/usr/local/bin/python", "-m", "awslambdaric"]
CMD ["app.handler.lambda_handler"]
