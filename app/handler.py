# app/handler.py
import os
import time
import asyncio
import logging
from datetime import datetime, timezone

import boto3
from playwright.async_api import async_playwright

logger = logging.getLogger()
logger.setLevel(logging.INFO)

s3 = boto3.client("s3")


def _req_env(name: str) -> str:
    v = os.environ.get(name)
    if not v:
        raise RuntimeError(f"Missing required env var: {name}")
    return v


async def _run(event: dict) -> dict:
    started = time.time()
    logger.info("STEP 0: start event_type=%s", type(event).__name__)

    # --- required env ---
    target_url = _req_env("TARGET_URL")
    bucket = _req_env("SCREENSHOT_BUCKET")
    username = _req_env("LOGIN_USERNAME")
    password = _req_env("LOGIN_PASSWORD")

    # --- optional env ---
    prefix = os.environ.get("SCREENSHOT_PREFIX", "captures/")

    # Playwright/Chromium がキャッシュ/設定を書き込みに行く先を /tmp に寄せる（Lambdaで重要）
    os.environ.setdefault("HOME", "/tmp")
    os.environ.setdefault("XDG_CACHE_HOME", "/tmp")
    os.environ.setdefault("XDG_CONFIG_HOME", "/tmp")
    os.environ.setdefault("XDG_DATA_HOME", "/tmp")

    # Dockerfile/Lambda env と一致させる（Qiita方式）
    os.environ.setdefault("PLAYWRIGHT_BROWSERS_PATH", "/playwright")

    logger.info(
        "STEP 1: env prepared HOME=%s XDG_CACHE_HOME=%s PLAYWRIGHT_BROWSERS_PATH=%s",
        os.environ.get("HOME"),
        os.environ.get("XDG_CACHE_HOME"),
        os.environ.get("PLAYWRIGHT_BROWSERS_PATH"),
    )

    # --- selectors: provided HTML ---
    membership_sel = "#id_membership_code"
    password_sel = "#id_password"
    submit_sel = 'input[type="submit"][name="submit_member"]'

    # --- launch args tuned for Lambda ---
    launch_args = [
        "--no-sandbox",
        "--disable-setuid-sandbox",
        "--disable-dev-shm-usage",
        "--disable-gpu",
        "--no-zygote",
        "--headless=new",
    ]

    logger.info("STEP 2: async_playwright start")
    async with async_playwright() as p:
        chromium_path = p.chromium.executable_path
        logger.info("STEP 3: chromium executable_path=%s", chromium_path)

        if not os.path.exists(chromium_path):
            raise RuntimeError(
                f"Chromium executable not found: {chromium_path}. "
                "Image may be missing browsers or PLAYWRIGHT_BROWSERS_PATH mismatch."
            )

        logger.info("STEP 4: chromium.launch args=%s", launch_args)
        # dumpio=True: Chromium/driver のstderr/stdoutを CloudWatch に流して原因を掴みやすくする
        browser = await p.chromium.launch(args=launch_args, dumpio=True)

        context = None
        page = None
        try:
            logger.info("STEP 5: new_context")
            context = await browser.new_context()
            page = await context.new_page()

            logger.info("STEP 6: goto %s", target_url)
            await page.goto(target_url, wait_until="domcontentloaded", timeout=60_000)

            logger.info("STEP 7: wait_for_selector %s", membership_sel)
            await page.wait_for_selector(membership_sel, timeout=30_000)

            logger.info("STEP 8: fill membership_code")
            await page.fill(membership_sel, username)

            logger.info("STEP 9: fill password")
            await page.fill(password_sel, password)

            logger.info("STEP 10: click submit %s", submit_sel)
            async with page.expect_navigation(wait_until="domcontentloaded", timeout=60_000):
                await page.click(submit_sel)

            logger.info("STEP 11: post-login settle")
            await page.wait_for_timeout(1500)

            logger.info("STEP 12: screenshot full_page=True")
            png = await page.screenshot(full_page=True)

            ts = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ")
            key = f"{prefix}{ts}.png"

            logger.info("STEP 13: upload to s3 bucket=%s key=%s", bucket, key)
            s3.put_object(Bucket=bucket, Key=key, Body=png, ContentType="image/png")

            elapsed = round(time.time() - started, 3)
            logger.info("DONE: ok elapsed_sec=%s s3://%s/%s", elapsed, bucket, key)
            return {"ok": True, "s3": f"s3://{bucket}/{key}", "elapsed_sec": elapsed}

        except Exception as e:
            logger.exception("FAILED: %s", str(e))
            # 失敗時スクショ（page が生きていれば）
            try:
                if page is not None:
                    logger.info("STEP X: capture failure screenshot")
                    png = await page.screenshot(full_page=True)
                    ts = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ")
                    key = f"{prefix}failed/{ts}.png"
                    s3.put_object(Bucket=bucket, Key=key, Body=png, ContentType="image/png")
                    logger.info("STEP X: failure screenshot uploaded s3://%s/%s", bucket, key)
            except Exception:
                logger.exception("FAILSHOT: also failed")
            raise

        finally:
            try:
                if context is not None:
                    await context.close()
            except Exception:
                logger.exception("context.close failed")
            try:
                await browser.close()
            except Exception:
                logger.exception("browser.close failed")


def lambda_handler(event, context):
    return asyncio.run(_run(event))
