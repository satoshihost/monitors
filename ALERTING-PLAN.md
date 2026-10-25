# Alerting & Bot Messaging — Plan

Last updated: 2026-10-21  
Status: Telegram-only. Matrix fallback **dormant** since 2026-10-21 (see below).

## 2026-10-21: Matrix fallback made dormant

Nobody reads the Matrix room, and the stored token turned out to be already invalid
(`M_UNKNOWN_TOKEN`), so the fallback had silently stopped working anyway. After the es7
incident (`security/es7-unknown-remote-agent-2026-10-20.md`) a credential sitting on 5
servers with no benefit was not worth keeping: `/root/.matrix-alerts` was deleted from
es1/es3/es5/es7/RN1. `notify.sh` is unchanged — with the file absent it logs
"Matrix credentials not found — skipping" and alerts continue via Telegram only.

**To re-enable if Telegram is ever lost:** log in to the matrix.org bot account, get a fresh
access token (Element: Settings → Help & About → Advanced), write `~/.matrix-alerts` using the
template in "Credentials" below, then
`MATRIX_CREDS_FILE=~/.matrix-alerts ./deploy-notify.sh`. Nothing else needs changing.
The sections below describe the original dual-channel design and remain accurate for that.

## Planned: per-push GitHub CI

Org-wide push checks (DirectSponsor + satoshihost repos, Telegram on failure, free GitHub Actions) are documented in **[github-push-checks.md](github-push-checks.md)**. Not built yet.

---

## Problem

All monitoring currently reports exclusively to a Telegram group.
Element/Matrix had setup difficulties that made it unreliable as a primary
channel. A single-channel alert system means failures can go unnoticed.

## Decision

**Telegram = Plan A. Matrix/Element = Plan B (fallback only).**

Every alert tries Telegram first. If that fails, it falls back to Matrix.
The system must work even if either channel is unavailable.

This follows the architecture in `~/work/Multi-Platform-Bot-Messaging-System`
(project spec file).

---

## Current State — All Telegram Integration Points

| Script | Runs on | Trigger | Notifies via |
|--------|---------|---------|--------------|
| `backup-system/verify-all-backups.sh` | es3 cron 06:00 UTC | checks backups exist on both backup servers for es1/es3/es5/es7/RN1, plus es2 on servarica1 (backup-server) only | `backup-system/telegram-notify.sh` |
| `backup-system/backup-*.sh` (6 scripts) | each VPS cron | after each backup run | same `telegram-notify.sh` |
| `server-scripts/es3/security-check-all.sh` → es3:`/root/` | es3 cron 06:30 UTC | security checks across all 6 servers (es2 added 2026-10-25) | `satoshi-notify.sh` via `/root/telegram-notify.sh` wrapper |
| `security/scripts/env-inventory-all.sh` → es3:`/root/` | es3 cron Sunday 07:00 UTC | OS/kernel/PHP/Apache versions + pending updates; full report at es3:/root/env-inventory.txt | same as above |
| `monitors/check_links.py` | GitHub Actions daily | checks PTC page links | direct Telegram API via env vars |
| `server-scripts/rn1/reconcile-notify.sh` → RN1:`/root/scripts/` | RN1 cron Sunday 03:00 UTC | cross-checks DS ledger vs profiles vs HTML amounts | DS_AuthBot → Telegram (creds: `/root/.telegram-ds-reconcile`) |
| `server-scripts/rn1/notify-new-posts.py` → RN1:`/root/scripts/` | RN1 cron hourly | new posts on directsponsor.net | SitesCheckBot → Telegram (creds: `/root/.telegram-sites-check`) |

Auth-server backup scripts (`projects/auth-server/backup-db-daily.sh`,
`backup-to-remote.sh`) do **not** currently send alerts — noted as a gap.

---

## Target Architecture

```
Any script / GitHub Action
        |
    notify() call
        |
   [ try Telegram ] ──── success ──▶  Telegram group (primary)
        |
      fail
        |
   [ try Matrix ]   ──── success ──▶  Matrix room (fallback)
        |
      fail
        |
   [ log warning, exit cleanly ]
```

Telegram is the primary channel.
Matrix is best-effort fallback — its failure must never cause a script to fail.

---

## Central Hub Approach

`~/work/monitors/` is the **canonical home** for:
- All alerting/notification code
- Documentation of every monitor across all projects
- The shared `notify.sh` and `notify.py` helpers

Other project folders (backup-system, security, auth-server) either:
- Reference the deployed server path `/usr/local/lib/satoshi-notify.sh`, or
- Keep a local copy with a comment pointing back here as the master

This solves the "related things spread across different projects" problem:
the code can live where it must, but `monitors/` is always the place to
look first and the place where changes originate.

---

## Implementation Plan

### Phase 1 — Setup ✅ DONE

- [x] Using existing personal matrix.org account as bot
- [x] Created private room `satoshihost-alerts` (E2E encryption disabled — required for curl/API posting)
- [x] Room ID: `!uUbDeAHlFHpMwhVvZE:matrix.org`
- [x] Credentials stored at `/root/.matrix-alerts` on all 5 servers
- [x] Local copy at `~/.matrix-alerts` (gitignored, for re-deployment)
      Format:
      ```
      MATRIX_HOMESERVER=https://matrix-client.matrix.org
      MATRIX_ACCESS_TOKEN=mat_...
      MATRIX_ROOM_ID=!uUbDeAHlFHpMwhVvZE:matrix.org
      ```

### Phase 2 — Shared bash helper ✅ DONE

- [x] `monitors/notify.sh` created — `notify()` tries Telegram first, falls back to Matrix
- [x] Deployed to `/usr/local/lib/satoshi-notify.sh` on all 5 servers (es1, es3-auth, es5, es7, RN1)
- [x] `backup-system/telegram-notify.sh` replaced with thin wrapper — existing backup scripts unchanged
- [x] `security-check-all.sh` on es3 uses `/root/telegram-notify.sh` which is now a thin wrapper
      mapping `telegram_notify()` → `notify()` via `/usr/local/lib/satoshi-notify.sh`

### Phase 3 — GitHub Actions (Python) ⏳ LOW PRIORITY

`monitors/check_links.py` already uses Telegram (Plan A) directly — no change needed for primary alerting.
Optional: add Matrix as fallback (add `requests.post` to Matrix HTTP API + GitHub secrets), but
Telegram-only is acceptable here since GitHub Actions failures are also visible in the Actions tab.

### Phase 4 — Docs update ⏳ TODO

Update `monitors/README.md`:
- List ALL monitors (not just GitHub Actions ones)
- Include VPS-based monitors with paths to their scripts
- Note where each script's canonical copy lives

---

## Matrix API — How It Works

Sending a message requires one HTTP call. No SDK or library needed.

```bash
curl -s -X POST \
  "https://matrix-client.matrix.org/_matrix/client/v3/rooms/ROOM_ID/send/m.room.message/$(date +%s)" \
  -H "Authorization: Bearer ${MATRIX_ACCESS_TOKEN}" \
  -H "Content-Type: application/json" \
  -d '{"msgtype":"m.text","body":"your message here"}'
```

Identical complexity to the current Telegram curl call.

---

## Decisions Made

- **Bot account:** existing personal matrix.org account (a dedicated bot account can be
  created later if needed; for now the personal account token is acceptable since
  these are your own servers and the token only posts to one private room)
- **Room:** single `#satoshihost-alerts:matrix.org` room for all alerts
- **Auth-server coverage:** `verify-all-backups.sh` already covers this — it SSHes
  into both backup servers and checks all 5 hosts (es1/es3/es5/es7/RN1) for
  recent backups. The auth-server scripts only *create* backups; no alerting gap.

## Next Steps

1. Update `monitors/README.md` as full central index — list all monitors including VPS-based ones (Phase 4)

## Re-deployment

If `notify.sh` changes or credentials need rotating:
```bash
MATRIX_CREDS_FILE=~/.matrix-alerts /home/andy/work/monitors/deploy-notify.sh
```

---

## Credentials Files — All Servers

All credential files are root-readable only (`chmod 600`). Never committed to any repo.

| File | Lives on | Used by |
|------|----------|---------|
| `/root/.telegram-backup-alerts` | all 5 servers | `satoshi-notify.sh` (Telegram fallback for backup/security alerts) |
| `/root/.matrix-alerts` | all 5 servers | `satoshi-notify.sh` (Matrix fallback) |
| `/root/.telegram-ds-reconcile` | RN1 | `reconcile-notify.sh` (DS_AuthBot) |
| `/root/.telegram-sites-check` | RN1 | `notify-new-posts.py` (SitesCheckBot) |

Local re-deployment template for `~/.matrix-alerts`:
```
MATRIX_HOMESERVER=https://matrix-client.matrix.org
MATRIX_ACCESS_TOKEN=mat_...
MATRIX_ROOM_ID=!uUbDeAHlFHpMwhVvZE:matrix.org
```

Local re-deployment template for `~/.telegram-backup-alerts` (and per-server equivalents):
```
TELEGRAM_BOT_TOKEN=...
TELEGRAM_CHAT_ID=...
```
