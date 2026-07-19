#!/usr/bin/env bash
# Nightly Postgres backup for the goldentempotravel.com production stack.
#
# Dumps the database from the running postgres container (pg_dump custom
# format, gzipped), prunes local dumps older than RETENTION_DAYS, and — if
# rclone is installed with the configured remote — copies the new dump
# off-site. Designed for cron:
#
#   10 4 * * * /opt/goldentempo/backup.sh >> /var/log/goldentempo-backup.log 2>&1
#
# Exit status: non-zero if the dump itself fails (cron mails/logs it);
# a missing/unconfigured rclone only warns and exits 0 (off-site copy is
# best-effort, the local dump already succeeded).
#
# Every path/name is overridable via env so the script can be dry-run
# against another stack (e.g. the dev compose) without touching this file:
#
#   COMPOSE_FILE      compose file of the stack to back up
#                     (default /opt/goldentempo/docker-compose.yml)
#   COMPOSE_PROJECT   compose project name; empty => derived by compose
#                     from the compose-file directory (default empty)
#   BACKUP_DIR        where dumps land (default /opt/goldentempo/backups)
#   PG_SERVICE        compose service name of postgres (default postgres)
#   PG_USER / PG_DB   database credentials (default travel / travel_planner)
#   RETENTION_DAYS    local prune horizon (default 14)
#   RCLONE_REMOTE     rclone destination (default r2:goldentempo-backups)
set -euo pipefail

COMPOSE_FILE="${COMPOSE_FILE:-/opt/goldentempo/docker-compose.yml}"
COMPOSE_PROJECT="${COMPOSE_PROJECT:-}"
BACKUP_DIR="${BACKUP_DIR:-/opt/goldentempo/backups}"
PG_SERVICE="${PG_SERVICE:-postgres}"
PG_USER="${PG_USER:-travel}"
PG_DB="${PG_DB:-travel_planner}"
RETENTION_DAYS="${RETENTION_DAYS:-14}"
RCLONE_REMOTE="${RCLONE_REMOTE:-r2:goldentempo-backups}"

compose() {
    if [ -n "$COMPOSE_PROJECT" ]; then
        docker compose -f "$COMPOSE_FILE" -p "$COMPOSE_PROJECT" "$@"
    else
        docker compose -f "$COMPOSE_FILE" "$@"
    fi
}

mkdir -p "$BACKUP_DIR"

out="$BACKUP_DIR/${PG_DB}-$(date +%F).dump.gz"
tmp="$out.tmp"
trap 'rm -f "$tmp"' EXIT

echo "[backup] $(date -u +%FT%TZ) dumping $PG_DB from service '$PG_SERVICE' to $out"

# pipefail makes a pg_dump failure fail the whole pipeline; the tmp+mv dance
# means a failed run never leaves a truncated file behind as "the backup".
compose exec -T "$PG_SERVICE" pg_dump -Fc -U "$PG_USER" "$PG_DB" | gzip >"$tmp"
mv "$tmp" "$out"

echo "[backup] wrote $(du -h "$out" | cut -f1) $out"

# Prune local dumps older than the retention horizon.
find "$BACKUP_DIR" -maxdepth 1 -name "${PG_DB}-*.dump.gz" -type f \
    -mtime +"$RETENTION_DAYS" -print -delete |
    sed 's/^/[backup] pruned /'

# Off-site copy (best-effort): requires rclone AND the remote to exist.
remote_name="${RCLONE_REMOTE%%:*}"
if ! command -v rclone >/dev/null 2>&1; then
    echo "[backup] WARNING: rclone not installed — skipping off-site copy of $out" >&2
    exit 0
fi
if ! rclone listremotes | grep -qx "${remote_name}:"; then
    echo "[backup] WARNING: rclone remote '${remote_name}:' not configured — skipping off-site copy of $out" >&2
    exit 0
fi
rclone copy "$out" "$RCLONE_REMOTE/"
echo "[backup] copied $out to $RCLONE_REMOTE/"
