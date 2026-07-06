# Local-Content Seeding Corpus

This directory holds raw local-sourced research, organized so
`scripts/seed_local_content.sh` (or `make seed-local`) can bulk-ingest it
through the admin API. See `specs/local-content-seeding/` for the full spec.

**Everything here except this README and `_example/` is gitignored** — real
research (interview transcripts, voice-memo notes) never lands in git.

## Layout

```
content/local/
  <city-slug>/                  e.g. athens, new-york
    city.json                   optional: {"name": "New York"} — overrides the
                                slug→name guess (hyphens→spaces, Title Case)
    <source-slug>/              one folder per local source, e.g. maria-the-baker
      source.json               the person's profile (required; see below)
      01-first-interview.txt    raw material, ingested in filename order
      02-followup-notes.md      (must match NN-*.txt or NN-*.md)
      .ingested                 machine-written ledger — do not edit or commit
```

## `source.json`

Exactly the fields `POST /api/v1/admin/local/sources` accepts. `name` is
required and is the find-or-create match key (exact match — don't rename a
source between runs unless you mean to create a new one).

```json
{
  "name": "Maria Papadopoulos",
  "bio": "Third-generation baker in Pangrati.",
  "photo_url": "",
  "location": "Athens, Greece",
  "expertise": "Bakeries, tavernas, Pangrati neighborhood",
  "credibility": "Runs Fournos Maria since 1998; featured in local press.",
  "consent_ref": "consent/2026-07-01-maria.pdf"
}
```

All fields except `name` are optional — omit them or leave them empty.

## Material files

Plain text or markdown. The whole file is submitted as raw research text for
AI extraction, except an optional **first line**:

```
kind: transcript
```

Accepted kinds: `transcript`, `notes`, `voice_memo` (default: `notes`). The
header line is stripped before submission.

## Running

```bash
# whole corpus against the local dev stack
SEED_EMAIL=admin@example.com SEED_PASSWORD=... make seed-local

# one city, pre-issued token, other environment
BASE_URL=https://your-host SEED_TOKEN=... CITY=athens ./scripts/seed_local_content.sh
```

- Re-runs skip anything already in a `.ingested` ledger (content-hash based:
  editing a file re-ingests it as new drafts; renaming does not).
- The **target server** needs `ANTHROPIC_API_KEY` and `GOOGLE_PLACES_API_KEY`
  live — extraction and place-verification happen server-side.
- Seeding creates **drafts only**. Curation and publishing stay human, and
  pins without verified coordinates remain unpublishable (anti-hallucination
  gate).
- `_example/` is a fictional fixture city used by tests. Underscore-prefixed
  city folders are skipped unless explicitly targeted with `CITY=_example`.
