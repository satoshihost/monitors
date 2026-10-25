# Uptime Kuma

Member-facing uptime monitoring and status pages for SatoshiHost.

- **Server:** es2 (89.116.44.57) — see [servers/es2.md](../servers/es2.md) (`/home/andy/work/servers/es2.md`)
- **URL:** https://uptime.satoshihost.com/ (redirects to `/dashboard`)
- **Status:** ✅ Running, SSL valid, offsite backups working (fixed 2026-10-25, see below)

**Last checked:** 2026-10-25, over SSH (`ssh es2`, hp3 key)

---

## Role

- **Kuma = the service for SatoshiHost users.** We monitor the websites we host, give members
  status pages (e.g. `uptime.satoshihost.com/status/<customer>`), and send down/up alerts by Telegram.
- **Internal server monitoring moves to checkmk**, which runs alongside the Hermes agent. checkmk
  does deep admin-side checks and Kuma does member-facing uptime and presentation. They are
  different tools and don't overlap, so we need both.
- Our own production sites can still have Kuma monitors and appear on a public status page.

### To do for this role

1. ~~Renew the SSL cert and fix the `/` 403~~ done 2026-10-25
2. Log in and review the existing monitors. Connect Telegram notifications (bot + chat ID, as in
   [ALERTING-PLAN.md](ALERTING-PLAN.md)).
3. Add monitors for every website we currently host, plus SSL-expiry checks
4. Create status pages: one public SatoshiHost page, then one per customer
5. Add uptime.satoshihost.com itself to checkmk (or an external heartbeat) so someone is watching the monitor

---

## How we know it is running

Checked over HTTPS without logging in (first check, 2026-10-25):

| Check | Result |
|-------|--------|
| `https://uptime.satoshihost.com/` | was **403 Forbidden** from nginx, now 302 to `/dashboard` (fixed) |
| `/dashboard`, `/setup` | 200, the Uptime Kuma web app loads |
| `/manifest.json` | `"name": "Uptime Kuma"` |
| `/api/entry-page`, `/socket.io/` | Kuma API and websocket respond |
| socket.io `needSetup` | `false`, so the admin account has already been created |
| `/api/badge/1/status`, `/api/badge/2/status` | `Up`, so monitors 1 and 2 exist and are public |
| Server timezone (from Kuma) | Europe/London |

---

## Fixed on 2026-10-25

1. **SSL expired 2026-02-25.** acme.sh's daily renewal had failed since January: the port-80
   vhosts redirected *everything* to HTTPS at server level, so the ZeroSSL challenge never
   validated. Fix: port-80 blocks now serve `/.well-known/acme-challenge/` from `/var/www/acme`
   and redirect the rest; cert re-issued from **Let's Encrypt** (webroot mode), valid to
   2027-01-23, auto-renew from 2026-12-23 via the root crontab acme.sh job. certbot (unused)
   was uninstalled; acme.sh is the only cert tool on es2.
2. **`/` returned 403.** `try_files $uri $uri/ @kuma` hit the empty-index folder
   `/var/www/uptime-static`. Now `try_files $uri @kuma`, so `/` goes to Kuma and
   `/status.html` (static page in that folder) still works.
3. **Duplicate cert files.** The Kuma vhost used its own copy (`uptime.satoshihost.com.cer`)
   that renewal never updated. Both vhosts now use `/etc/nginx/ssl/list.clickforcharity.net.{cer,key}`.
4. **SSH access restored** with the hp3 key; es2 SSH is now key-only (root password still works
   on the provider web console).
5. **Offsite backups had failed since ~2026-10-20** (old `warp` key rejected after the key
   rotation). Now uses a dedicated `/root/.ssh/es2-backup` key, authorised on the backup server
   as `restrict,from="89.116.44.57"`. `warp` deleted. Test backup copied OK.

Still unknown: which monitors exist and whether Telegram is connected (needs a dashboard login).

Pre-change copies of the configs are in `/root/config-backup-20261025/` on es2.

---

## Install details (verified over SSH 2026-10-25)

- Docker image `louislam/uptime-kuma:1`, container `uptime-kuma`, `restart: always`
- Compose file: `/opt/uptime-kuma/docker-compose.yml`
- Data (SQLite): `/opt/uptime-kuma/data` → mounted at `/app/data`
- Listens on `127.0.0.1:3001`, with nginx reverse proxy in front (same nginx as Listmonk)
- nginx vhost `/etc/nginx/sites-available/uptime.satoshihost.com`: static root
  `/var/www/uptime-static`, everything else proxied to Kuma with websocket headers
- Backup: included in `/opt/backup-listmonk.sh` (daily 02:00 from root crontab, combined tar.gz
  with Listmonk DB, ~12MB), local `/var/backups/listmonk/` (7 days) +
  `backup-server:/var/backups/es2/` (30 days, key `/root/.ssh/es2-backup`),
  log `/var/log/listmonk-backup.log`

Minimal compose (from [servers/es2-deployment-plan.md](../servers/es2-deployment-plan.md)):

```yaml
services:
  uptime-kuma:
    image: louislam/uptime-kuma:1
    container_name: uptime-kuma
    restart: always
    ports:
      - "127.0.0.1:3001:3001"
    volumes:
      - ./data:/app/data
```

nginx needs websocket headers for Kuma (`proxy_http_version 1.1`, `Upgrade`, `Connection "upgrade"`).

---

## Plans and ideas

- Full plan (customer status pages, service tiers, provisioning script, public
  `status.satoshihost.com`): [projects/uptime-monitoring/README.md](../projects/uptime-monitoring/README.md)
- Embeddable status widget that reads from this instance: `projects/uptime-monitoring/status.html`
- **Monitor the monitor:** Kuma can't alert on itself. Use checkmk or an external dead-man's-switch
  heartbeat (see `hermes-agent/hermes-orangepi-plan.md` §4)
- Lessons from the earlier install: Telegram alerts were reliable. Keep config backed up and documented,
  not only in the GUI.

---

## Doc cleanup (2026-10-25)

These docs had stale Kuma info and now point here: `servers/es2.md`, `servers/es2/SERVER_CONTEXT.md`,
`servers/servers-ai-context/server-es2-git-monitoring.md`, `servers/HOSTNAME_STANDARDIZATION.md`,
`servers/es2-deployment-plan.md`, `projects/uptime-monitoring/README.md`,
`projects/docs/docs/infrastructure/servers-overview.md`, `projects/docs/docs/infrastructure/servers/es2-git-monitoring.md`,
`projects/docs/docs/reference/domain-inventory.md`, `projects/docs/docs/backup-server/index.md`,
`hermes-agent/HERMES_INSTALL_PLAN.md`, `hermes-agent/hermes-orangepi-plan.md`.

Left unchanged as historical records: `projects/listmonk/LISTMONK_RESURRECTION_PLAN.md`,
`currencies/uselesscoin/deployment/*.sh`, and `hermes-agent/andy-notes.txt`.
