#!/usr/bin/env python3
"""
Check random links from Click for Charity PTC page using a real browser.
Uses Playwright to load the page and wait for JavaScript to render the task list,
then checks that the links are reachable.
Reports status via Telegram bot.
"""

import requests
import random
import os
import sys
from datetime import datetime
from playwright.sync_api import sync_playwright, TimeoutError as PlaywrightTimeout

# Configuration - EDIT THESE TO ADD/REMOVE EXCLUDED LINKS
EXCLUDED_DOMAINS = [
    "rotate5url.com",
    "rotate4all"
]

# Telegram config (from GitHub Secrets)
BOT_TOKEN = os.getenv("TELEGRAM_BOT_TOKEN")
CHAT_ID = os.getenv("TELEGRAM_CHAT_ID")

# The page to check
TARGET_URL = "https://clickforcharity.net/ptc.html"

# Number of links to check per run
LINKS_TO_CHECK = 2

# How long to wait for tasks to appear after JS renders (ms)
TASK_RENDER_TIMEOUT_MS = 30000

# How many times to retry before sending an alert
MAX_RETRIES = 2

def get_all_links():
    """Load ptc.html in a real browser and extract task links after JS renders them.
    Retries up to MAX_RETRIES times before sending an alert."""
    last_error = None

    for attempt in range(1, MAX_RETRIES + 1):
        print(f"Attempt {attempt}/{MAX_RETRIES}: loading {TARGET_URL} ...")
        with sync_playwright() as p:
            browser = p.chromium.launch(headless=True)
            page = browser.new_page()

            try:
                page.goto(TARGET_URL, timeout=30000)

                # Wait for at least one btn-visit link to appear in the task list
                page.wait_for_selector("#task-list a.btn-visit", timeout=TASK_RENDER_TIMEOUT_MS)

            except PlaywrightTimeout:
                browser.close()
                last_error = "timeout"
                print(f"  Attempt {attempt} timed out after {TASK_RENDER_TIMEOUT_MS // 1000}s")
                continue
            except Exception as e:
                browser.close()
                last_error = str(e)
                print(f"  Attempt {attempt} failed: {e}")
                continue

            # Extract all btn-visit hrefs
            link_elements = page.query_selector_all("#task-list a.btn-visit")
            links = []
            for el in link_elements:
                href = el.get_attribute("href") or ""
                if href.startswith("http"):
                    links.append(href)

            browser.close()
            return links

    # All attempts failed
    if last_error == "timeout":
        send_telegram(f"❌ <b>PTC page failed to render tasks</b>\nNo task links appeared within {TASK_RENDER_TIMEOUT_MS // 1000}s on {TARGET_URL} (tried {MAX_RETRIES}x)\nPage may be down or JS broken.")
    else:
        send_telegram(f"❌ <b>Failed to load PTC page</b>\n{TARGET_URL} (tried {MAX_RETRIES}x)\nError: {last_error}")
    sys.exit(1)


def is_excluded(url):
    """Check if URL should be excluded (paid rotation links)"""
    url_lower = url.lower()
    for domain in EXCLUDED_DOMAINS:
        if domain.lower() in url_lower:
            return True
    return False

def check_link(url):
    """Check if a link is reachable (returns 200)"""
    try:
        response = requests.head(url, timeout=10, allow_redirects=True)
        return response.status_code == 200, response.status_code
    except requests.exceptions.Timeout:
        return False, "TIMEOUT"
    except requests.exceptions.ConnectionError:
        return False, "CONNECTION_ERROR"
    except Exception as e:
        return False, str(type(e).__name__)

def send_telegram(message):
    """Send message to Telegram group"""
    url = f"https://api.telegram.org/bot{BOT_TOKEN}/sendMessage"
    payload = {
        "chat_id": CHAT_ID,
        "text": message,
        "parse_mode": "HTML"
    }
    try:
        response = requests.post(url, json=payload, timeout=10)
        return response.status_code == 200
    except Exception as e:
        print(f"Failed to send Telegram message: {e}", file=sys.stderr)
        return False

def main():
    print(f"[{datetime.now().isoformat()}] Starting link check...")

    # Load the page with a real browser and extract rendered task links
    all_links = get_all_links()
    print(f"Found {len(all_links)} total links")

    # Filter out excluded (paid rotation) links
    available_links = [link for link in all_links if not is_excluded(link)]
    excluded_count = len(all_links) - len(available_links)
    print(f"Available to check: {len(available_links)} (excluded: {excluded_count})")

    if len(available_links) < LINKS_TO_CHECK:
        send_telegram(f"⚠️ <b>PTC Links Check: not enough links</b>\nAvailable: {len(available_links)}, need: {LINKS_TO_CHECK}\n{TARGET_URL}")
        return

    # Pick random links to test
    links_to_test = random.sample(available_links, LINKS_TO_CHECK)

    print(f"Checking {len(links_to_test)} random links...")
    results = []
    all_ok = True

    for link in links_to_test:
        working, status = check_link(link)
        results.append((link, working, status))
        print(f"  {link}: {'✅' if working else '❌'} ({status})")
        if not working:
            all_ok = False

    # Build Telegram message
    if all_ok:
        message = f"✅ <b>PTC Links Check OK</b>\n"
        message += f"Checked {LINKS_TO_CHECK} random links on {datetime.now().strftime('%Y-%m-%d %H:%M')} UTC\n"
        message += "All working!"
    else:
        message = f"❌ <b>PTC Links Check FAILED</b>\n"
        message += f"Time: {datetime.now().strftime('%Y-%m-%d %H:%M')} UTC\n\n"
        for link, working, status in results:
            if not working:
                message += f"❌ {link}\n   Status: {status}\n\n"
        for link, working, status in results:
            if working:
                message += f"✅ {link}\n"

    success = send_telegram(message)
    if success:
        print("✅ Telegram message sent")
    else:
        print("❌ Failed to send Telegram message", file=sys.stderr)
        sys.exit(1)

if __name__ == "__main__":
    main()
