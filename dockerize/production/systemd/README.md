# systemd units — Golden Tempo backups

Committed units that schedule the nightly Postgres backup (`../backup.sh`).
They assume the standard prod layout: the stack lives at `/opt/goldentempo`
(compose project `goldentempo`, `.env` beside the compose file) and
`backup.sh` is copied to `/opt/goldentempo/backup.sh`.

## Install

```bash
# From /opt/goldentempo on the prod host (adjust paths if your layout differs):
sudo cp dockerize/production/backup.sh            /opt/goldentempo/backup.sh
sudo chmod +x /opt/goldentempo/backup.sh
sudo cp dockerize/production/systemd/goldentempo-backup.service /etc/systemd/system/
sudo cp dockerize/production/systemd/goldentempo-backup.timer   /etc/systemd/system/

sudo systemctl daemon-reload
sudo systemctl enable --now goldentempo-backup.timer
```

## Operate

```bash
systemctl list-timers goldentempo-backup.timer   # next/last run
sudo systemctl start goldentempo-backup.service  # run one backup now
journalctl -u goldentempo-backup.service -n 50   # last run's output
```

The service is `Type=oneshot`; the timer fires it daily ~04:10 with
`Persistent=true` (a backup missed while the host was off runs on next boot).
Knobs come from `EnvironmentFile=/opt/goldentempo/.env` — see the `backup.sh`
header and the Backups block in `.env.sample` (`BACKUP_DIR`, `RETENTION_DAYS`,
`RCLONE_REMOTE`, `BACKUP_HEARTBEAT_FILE`, `BACKUP_STALE_HOURS`).

## Verify the backups actually restore

A backup you can't restore isn't a backup. Periodically run the non-destructive
drill (it touches only a throwaway container, never the live stack):

```bash
sudo /opt/goldentempo/restore-drill.sh   # restores the latest dump, PASS/FAIL
```

`../restore.md` is the full, live-stack restore runbook.

## How the heartbeat feeds health

`backup.sh` writes `BACKUP_HEARTBEAT_FILE` (default
`$BACKUP_DIR/.last_success`) on every good local dump. The API's
`GET /api/v1/admin/ops/health` reads it and flags `backups.stale` (and marks
the whole service degraded, alerting admins) once it is older than
`BACKUP_STALE_HOURS` (default 36) — so a silently-failing timer becomes a
visible, alerting condition. Make the file readable by the API process/container.
