#!/usr/bin/env python3
"""
Check random links from Click for Charity PTC page
Reports status via Telegram bot
"""

import requests
from bs4 import BeautifulSoup
import random
import os
import sys
from datetime import datetime

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

def get_all_links(url):
    """Fetch the page and extract task links from task-list-container"""
    try:
        response = requests.get(url, timeout=10)
        response.raise_for_status()
        soup = BeautifulSoup(response.content, 'html.parser')
        links = []
        
        # Find the task-list-container element
        task_container = soup.find('section', class_='task-list-container')
        
        if not task_container:
            send_telegram(f"❌ Could not find task-list-container on {TARGET_URL}")
            sys.exit(1)
        
        # Find all a.btn-visit links within the container
        for link in task_container.find_all('a', class_='btn-visit', href=True):
            href = link['href']
            if href.startswith('http'):
                links.append(href)
        
        return links
    except Exception as e:
        send_telegram(f"❌ Failed to fetch {TARGET_URL}: {str(e)}")
        sys.exit(1)

def is_excluded(url):
    """Check if URL should be excluded (paid links, etc)"""
    url_lower = url.lower()
    for domain in EXCLUDED_DOMAINS:
        if domain.lower() in url_lower:
            return True
    return False

def check_link(url):
    """Check if a link is working (returns 200)"""
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
    
    # Get all links from the page
    all_links = get_all_links(TARGET_URL)
    print(f"Found {len(all_links)} total links")
    
    # Filter out excluded links
    available_links = [link for link in all_links if not is_excluded(link)]
    print(f"Available to check: {len(available_links)} (excluded: {len(all_links) - len(available_links)})")
    
    if len(available_links) < LINKS_TO_CHECK:
        send_telegram(f"⚠️ Not enough links to check! Available: {len(available_links)}, need: {LINKS_TO_CHECK}")
        return
    
    # Pick random links
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
        message += f"Checked 2 random links on {datetime.now().strftime('%Y-%m-%d %H:%M')} UTC\n"
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
    
    # Send to Telegram
    success = send_telegram(message)
    if success:
        print("✅ Telegram message sent")
    else:
        print("❌ Failed to send Telegram message", file=sys.stderr)
        sys.exit(1)

if __name__ == "__main__":
    main()
