# Production stack — goldentempo.co

Runs the prebuilt GHCR images on a VPS behind **Cloudflare** (proxied DNS,
SSL mode **Full (strict)**). The gateway terminates TLS with a **Cloudflare
Origin CA** certificate and restores the real client IP from
`CF-Connecting-IP` so the API's per-IP rate limiter sees end users, not
Cloudflare edge IPs.

## Server layout

```
/opt/goldentempo/
├── docker-compose.yml        # this directory's compose file
├── .env                      # secrets: API keys, POSTGRES_PASSWORD, DATABASE_URL (PR A2)
├── nginx/
│   ├── prod.conf             # TLS server blocks (mounted over conf.d/default.conf)
│   └── cloudflare-realip.conf# CF ranges + real_ip_header (mounted into conf.d/)
└── backups/                  # pg_dump output

/etc/goldentempo/certs/
├── origin.crt                # Cloudflare Origin CA certificate (goldentempo.co + *.goldentempo.co)
└── origin.key                # its private key (chmod 600, root-owned)
```

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

```bash
# Deploy a new build (images published by CI as :latest and :<sha>)
cd /opt/goldentempo
IMAGE_TAG=<sha> docker compose pull && IMAGE_TAG=<sha> docker compose up -d

# Rollback: same command with the previous sha
IMAGE_TAG=<previous-sha> docker compose pull && IMAGE_TAG=<previous-sha> docker compose up -d

# Config-only change (no new images)
docker compose up -d --force-recreate gateway

# Status / logs
docker compose ps
docker compose logs -f gateway api

# DB backup before risky deploys
docker compose exec postgres pg_dump -U travel travel_planner > backups/$(date +%F).sql
```

## Sanity checks after a deploy

```bash
curl -fsS https://goldentempo.co/health              # gateway
curl -fsS https://goldentempo.co/api/v1/health       # API through the proxy
curl -sI  http://goldentempo.co/                     # 301 → https apex
curl -sI  https://www.goldentempo.co/                # 301 → apex
```
