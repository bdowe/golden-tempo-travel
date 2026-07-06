# Spec: Local-Content Seeding

> **WHAT & WHY only.** No tech choices, file names, libraries, or code. If a
> sentence names a file or a package, it belongs in `plan.md`, not here.

## Context

The local-sourced content layer is the product's stated moat, but it currently
has zero content: the only way in is an admin manually posting one blob of raw
research text at a time through the admin ingest endpoint. Seeding even one
city that way is tedious; seeding ten is untenable. This feature defines a
simple on-disk contract for organizing research material per city and per
local source, plus a batch runner that walks that directory and drives the
**existing** admin endpoints to ingest everything. No new API surface is
added; the coordinate anti-hallucination gate and the human curation/publish
queue remain exactly as they are — seeding produces *drafts*, never published
content.

## User Stories

- As **Brian (admin/curator)**, I want to **drop research files into a folder
  per city and run one command** so that an entire city's local content is
  ingested as drafts without hand-crafting API calls.
- As **Brian**, I want **re-runs to skip material that was already ingested**
  so that adding one new file to a city doesn't duplicate every draft.
- As **Brian**, I want a **per-file report and a final coverage table** so I
  can see how many drafts were created, how many verified against a real
  place, and where each city stands.
- As a **traveler**, I (indirectly) benefit because cities gain curated local
  recommendations faster — still human-reviewed before anything is published.

## Acceptance Criteria

- [ ] A documented content-directory format exists: one folder per city, one
      folder per local source inside it, a source profile file, and numbered
      raw-material files (see File Format Contract below).
- [ ] Running the seeder against a content directory logs in, creates any
      local sources that don't already exist (matched by exact name), and
      ingests every material file through the existing admin ingest endpoint.
- [ ] Each ingested file prints: city, source, file name, number of drafts
      created, and how many were place-verified vs unverified.
- [ ] The run ends with the per-city coverage table (published/draft counts)
      from the existing admin coverage endpoint.
- [ ] Re-running the seeder over the same directory ingests nothing (every
      previously ingested file is reported as skipped), based on a per-source
      ledger of content hashes.
- [ ] A partial failure (one file errors) does not stop the run, is clearly
      reported, leaves that file out of the ledger (so a re-run retries it),
      and makes the overall run exit non-zero.
- [ ] The real content directory is not committed to git; a README explaining
      the format and one clearly-fake example fixture city **are** committed.
- [ ] The example fixture city is skipped by normal runs and only seeded when
      explicitly targeted, so fixture data can never leak into a real
      environment by default.
- [ ] Drafts created by seeding are indistinguishable from manually ingested
      drafts: same curation queue, same publish-blocked-without-coordinates
      gate, same attribution.

## File Format Contract

The seeder reads a content directory (default `content/local/`) shaped as:

```
content/local/
  <city-slug>/                     e.g. athens, new-york
    city.json                      optional: {"name": "<display name>"}
    <source-slug>/                 e.g. maria-the-baker
      source.json                  the local source's profile (required)
      01-<anything>.txt|.md        raw material, ingested in filename order
      02-<anything>.md
      .ingested                    machine-written ledger (never committed)
```

- **City name.** The city name sent to the ingest endpoint is the city
  folder's slug with hyphens turned into spaces and each word capitalized
  (`new-york` → `New York`). When that transformation can't produce the right
  name (accents, casing), `city.json`'s `name` field overrides it.
- **`source.json`** carries exactly the fields the existing create-source
  admin endpoint accepts: `name` (required — also the find-or-create match
  key, exact match), and optional `bio`, `photo_url`, `location`,
  `expertise`, `credibility`, `consent_ref`. Unknown fields are ignored.
- **Material files** are plain text or markdown named `NN-*.txt` or
  `NN-*.md` (two leading digits give deterministic order). The file's whole
  content is submitted as the raw research text, except an optional first
  line of the form `kind: transcript`, `kind: notes`, or `kind: voice_memo`
  (the kinds the ingest endpoint accepts), which sets the material kind and
  is stripped from the submitted text. Without the header the kind defaults
  to `notes`.
- **Ledger.** After a successful ingest the seeder appends the file's content
  hash to a `.ingested` file next to the material. Files whose hash already
  appears in the ledger are skipped on re-runs. Editing a file changes its
  hash, so edited material is (deliberately) re-ingested as new drafts.
- **Fixture.** `content/local/_example/` is a committed, clearly-fictional
  city used by tests and as living documentation of the format.
  Underscore-prefixed city folders are skipped unless explicitly targeted.

## API Surface

**None added or changed.** The seeder is a pure client of existing admin
endpoints: login, list/create local sources, ingest, list recommendations,
and coverage. Authentication is a normal admin session (email/password login
or a pre-issued token).

## Data Model

**No schema changes.** Seeding writes through the existing pipeline: raw
material provenance, draft recommendations (verified against the places
provider where possible), and optional draft guides — all attributed to the
local source.

## UI Behavior

None. This is an operator tool: a command-line runner plus a make target. Its
output surfaces in the existing admin curation queue and coverage screens.

## Edge Cases & Error States

- **Missing/bad credentials or non-admin account** → the run aborts up front
  with a clear message before touching any content.
- **Source folder without a profile file, or a profile missing `name`** → that
  source is skipped with a warning; the run continues and exits non-zero.
- **Ingest failure for one file** (extraction error, upstream outage, rate
  limit) → reported, not added to the ledger, run continues, exit non-zero.
- **Server without the AI or places keys configured** → ingest returns its
  existing configured-error; the seeder surfaces it per file. The keys must
  be live on the **target server** at seed time (the seeder itself needs no
  API keys). Place verification failures are not errors: unverified drafts
  are kept, per existing behavior — publishing them stays blocked until a
  human fixes the pin.
- **Rate limits** — the seeder paces itself (sequential, small delay) to stay
  under the server's general per-IP request limit; extraction calls are slow
  and given a generous per-request timeout.
- **Empty content directory / filter matching nothing** → reported, exits
  zero (nothing to do is not a failure).

## Out of Scope

- No new API endpoints, no server-side batch mode, no async job queue.
- No auto-publish: the coordinate gate and human curation are untouched.
- No de-duplication of *drafts* (only of *input files*): re-ingesting edited
  material intentionally creates new drafts for the curator to reconcile.
- No deletion/sync: removing a file does not archive its drafts.
- No non-text material (audio, images) — transcribe first, then seed.

## Open Questions

None — resolved during spec review:
- Ledger lives next to the content (not centrally) so moving a city folder
  keeps its ingest state.
- Exact-name matching for find-or-create is acceptable at this scale; a
  rename creates a new source, which the admin UI already surfaces.
