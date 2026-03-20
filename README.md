# SatoshiHost Monitoring

Automated monitoring and health checks for SatoshiHost infrastructure and services. All checks report to the **@satoshihost** Telegram group. Zero cost - runs on GitHub Actions.

## 🎯 Current Monitors

| Monitor | Purpose | Schedule | Status |
|---------|---------|----------|--------|
| **Link Checker** | Verifies links on [Click for Charity PTC page](https://clickforcharity.net/ptc.html) work correctly | Daily 9 AM UTC | ✅ Active |
| **API Health** | *(Coming soon)* | - | 🔄 Planned |
| **DNS Resolution** | *(Coming soon)* | - | 🔄 Planned |
| **SSL Certificate** | *(Coming soon)* | - | 🔄 Planned |

> **Note:** VPS-based monitors (backups, server security) run directly on the auth server and are separate from this repo.

---

## 🚀 Quick Start

### Setup (First Time Only)

1. **Add Telegram Secrets** to this repo:
   - Go to **Settings → Secrets and variables → Actions**
   - Add `TELEGRAM_BOT_TOKEN`
   - Add `TELEGRAM_CHAT_ID`
   - (See details in specific monitor docs)

2. **Choose your monitor(s)** and follow setup:
   - [Link Checker Setup](docs/SETUP-links.md)
   - API Health *(coming soon)*
   - DNS Checker *(coming soon)*
   - SSL Checker *(coming soon)*

3. **Done!** Monitors run automatically on schedule.

### Test a Monitor Manually

1. Go to **Actions** tab
2. Select the workflow (e.g., "Daily Link Check")
3. Click **Run workflow**
4. Check Telegram group in ~30 seconds

---

## 📋 Monitors Overview

### Link Checker
Randomly checks 2 links daily from your PTC page to ensure they're working. Skips paid links.

- **What it checks:** 2 random links from clickforcharity.net/ptc.html
- **Excludes:** Rotate5url.com, Rotate4All (paid links)
- **Frequency:** Daily at 9 AM UTC
- **Notifications:** All OK messages + error alerts
- **Setup:** [Read full setup here](docs/SETUP-links.md)

### (More monitors will go here as they're added)

---

## 🔐 Security

**Telegram credentials are protected:**
- Stored in GitHub Secrets (encrypted)
- Never visible in logs or code
- Only accessible to workflows
- Safe to reuse same bot for multiple monitors

**All scripts:**
- Are open source (in this repo)
- Don't store sensitive data locally
- Report via Telegram only
- Use standard HTTP requests (no sketchy libraries)

---

## 🛠️ Adding a New Monitor

When you want to add another monitor:

1. Create a new script: `scripts/your_checker.py`
2. Create a workflow: `.github/workflows/your_check.yml`
3. Create docs: `docs/SETUP-your_check.md`
4. Update this README with the new monitor in the table above
5. Test it manually first (Actions tab → Run workflow)

Each monitor follows the same pattern - see Link Checker as a template.

---

## 📊 Telegram Messages

You'll receive messages like:

**✅ All Good:**
```
✅ PTC Links Check OK
Checked 2 random links on 2026-03-20 09:00 UTC
All working!
```

**❌ Something Broken:**
```
❌ PTC Links Check FAILED
Time: 2026-03-20 09:00 UTC

❌ https://example.com
   Status: CONNECTION_ERROR

✅ https://otherlink.com
```

---

## 🐛 Troubleshooting

**Monitor isn't running?**
- Check **Actions** tab for workflow status
- Verify secrets are added (Settings → Secrets)
- Check the specific monitor's setup doc

**No Telegram message?**
- Run workflow manually to test (Actions → Run workflow)
- Check that both secrets exist and have correct values
- Look at workflow logs for errors

**Getting random errors?**
- Some links might block automated checks
- Intermittent network issues are normal
- Pattern of failures = real problem

See specific monitor docs for detailed troubleshooting.

---

## 📝 Contributing

To add a new monitor or improve existing ones:

1. Test locally first
2. Add clear comments in code
3. Include setup documentation
4. Update this README
5. Test the workflow in GitHub Actions before merging

---

## 📚 Resources

- [GitHub Actions Documentation](https://docs.github.com/en/actions)
- [Cron Syntax Reference](https://crontab.guru/)
- [Telegram Bot API](https://core.telegram.org/bots/api)

---

**Last Updated:** 2026-03-20  
**Maintained by:** SatoshiHost Team  
**Cost:** $0 (GitHub Actions free tier)
