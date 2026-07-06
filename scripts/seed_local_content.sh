#!/usr/bin/env bash
# seed_local_content.sh — bulk-ingest local-sourced content through the admin API.
#
# Walks a content directory (see content/local/README.md and
# specs/local-content-seeding/ for the format) and drives the EXISTING admin
# endpoints: find-or-create each source, ingest each material file, then print
# the coverage table. No new API surface; drafts only — publishing stays human.
#
# Environment:
#   BASE_URL       target server (default http://localhost:3000 — the gateway)
#   SEED_TOKEN     pre-issued admin bearer token; or
#   SEED_EMAIL / SEED_PASSWORD   admin credentials for POST /auth/login
#   CONTENT_DIR    corpus root (default ./content/local)
#   CITY           optional city-slug filter (also the only way to seed
#                  underscore-prefixed fixture cities like _example)
#   SEED_SLEEP     seconds between API calls (default 1; general limiter is 60/min)
#
# Idempotent: successful ingests append "sha256  filename" to the source dir's
# .ingested ledger; matching files are skipped on re-runs. Exit is non-zero if
# any source or file failed.

set -u

BASE_URL="${BASE_URL:-http://localhost:3000}"
CONTENT_DIR="${CONTENT_DIR:-./content/local}"
CITY="${CITY:-}"
SEED_TOKEN="${SEED_TOKEN:-}"
SEED_EMAIL="${SEED_EMAIL:-}"
SEED_PASSWORD="${SEED_PASSWORD:-}"
SEED_SLEEP="${SEED_SLEEP:-1}"
API="$BASE_URL/api/v1"

FAILURES=0
INGESTED=0
SKIPPED=0

log()  { printf '%s\n' "$*"; }
warn() { printf 'WARN: %s\n' "$*" >&2; }
fail() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }

for dep in curl jq; do
  command -v "$dep" >/dev/null 2>&1 || fail "missing dependency: $dep"
done

sha256_of() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | awk '{print $1}'
  else
    shasum -a 256 "$1" | awk '{print $1}'
  fi
}

# api_call METHOD PATH [JSON_BODY] — sets the globals RESP_BODY and LAST_STATUS
# (must run in the current shell, never in $(...), so both survive). Ingest can
# block on a synchronous Claude extraction, hence the generous --max-time.
LAST_STATUS=""
RESP_BODY=""
api_call() {
  local method="$1" path="$2" body="${3:-}" tmp status
  tmp="$(mktemp)"
  if [ -n "$body" ]; then
    status="$(curl -sS -o "$tmp" -w '%{http_code}' --max-time 180 \
      -X "$method" "$API$path" \
      -H "Authorization: Bearer $SEED_TOKEN" \
      -H 'Content-Type: application/json' \
      -d "$body")" || status="000"
  else
    status="$(curl -sS -o "$tmp" -w '%{http_code}' --max-time 180 \
      -X "$method" "$API$path" \
      -H "Authorization: Bearer $SEED_TOKEN")" || status="000"
  fi
  LAST_STATUS="$status"
  RESP_BODY="$(cat "$tmp")"
  rm -f "$tmp"
}

error_of() { # best-effort {"error": ...} extraction from a response body
  printf '%s' "$1" | jq -r '.error // empty' 2>/dev/null || true
}

# --- auth ---------------------------------------------------------------------

if [ -z "$SEED_TOKEN" ]; then
  [ -n "$SEED_EMAIL" ] && [ -n "$SEED_PASSWORD" ] \
    || fail "set SEED_TOKEN, or SEED_EMAIL and SEED_PASSWORD"
  login_body="$(jq -n --arg email "$SEED_EMAIL" --arg password "$SEED_PASSWORD" \
    '{email: $email, password: $password}')"
  api_call POST /auth/login "$login_body"
  [ "$LAST_STATUS" = "200" ] || fail "login failed ($LAST_STATUS): $(error_of "$RESP_BODY")"
  SEED_TOKEN="$(printf '%s' "$RESP_BODY" | jq -r '.token // empty')"
  [ -n "$SEED_TOKEN" ] || fail "login succeeded but no token in response"
  log "Logged in as $SEED_EMAIL"
fi

# Probe an admin route so bad/non-admin credentials fail fast and clearly.
api_call GET /admin/local/sources
case "$LAST_STATUS" in
  200) : ;;
  401) fail "token rejected (401) — not logged in?" ;;
  403) fail "account is not an admin (403)" ;;
  *)   fail "cannot reach $API/admin/local/sources ($LAST_STATUS): $(error_of "$RESP_BODY")" ;;
esac

[ -d "$CONTENT_DIR" ] || fail "content directory not found: $CONTENT_DIR"

# --- helpers ------------------------------------------------------------------

title_case_slug() { # new-york -> New York
  printf '%s' "$1" | tr '-' ' ' \
    | awk '{for (i = 1; i <= NF; i++) $i = toupper(substr($i,1,1)) substr($i,2)} 1'
}

# find_or_create_source $1=source.json — sets SRC_ID on success. Runs in the
# current shell (not $(...)) so counters and logs behave normally.
SRC_ID=""
find_or_create_source() {
  local file="$1" name create_body
  SRC_ID=""
  name="$(jq -r '.name // empty' "$file")"
  if [ -z "$name" ]; then
    warn "$file: missing required \"name\" — skipping source"
    return 1
  fi
  api_call GET /admin/local/sources
  if [ "$LAST_STATUS" != "200" ]; then
    warn "could not list sources ($LAST_STATUS) — skipping $name"
    return 1
  fi
  SRC_ID="$(printf '%s' "$RESP_BODY" \
    | jq -r --arg n "$name" 'map(select(.name == $n)) | first | .id // empty')"
  if [ -n "$SRC_ID" ]; then
    log "  source: $name (exists)"
    return 0
  fi
  # Keep only the fields the endpoint accepts; drop absent optionals.
  create_body="$(jq '{name, bio, photo_url, location, expertise, credibility, consent_ref}
                     | with_entries(select(.value != null))' "$file")"
  api_call POST /admin/local/sources "$create_body"
  sleep "$SEED_SLEEP"
  if [ "$LAST_STATUS" != "201" ]; then
    warn "could not create source $name ($LAST_STATUS): $(error_of "$RESP_BODY")"
    return 1
  fi
  SRC_ID="$(printf '%s' "$RESP_BODY" | jq -r '.id // empty')"
  log "  source: $name (created)"
  [ -n "$SRC_ID" ]
}

ingest_file() { # $1=source id  $2=city name  $3=material file  $4=ledger path
  local src_id="$1" city_name="$2" file="$3" ledger="$4"
  local hash first_line kind body payload drafts verified unverified guide

  hash="$(sha256_of "$file")"
  if [ -f "$ledger" ] && grep -q "^$hash" "$ledger"; then
    log "    $(basename "$file"): skipped (already ingested)"
    SKIPPED=$((SKIPPED + 1))
    return 0
  fi

  # Optional first-line header: "kind: transcript|notes|voice_memo" (stripped).
  first_line="$(head -n 1 "$file")"
  if [[ "$first_line" =~ ^kind:[[:space:]]*(transcript|notes|voice_memo)[[:space:]]*$ ]]; then
    kind="${BASH_REMATCH[1]}"
    body="$(tail -n +2 "$file")"
    body="${body#$'\n'}" # drop the conventional blank line after the header
  else
    kind="notes"
    body="$(cat "$file")"
  fi
  if [ -z "$(printf '%s' "$body" | tr -d '[:space:]')" ]; then
    warn "    $(basename "$file"): empty after header — skipping (not ledgered)"
    FAILURES=$((FAILURES + 1))
    return 1
  fi

  # jq does the JSON string encoding, so any raw text is safe in the payload.
  payload="$(printf '%s' "$body" | jq -Rs \
    --arg source_id "$src_id" --arg city "$city_name" --arg kind "$kind" \
    '{source_id: $source_id, city: $city, kind: $kind, raw_text: .}')"

  api_call POST /admin/local/ingest "$payload"
  sleep "$SEED_SLEEP"
  if [ "$LAST_STATUS" != "201" ]; then
    warn "    $(basename "$file"): ingest failed ($LAST_STATUS): $(error_of "$RESP_BODY")"
    FAILURES=$((FAILURES + 1))
    return 1
  fi

  drafts="$(printf '%s' "$RESP_BODY" | jq -r '.recommendations | length')"
  verified="$(printf '%s' "$RESP_BODY" | jq -r '.verified')"
  unverified="$(printf '%s' "$RESP_BODY" | jq -r '.unverified')"
  guide="$(printf '%s' "$RESP_BODY" | jq -r '.guide_id // empty')"
  log "    $(basename "$file"): $drafts drafts ($verified verified, $unverified unverified)${guide:+, guide $guide}"
  printf '%s  %s\n' "$hash" "$(basename "$file")" >> "$ledger"
  INGESTED=$((INGESTED + 1))
}

# --- walk the corpus ------------------------------------------------------------

log "Seeding from $CONTENT_DIR into $BASE_URL${CITY:+ (city filter: $CITY)}"
matched_city=0

while IFS= read -r city_dir; do
  city_slug="$(basename "$city_dir")"
  if [ -n "$CITY" ]; then
    [ "$city_slug" = "$CITY" ] || continue
  else
    case "$city_slug" in _*)
      log "Skipping fixture city $city_slug (target it explicitly with CITY=$city_slug)"
      continue ;;
    esac
  fi
  matched_city=1

  if [ -f "$city_dir/city.json" ]; then
    city_name="$(jq -r '.name // empty' "$city_dir/city.json")"
  else
    city_name=""
  fi
  [ -n "$city_name" ] || city_name="$(title_case_slug "$city_slug")"
  log "City: $city_name ($city_slug)"

  found_source=0
  while IFS= read -r src_dir; do
    found_source=1
    if [ ! -f "$src_dir/source.json" ]; then
      warn "  $(basename "$src_dir"): no source.json — skipping"
      FAILURES=$((FAILURES + 1))
      continue
    fi
    if ! find_or_create_source "$src_dir/source.json"; then
      FAILURES=$((FAILURES + 1))
      continue
    fi

    found_material=0
    while IFS= read -r material; do
      found_material=1
      ingest_file "$SRC_ID" "$city_name" "$material" "$src_dir/.ingested" || true
    done < <(find "$src_dir" -maxdepth 1 -type f \
               \( -name '[0-9][0-9]-*.txt' -o -name '[0-9][0-9]-*.md' \) | sort)
    [ "$found_material" = 1 ] || log "    (no NN-*.txt|md material files)"
  done < <(find "$city_dir" -mindepth 1 -maxdepth 1 -type d | sort)
  [ "$found_source" = 1 ] || log "  (no source directories)"
done < <(find "$CONTENT_DIR" -mindepth 1 -maxdepth 1 -type d | sort)

if [ "$matched_city" = 0 ]; then
  log "Nothing to seed${CITY:+ (no city directory named \"$CITY\")}."
fi

# --- coverage ---------------------------------------------------------------------

log ""
log "Coverage ($API/admin/local/coverage):"
api_call GET /admin/local/coverage
if [ "$LAST_STATUS" = "200" ]; then
  printf '%s' "$RESP_BODY" | jq -r '
    (["CITY", "PUBLISHED", "DRAFT", "ARCHIVED"] | @tsv),
    (.[] | [.city, (.published|tostring), (.draft|tostring), (.archived|tostring)] | @tsv)' \
    | column -t -s "$(printf '\t')"
else
  warn "could not fetch coverage ($LAST_STATUS)"
fi

log ""
log "Done: $INGESTED ingested, $SKIPPED skipped, $FAILURES failed."
[ "$FAILURES" = 0 ] || exit 1
