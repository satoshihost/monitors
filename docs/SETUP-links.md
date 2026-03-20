# Link Checker Setup

Automatically checks random links from [Click for Charity PTC page](https://clickforcharity.net/ptc.html) daily. Reports via Telegram.

## Prerequisites

- This repo already has Telegram secrets configured (see main README)
- Telegram bot token and chat ID must be in GitHub Secrets

## Files Needed

```
satoshihost/monitors/
├── check_links.py
└── .github/workflows/
    └── check-links.yml
```

## Installation

### 1. Add Files to Repo

Copy these files to your repo (they're in the outputs):
- `check_links.py` → root of repo
- `check-links.yml` → `.github/workflows/` folder

(The `.github` folder might be hidden but GitHub handles it fine when you upload)

### 2. Verify Telegram Secrets

Go to repo **Settings → Secrets and variables → Actions**

Make sure these exist:
- `TELEGRAM_BOT_TOKEN` = your bot token
- `TELEGRAM_CHAT_ID` = -1002247747301

Both must be correct for notifications to work.

### 3. Test It

1. Go to **Actions** tab in GitHub
2. Click **Daily Link Check** workflow
3. Click **Run workflow** button
4. Wait ~30 seconds
5. Check your @satoshihost Telegram group for the result

✅ If you see a message = it's working!

---

## Configuration

### Change Check Time

Edit `.github/workflows/check-links.yml`

Find:
```yaml
- cron: '0 9 * * *'
```

This means 9 AM UTC daily. Change using [crontab.guru](https://crontab.guru/):
- `0 9 * * *` = 9:00 AM UTC
- `0 6 * * *` = 6:00 AM UTC  
- `30 14 * * *` = 2:30 PM UTC
- `0 0 * * *` = Midnight UTC

### Add More Excluded Links

Edit `check_links.py`

Find this section (around line 10):
```python
# Configuration - EDIT THESE TO ADD/REMOVE EXCLUDED LINKS
EXCLUDED_DOMAINS = [
    "rotate5url.com",
    "rotate4all"
]
```

Add domains like:
```python
EXCLUDED_DOMAINS = [
    "rotate5url.com",
    "rotate4all",
    "anotherpaidsite.com",
    "exclude-this-domain.org"
]
```

### Check More/Fewer Links

Find in `check_links.py` (around line 25):
```python
# Number of links to check per run
LINKS_TO_CHECK = 2
```

Change `2` to any number (1, 3, 5, etc.)

**Note:** You need at least this many non-excluded links on the page. If you have 10 total links and 2 are excluded, you can check up to 8 per run.

---

## What It Does

1. **Fetches** the PTC page: https://clickforcharity.net/ptc.html
2. **Extracts** all links from the page
3. **Filters** out excluded domains (paid links)
4. **Picks** 2 random links
5. **Tests** if each link responds with HTTP 200 (working)
6. **Reports** results to Telegram:
   - ✅ All OK message if everything works
   - ❌ Error details if anything fails

**Example messages:**

✅ Success:
```
✅ PTC Links Check OK
Checked 2 random links on 2026-03-20 09:00 UTC
All working!
```

❌ Failure:
```
❌ PTC Links Check FAILED
Time: 2026-03-20 09:00 UTC

❌ https://example.com
   Status: CONNECTION_ERROR

✅ https://otherlink.com
```

---

## How It Works (Technical)

- **Language:** Python 3.11
- **Libraries:** requests, beautifulsoup4
- **Runs on:** Ubuntu (GitHub Actions free tier)
- **Cost:** $0
- **Execution time:** ~10-20 seconds

The workflow:
1. Checks out the repo code
2. Installs Python and required libraries
3. Runs `check_links.py` script
4. Script sends result to Telegram via bot token

All automated, no manual steps needed after setup.

---

## Troubleshooting

### No Telegram message received

**Check 1:** Verify secrets are correct
- Go to Settings → Secrets
- Make sure both `TELEGRAM_BOT_TOKEN` and `TELEGRAM_CHAT_ID` exist
- Values shouldn't be truncated or have extra spaces

**Check 2:** Test the workflow manually
- Actions → Daily Link Check → Run workflow
- Wait 30 seconds
- Check Telegram group

**Check 3:** Look at workflow logs
- Go to Actions tab
- Click the failed run
- Click "Daily Link Check" job
- Scroll to see error messages

### Getting "Not enough links" error

You have fewer available links than `LINKS_TO_CHECK`.

**Solution:**
- Either add more links to the PTC page
- Or reduce `LINKS_TO_CHECK` to a smaller number
- Check current count: look at the Telegram message or workflow logs

### Links showing as failed but they actually work

The link might:
- Be blocking automated requests
- Have a firewall rule
- Require JavaScript to load (this script can't do that)
- Be temporarily down

If one link fails repeatedly but works when you visit it manually, you might need to exclude it or increase the timeout value.

### Workflow shows green ✅ but no Telegram message

Your Telegram credentials might be wrong. Double-check:
- Bot token matches exactly
- Chat ID is `-1002247747301` (including the minus sign!)
- No extra spaces or line breaks

---

## Customization Ideas

- Add multiple workflows checking different sets of links on different schedules
- Add a separate workflow that tests ALL links weekly (more intensive)
- Add logging to track which links fail most often
- Add retry logic for flaky links
- Filter by link type (only check PTC sites, skip payment processors, etc.)

---

## Next Steps

Once this is running smoothly, consider adding other monitors:
- API health checks
- DNS resolution monitoring
- SSL certificate expiry alerts
- Server uptime monitoring

All follow the same pattern - see the main repo README.

---

**Questions?** Check the main [README.md](../README.md) or GitHub Actions docs.
