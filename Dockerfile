# syntax=docker/dockerfile:1

ARG PYTHON_VERSION=3.12
ARG FUNCTION_DIR="/function"

FROM public.ecr.aws/docker/library/python:${PYTHON_VERSION}-slim

ARG FUNCTION_DIR

ENV PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1 \
    HOME=/tmp \
    XDG_CACHE_HOME=/tmp \
    XDG_CONFIG_HOME=/tmp \
    XDG_DATA_HOME=/tmp \
    PLAYWRIGHT_BROWSERS_PATH=/playwright \
    DEBUG=pw:browser*

RUN mkdir -p ${FUNCTION_DIR}
WORKDIR ${FUNCTION_DIR}

COPY requirements.txt ${FUNCTION_DIR}/requirements.txt
RUN pip install --no-cache-dir -r requirements.txt && \
    python -m playwright install --with-deps chromium

COPY app/ ${FUNCTION_DIR}/app/

ENTRYPOINT ["/usr/local/bin/python", "-m", "awslambdaric"]
CMD ["app.handler.lambda_handler"]
