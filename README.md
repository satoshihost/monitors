# SatoshiHost Monitoring

Central index for all automated monitoring across SatoshiHost infrastructure.
Alerts go to Telegram. (Matrix/Element fallback is dormant since 2026-10-21 — see ALERTING-PLAN.md to re-enable.)

See [ALERTING-PLAN.md](ALERTING-PLAN.md) for architecture, credentials, and deployment details.

**Planned:** per-push CI on all DirectSponsor / satoshihost repos → Telegram on failure — [github-push-checks.md](github-push-checks.md)

---

## All Active Monitors

### GitHub Actions (this repo)

| Monitor | Script | Trigger | Alerts via |
|---------|--------|---------|------------|
| CFC link checker | `check_links.py` | manual (Actions tab) | Telegram direct |

### VPS cron — es3 (es3-auth)

| Monitor | Script | Schedule | Alerts via |
|---------|--------|----------|------------|
| Backup verification | `backup-system/verify-all-backups.sh` | 06:00 UTC daily | `satoshi-notify.sh` |
| Per-server backups (×6) | `backup-system/backup-*.sh` | after each backup run | `satoshi-notify.sh` |
| Security checks | `security-check-all.sh` | 06:30 UTC daily | `satoshi-notify.sh` → `/root/telegram-notify.sh` |

### VPS cron — RN1

| Monitor | Script | Schedule | Alerts via |
|---------|--------|----------|------------|
| DS donation reconciliation | `server-scripts/rn1/reconcile-notify.sh` | Sunday 03:00 UTC | DS_AuthBot → Telegram |
| DS new posts | `server-scripts/rn1/notify-new-posts.py` | hourly | SitesCheckBot → Telegram |

### Uptime Kuma — es2

Member-facing uptime monitoring and status pages for SatoshiHost users, at https://uptime.satoshihost.com/dashboard.
Internal server monitoring is planned to move to checkmk, alongside Hermes.
Status, problems and to-do list: [UPTIME-KUMA.md](UPTIME-KUMA.md)

---

## Shared Notification Helper

`notify.sh` is the canonical alerting helper. It is deployed to `/usr/local/lib/satoshi-notify.sh`
on all 5 servers (es1, es3-auth, es5, es7, RN1).

```bash
source /usr/local/lib/satoshi-notify.sh
notify "✅ Title" "Optional body text"
```

Tries Telegram first; would fall back to Matrix if `/root/.matrix-alerts` existed (it currently doesn't — dormant).

To re-deploy after changes:
```bash
/home/andy/work/monitors/deploy-notify.sh
# after rotating the Telegram token:
TELEGRAM_CREDS_FILE=~/.telegram-backup-alerts /home/andy/work/monitors/deploy-notify.sh
```

---

## Repo Structure

```
notify.sh                        # Shared alert helper — canonical source
deploy-notify.sh                 # Deploys notify.sh to all 5 servers
check_links.py                   # GitHub Actions: CFC PTC link checker
.github/workflows/
  check_links.yml                # Workflow for link checker
server-scripts/
  rn1/
    reconcile-notify.sh          # DS reconciliation cron (RN1)
    notify-new-posts.py          # DS new-post notifier (RN1)
docs/
  SETUP-links.md                 # Link checker setup guide
ALERTING-PLAN.md                 # Full architecture, credentials, history
UPTIME-KUMA.md                   # Uptime Kuma on es2 — member-facing monitoring
github-push-checks.md            # Plan: org-wide push CI → Telegram (not yet built)
```

---

## Link Checker — Quick Reference

Checks 2 random links on [clickforcharity.net/ptc.html](https://clickforcharity.net/ptc.html)
to confirm they are reachable. Skips paid rotation links.

- Run manually: **Actions tab → Daily Link Check → Run workflow**
- Needs GitHub secrets: `TELEGRAM_BOT_TOKEN`, `TELEGRAM_CHAT_ID`
- Full setup: [docs/SETUP-links.md](docs/SETUP-links.md)

---

**Last updated:** 2026-05-23
