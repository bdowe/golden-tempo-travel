# Plan: Local-Content Seeding

> **HOW.** Translates `spec.md` into a file-level technical approach. Every
> decision should trace back to an acceptance criterion. See `../../CLAUDE.md`
> for repo conventions referenced below — don't restate them, point to them.

## Technical Approach

A single bash script (`scripts/seed_local_content.sh`, bash + curl + jq,
shellcheck-clean) walks the content directory and drives the **existing**
admin endpoints — no Go or Flutter changes. Rationale: the ingest pipeline
(extraction → Places verification → draft insert) already does all the hard
work server-side; a client-side batch runner keeps the anti-hallucination
gate and curation queue untouched by construction, and a shell script is the
cheapest thing Brian can run against any environment (dev gateway or prod)
with just a URL and credentials.

Idempotency is client-side: a `.ingested` ledger of sha256 content hashes per
source directory. Hash-of-content (not filename or mtime) means renames don't
re-ingest but edits do — matching the spec's "edited material is new drafts"
decision.

## Go API Changes

**None.** The script is a pure client of:

- `POST /api/v1/auth/login` → `{user, token}` (`auth_handler.go`,
  `AuthResponse.Token` is the bearer session id).
- `GET /api/v1/admin/local/sources` → `store.LocalSource[]` (match by exact
  `.name`); `POST` same path with
  `{name, bio, photo_url, location, expertise, credibility, consent_ref}`
  (`createLocalSourceRequest` in `local_ingest_handler.go`) → 201 + source
  (take `.id`).
- `POST /api/v1/admin/local/ingest` with
  `{source_id, city, kind, raw_text}` (`ingestRequest`; kind ∈
  `transcript|notes|voice_memo`, empty → `notes`) → 201 `ingestResponse`:
  `{recommendations: [...], guide_id?, verified, unverified}` — the script
  reports `recommendations | length`, `verified`, `unverified`, `guide_id`.
- `GET /api/v1/admin/local/coverage` → `coverageRow[]`
  `{city, published, draft, archived}` for the closing table.

All admin routes sit behind `authMiddleware` + `adminMiddleware`; the script
sends `Authorization: Bearer <token>` and fails fast with a clear message on
401/403 (probe = the sources GET).

## Script Design (`scripts/seed_local_content.sh`)

- **Env contract:** `BASE_URL` (default `http://localhost:3000` — the nginx
  gateway), `SEED_TOKEN` **or** `SEED_EMAIL`+`SEED_PASSWORD`, `CONTENT_DIR`
  (default `./content/local`), `CITY` (optional slug filter),
  `SEED_SLEEP` (seconds between API calls, default 1 — stays well under the
  general 60/min per-IP limiter in `main.go`).
- **Traversal:** `find -maxdepth 1` + `sort` piped into `while read` loops
  (no `mapfile`/arrays — keeps macOS's stock bash 3.2 happy). City dirs
  starting with `_` are skipped unless `CITY` names them exactly.
- **City name:** slug → spaces + title-case in awk; `city.json` `.name`
  overrides when present.
- **Find-or-create source:** GET the source list once per source dir, exact
  `jq 'select(.name == $n)'` match; otherwise POST `source.json` filtered
  through jq to the accepted fields (`with_entries(select(.value != null))`
  so absent optionals stay absent).
- **Material files:** `NN-*.txt` / `NN-*.md`, filename-sorted. First line
  `kind: (transcript|notes|voice_memo)` is matched with a bash regex,
  stripped (plus one following blank line); body is passed to jq via
  `--rawfile`/`--arg`-style safe encoding (`jq -n --arg`) so any text is
  valid JSON.
- **Ingest call:** `curl --max-time 180` (extraction is a synchronous Claude
  call), capture HTTP status + body separately; on 201 print the draft /
  verified / unverified counts and append `sha256  filename` to
  `<source-dir>/.ingested`; on anything else print the server's `error`
  field, count a failure, continue.
- **Exit code:** non-zero iff any source/profile/file failed; skipped-via-
  ledger and nothing-matched are success.

## Repository Layout Changes

- `.gitignore`: ignore `content/*` and everything under `content/local/*`
  **except** `content/local/README.md` and `content/local/_example/`; ignore
  `.ingested` ledgers everywhere (so the fixture's ledger never lands in
  git).
- `content/local/README.md`: the operator-facing copy of the file-format
  contract + a run example.
- `content/local/_example/`: one fictional city (`city.json` naming it
  "Exampleville", one source with `source.json` + two material files, one
  exercising the `kind:` header). Safe fake data; used by the live test.
- `Makefile`: `seed-local` target (added to `.PHONY`) wrapping the script,
  `## help` text in the existing format; passes `CONTENT_DIR`/`CITY`
  through and defaults `BASE_URL` to `$(GATEWAY_URL)`.

## Flutter Changes

None.

## Contract Parity  ← anti-drift gate

No Go/Dart model changes. The script-side contract rows to hold against the
handlers:

| JSON key | Go type (handler) | Script use | Nullable? | ✓ |
|----------|-------------------|------------|-----------|---|
| `token` (login resp) | `string` (`AuthResponse`) | bearer token | no | ☑ |
| `name` (source) | `string` | exact-match key / create | no | ☑ |
| `bio`,`photo_url`,`location`,`expertise`,`credibility`,`consent_ref` | `string` (empty → NULL via `strPtrOrNil`) | passthrough from `source.json` | yes | ☑ |
| `id` (source resp) | `uuid.UUID` | becomes `source_id` | no | ☑ |
| `source_id`,`city`,`kind`,`raw_text` (ingest req) | `string` | request body | `kind` empty→`notes` | ☑ |
| `recommendations` (ingest resp) | `[]store.LocalRecommendation` | `length` = drafts created | no | ☑ |
| `verified`,`unverified` (ingest resp) | `int` | per-file report | no | ☑ |
| `guide_id` (ingest resp) | `*string`, `omitempty` | mentioned when present | yes | ☑ |
| `city`,`published`,`draft`,`archived` (coverage) | `string`/`int64` | closing table | no | ☑ |

## Cross-cutting

- **Env vars:** none added server-side. `ANTHROPIC_API_KEY` and
  `GOOGLE_PLACES_API_KEY` must be live on the **target server** (already
  documented in `.env.sample`); the seeder itself carries only credentials.
- **Gateway:** default `BASE_URL` is the gateway (`:3000`); paths are all
  `/api/v1/*` so no proxy changes.
- **Rate limits:** sequential + `SEED_SLEEP` respects the 60/min general
  limiter; login is on the strict tier but is a single call.

## Verification

(Mirror into `tasks.md` as the final tasks.)

- `shellcheck scripts/seed_local_content.sh` — clean.
- `make api-fmt && make api-vet` — confirm no Go drift (no Go changes made).
- Live end-to-end against `make docker-dev` at `http://localhost:3000`:
  1. Register a throwaway user via the API, flip `is_admin` in Postgres.
  2. `SEED_TOKEN=… CITY=_example ./scripts/seed_local_content.sh` — expect
     source created, both fixture files ingested, drafts visible via
     `GET /api/v1/admin/local/recommendations?status=draft`, coverage table
     printed.
  3. Re-run — expect every file reported skipped (ledger), exit 0.
  4. Clean up: delete the fixture's drafts/guides/materials/source and the
     throwaway user (children first — the `local_*` FKs are `ON DELETE
     RESTRICT`).
- `make seed-local CITY=_example` — Makefile wiring works, help text shows
  in `make help`.
