# Production stack — goldentempotravel.com

Runs the prebuilt GHCR images on a VPS behind **Cloudflare** (proxied DNS,
SSL mode **Full (strict)**). The gateway terminates TLS with a **Cloudflare
Origin CA** certificate and restores the real client IP from
`CF-Connecting-IP` so the API's per-IP rate limiter sees end users, not
Cloudflare edge IPs.

## Server layout

```
/opt/goldentempo/
├── docker-compose.yml        # this directory's compose file
├── .env                      # secrets — copy .env.sample and fill in (chmod 600)
├── .image_tag                # IMAGE_TAG=<sha> of the live deploy (written by CI)
├── backup.sh                 # nightly pg_dump + prune + optional rclone off-site copy
├── nginx/
│   ├── prod.conf             # TLS server blocks (mounted over conf.d/default.conf)
│   └── cloudflare-realip.conf# CF ranges + real_ip_header (mounted into conf.d/)
└── backups/                  # backup.sh output (gzipped pg_dump custom format)

/etc/goldentempo/certs/
├── origin.crt                # Cloudflare Origin CA certificate (goldentempotravel.com + *.goldentempotravel.com)
└── origin.key                # its private key (chmod 600, root-owned)
```

## Environment / secrets

All runtime configuration lives in one file: `/opt/goldentempo/.env`
(`cp .env.sample .env`, fill in, `chmod 600`). It is used two ways:

1. **Compose interpolation** — `POSTGRES_PASSWORD` (required, no default:
   `docker compose config` fails fast if it's missing) and `IMAGE_TAG`.
2. **`env_file` passthrough into the api** — provider keys, SMTP, Sentry,
   `PUBLIC_*`, tuning vars. See `.env.sample` for the annotated inventory
   of what's required vs degraded-mode-optional.

`DATABASE_URL` is **not** set in `.env` — the compose file composes it from
`POSTGRES_PASSWORD` (so api and postgres can never disagree) with
`sslmode=disable`, which is safe because 5432 is never published to the
host; it exists only on the private compose network.

## How config reaches the containers

**Mounted, never baked.** The gateway image (built by
`dockerize/deployment/Dockerfile`) bakes in:

- `/etc/nginx/snippets/app-locations.conf` — the shared location set
  (API proxy, SPA, share-preview rewrite, static caching, legal pages),
  used verbatim by both the deployment `:80` server and the production
  `:443` server;
- `/etc/nginx/conf.d/share-prerender-map.conf` — the `$share_prerender`
  bot-UA `map` (must live at `http` scope);
- `/etc/nginx/conf.d/default.conf` — the local `:80` server shell.

The production compose then **mounts** `nginx/prod.conf` *over*
`conf.d/default.conf` (replacing the `:80 localhost` shell with the
`:80→301` + `:443 ssl` servers), mounts `nginx/cloudflare-realip.conf` into
`conf.d/`, and mounts `/etc/goldentempo/certs` read-only. Editing a conf on
the host therefore needs only a gateway restart, not an image rebuild:

```bash
docker compose exec gateway nginx -t && docker compose exec gateway nginx -s reload
```

## Client-IP chain (rate limiting correctness)

1. Cloudflare edge connects to nginx `:443` and sets `CF-Connecting-IP`.
2. `cloudflare-realip.conf`: the peer IP is in Cloudflare's published
   ranges, so the realip module rewrites `$remote_addr` to the header's
   value (the end user). Non-Cloudflare peers keep their socket IP and the
   header is ignored — unspoofable.
3. The shared `/api/` proxy block sends
   `X-Forwarded-For: $remote_addr` — **replace, not append** — a single
   trusted value.
4. The Go rate limiter (`src/packages/api/ratelimit.go` `clientIP()`) takes
   the rightmost `X-Forwarded-For` entry → the real user IP.

When Cloudflare publishes new ranges, refresh `cloudflare-realip.conf`
from <https://www.cloudflare.com/ips/> and reload the gateway.

## Deploy / rollback

**Normal path is hands-off:** every green push to `main` builds + pushes
both images to GHCR (`:latest` and `:<sha>`) and the CI `deploy` job
rsyncs this directory to `/opt/goldentempo/` and restarts the stack with
`IMAGE_TAG=<sha>`. It also writes the live tag to
`/opt/goldentempo/.image_tag` so manual restarts don't fall back to
`:latest`. (Until the `DEPLOY_HOST` / `DEPLOY_SSH_KEY` /
`DEPLOY_KNOWN_HOSTS` secrets exist, the deploy job self-skips with a
notice.)

**Rollback** = re-deploy an older image: GitHub → Actions → CI →
*Run workflow* on `main` with `image_tag` set to the git SHA of a previous
green main build. Manual fallback on the server:

```bash
cd /opt/goldentempo

# Restart whatever is currently deployed (reads .image_tag written by CI)
set -a; . ./.image_tag; set +a
docker compose pull && docker compose up -d

# Deploy/rollback a specific build by hand
IMAGE_TAG=<sha> docker compose pull && IMAGE_TAG=<sha> docker compose up -d

# Config-only change (no new images)
docker compose up -d --force-recreate gateway

# Status / logs
docker compose ps
docker compose logs -f gateway api

# DB backup before risky deploys (same script cron runs nightly)
./backup.sh
```

## Backups & restore

`backup.sh` dumps the database (`pg_dump -Fc | gzip`) into `backups/`,
prunes dumps older than 14 days, and — when `rclone` is installed with an
`r2:goldentempo-backups` remote configured — copies the new dump off-site
(otherwise it warns and still exits 0). Nightly cron (as root):

```cron
10 4 * * * /opt/goldentempo/backup.sh >> /var/log/goldentempo-backup.log 2>&1
```

Paths/services are overridable via env (`COMPOSE_FILE`, `COMPOSE_PROJECT`,
`BACKUP_DIR`, …) — see the header of `backup.sh`.

To restore a dump, follow [`restore.md`](restore.md): verify the dump in a
fresh scratch volume first, then swap it under the live stack and confirm
`/api/v1/health` reports `database: ok`.

## Sanity checks after a deploy

```bash
curl -fsS https://goldentempotravel.com/health              # gateway
curl -fsS https://goldentempotravel.com/api/v1/health       # API through the proxy
curl -sI  http://goldentempotravel.com/                     # 301 → https apex
curl -sI  https://www.goldentempotravel.com/                # 301 → apex
```

For the full end-to-end journey (register → trip → item → share/OG → export →
alerts → notifications → teardown), run the smoke harness against the live host.
It registers a throwaway user and deletes it in teardown, so it is safe to run
against production:

```bash
# sql seed mode is local-only (needs the postgres container); against prod use
# plan mode (the AI planner builds a real trip — costs a little Anthropic spend)
# or existing mode with a trip you own (SMOKE_TRIP_ID + SMOKE_TOKEN=<bearer>).
make smoke BASE_URL=https://goldentempotravel.com SMOKE_SEED_MODE=plan
```

Green means the traveler journey works end to end; the run also prints a
**MANUAL CHECKS REMAINING** block for the things a script can't assert on its own
(real Cloudflare real-IP rate limiting, Slack/Facebook link-preview unfurl, SMTP
inbox round-trips, legal-page DRAFT-banner sign-off).
