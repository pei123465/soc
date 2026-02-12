# app/handler.py
import os
import json
import time
import asyncio
from datetime import datetime, timezone

import boto3
from playwright.async_api import async_playwright

s3 = boto3.client("s3")
secrets = boto3.client("secretsmanager")

def _get_secret_json(secret_arn: str) -> dict:
    resp = secrets.get_secret_value(SecretId=secret_arn)  # GetSecretValue API citeturn9search1
    if "SecretString" in resp:
        return json.loads(resp["SecretString"])
    # SecretBinaryの場合
    return json.loads(resp["SecretBinary"].decode("utf-8"))

async def _run(event: dict) -> dict:
    target_url = os.environ["TARGET_URL"]
    bucket = os.environ["SCREENSHOT_BUCKET"]
    prefix = os.environ.get("SCREENSHOT_PREFIX", "captures/")
    secret_arn = os.environ["LOGIN_SECRET_ARN"]

    creds = _get_secret_json(secret_arn)
    username = creds["username"]
    password = creds["password"]

    # Lambdaでの安定化で使われがちなChromium起動フラグ例（要件に応じて調整）citeturn8view0
    launch_args = [
        "--single-process",
        "--no-zygote",
        "--no-sandbox",
        "--disable-gpu",
        "--disable-dev-shm-usage",
        "--headless=new",
    ]

    started = time.time()
    async with async_playwright() as p:
        browser = await p.chromium.launch(args=launch_args)
        context = await browser.new_context()
        page = await context.new_page()

        # 例：ログインページに遷移 → ログイン（セレクタは実システムに合わせて変更）
        await page.goto(target_url, wait_until="domcontentloaded")

        # TODO: セレクタは要件に合わせて変更
        await page.fill('input[name="email"]', username)
        await page.fill('input[name="password"]', password)
        await page.click('button[type="submit"]')

        await page.wait_for_timeout(1500)

        png = await page.screenshot(full_page=True)

        await browser.close()

    ts = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ")
    key = f"{prefix}{ts}.png"

    s3.put_object(Bucket=bucket, Key=key, Body=png, ContentType="image/png")

    return {
        "ok": True,
        "s3": f"s3://{bucket}/{key}",
        "elapsed_sec": round(time.time() - started, 3),
    }

def lambda_handler(event, context):
    return asyncio.run(_run(event))
