# Spec: Free-Cap Soft Instrumentation

> **WHAT & WHY only.** No tech choices, file names, libraries, or code. If a
> sentence names a file or a package, it belongs in `plan.md`, not here.

## Context

`docs/business-model.md` §7 gates Phase 3 (the paid tier) on "a measured
cohort actually hitting the free caps" — but no cap exists anywhere in the
product, so the trigger condition is currently unmeasurable. This feature
adds **measurement only**: the placeholder caps from §4 (~20 AI planning
sessions/month, 3 active trips) become counters that record a
`free_cap_would_hit` analytics event at the moment a signed-in user *would
have* been stopped if the caps were enforced. **Nothing is enforced. No
paywall. No request is ever rejected, slowed, or altered by this feature —
if any part of the measurement fails, the request proceeds exactly as
before (fail-open).** The output is the §8 "cap-hit rate" metric on the
admin dashboard: how many would-hit events fired and how many distinct
users they touched, per cap kind — the demand signal Phase-3 pricing will
be read off of.

## User Stories

- As the **operator**, I want to see how many users would hit the free caps
  so that I can decide when (and at what limits) to launch the paid tier.
- As the **operator**, I want the caps to be tunable via configuration so
  that I can test lower thresholds and recalibrate the placeholder numbers
  from usage data without a deploy.
- As a **traveler** (free or otherwise), I want zero behavior change: my
  planning sessions and trips work identically whether or not I am past any
  cap, and identically when the measurement layer is broken.

## Cap Semantics (normative)

Two cap kinds are measured. Both apply to **signed-in users only** —
anonymous planning sessions carry no durable identity, so no per-user count
is meaningful (and anonymous users can't be converted to a paid tier
anyway).

### `plan_runs` — AI planning sessions per month

- **Cap:** `FREE_PLAN_SESSIONS_PER_MONTH`, default **20** (the §4
  placeholder). Read from the environment at evaluation time, so tests and
  ops can lower it without a restart-order dependency.
- **Window:** trailing 30 days (rolling), not calendar month. "Per month"
  in the tier table is a marketing phrasing; a rolling window avoids
  month-boundary cliffs and is what a future enforcement layer would want.
- **Counted unit:** one `plan_session_started` event by that user inside
  the window.
- **Crossing rule (only-on-crossing):** when a signed-in session starts,
  count the user's *prior* `plan_session_started` events in the window —
  i.e. the count is taken **before** this session's own start event is
  recorded, so the session being started is not part of its own count.
  Emit `free_cap_would_hit` **iff that prior count equals the cap
  exactly**. In other words: sessions 1..cap are free; the (cap+1)-th
  session in a window is the first that would have been blocked, and it is
  the *only* one that emits. Sessions cap+2, cap+3, … see a prior count
  greater than the cap and emit nothing.

### `active_trips` — concurrently saved trips

- **Cap:** `FREE_ACTIVE_TRIPS`, default **3** (the §4 placeholder). Read
  from the environment at evaluation time.
- **Counted unit:** one trip *lineage* — the same grouping My Trips uses,
  where repeated refinements of one conversation collapse to a single trip
  with versions. Saving a new **version** of an existing trip does not
  increase the count and can never emit. All saved trips count as active
  (there is no archived state today; if one is added, archived lineages
  leave the count).
- **Crossing rule (only-on-crossing):** after a trip is successfully
  created (a brand-new lineage — via the planning agent finalizing an
  itinerary, or via duplicating a shared trip), count the owner's distinct
  lineages. Emit `free_cap_would_hit` **iff the post-creation count equals
  cap + 1 exactly** — the creation that takes the user from "at the cap" to
  "one past it". A user already far past the cap (e.g. crossed while the
  database was down, or before this feature shipped) emits nothing on
  their next creation: the crossing was missed, not deferred.

### Why only-on-crossing

The dashboard reports raw would-hit event counts. If every over-cap session
or trip creation emitted an event, a single power user running 40 sessions
in a month would register 20 events and dominate the count — the metric
would measure *usage past the cap*, not *users encountering the cap*.
Emitting only at the crossing makes each event mean "one user, one moment
of would-have-been-blocked", so the event count approximates crossing
moments and the distinct-user count approximates the cohort size. Both
numbers are surfaced; distinct-users-affected is the primary Phase-3
signal.

**Re-crossing is a new crossing.** The plan-runs window rolls, so a user
can drop back under the cap next month and cross again — that emits again,
correctly: recurring monthly pressure is a stronger demand signal than a
one-time spike. Likewise a user who deletes trips below the cap and later
creates past it again emits again. At most one event fires per crossing.

## Accuracy Model (accepted limitations)

- **Counting off the analytics event log undercounts in degraded mode.**
  Plan-run counts derive from the same best-effort analytics stream that
  powers the rest of the dashboard: when the database is unavailable,
  sessions happen but no events are recorded, and those sessions are
  invisible to the cap counter forever. This is acceptable — the feature is
  a *demand signal*, not a billing meter. A systematic undercount makes the
  signal conservative (we see *at least* this much cap pressure), which is
  the safe direction for a launch-the-paid-tier trigger.
- **Concurrent session starts can race.** Two simultaneous sessions by the
  same user may both observe the same prior count and double-emit, or
  straddle the threshold and emit nothing. No locking is added; the
  distinct-user number is unaffected either way and the event count is
  approximate by design.
- **Future strict metering path.** If enforcement ever ships, counting off
  the event log is not good enough (fail-open + undercount = free
  overage). The upgrade path is a dedicated `usage_counters` table —
  per-user, per-cap-kind, per-window running counters incremented
  transactionally with the counted action (session start committed with
  the counter; trip insert and counter in one transaction) — at which
  point the counter becomes authoritative, the crossing check reads it,
  and enforcement can fail-closed. The event schema defined here is
  deliberately independent of how the count is produced, so that migration
  changes no dashboards.

## Event Schema (normative)

**`free_cap_would_hit`** — recorded **server-side only**. It must never be
accepted from the client event-reporting endpoint (clients could otherwise
spoof demand); the client event whitelist is unchanged.

| Field | Meaning |
|---|---|
| user id | The signed-in user who crossed. Never null — anonymous flows never emit. |
| trip id | For `active_trips`: the trip whose creation crossed the line. Absent for `plan_runs`. |
| `metadata.cap_kind` | `"plan_runs"` or `"active_trips"`. |
| `metadata.count` | The count that crossed: for `plan_runs` the ordinal of the crossing session (prior count + 1 = cap + 1); for `active_trips` the post-creation lineage count (= cap + 1). Recording cap+1 rather than the cap makes each event self-describing about the threshold in force when it fired, even after the env var changes. |

## Configuration

| Variable | Default | Meaning |
|---|---|---|
| `FREE_PLAN_SESSIONS_PER_MONTH` | 20 | plan_runs cap; trailing-30-day window. |
| `FREE_ACTIVE_TRIPS` | 3 | active_trips cap (distinct lineages). |

Both are read at evaluation time (per check, not at boot), must be positive
integers, and fall back to the default when unset or invalid. Changing them
changes only *future* crossing decisions; recorded events keep the `count`
they fired with.

## API Surface

### `GET /api/v1/admin/metrics?days=` (existing endpoint, two new fields)

- **Purpose:** surface the §8 cap-hit rate next to the existing funnel
  numbers.
- **Response additions:**
  - `free_cap_would_hits` — map of cap kind → number of would-hit events in
    the window (crossings observed).
  - `free_cap_users_affected` — map of cap kind → distinct users who
    emitted at least one would-hit event in the window (the cohort size;
    the primary Phase-3 trigger number).
- Both maps are empty (not absent) when no events exist. Admin-only, as
  before.

### Rider: outbound AI base-URL override

The two places the backend constructs an Anthropic client (the planning
agent and the admin local-content ingest) honor an optional
`ANTHROPIC_BASE_URL` environment variable redirecting API traffic. Unset ⇒
behavior identical to today. This is the seam a fake-AI end-to-end test
harness needs (and what this feature's own integration test uses to drive a
real planning session without external calls).

## Data Model

No schema change. `free_cap_would_hit` rows live in the existing analytics
event log alongside every other event type.

## UI Behavior

- **Admin metrics dashboard**, AI-planning section, next to the agent-loop
  cap-hits tile: one tile per cap kind showing would-hit crossings with the
  distinct-users-affected as the caption. Zero states show 0 (the number
  being reliably zero is itself the Phase-3 answer "not yet").

## Edge Cases & Error States

- **Database unavailable (degraded mode):** no counting, no recording, no
  logging noise beyond the standard analytics drop; the request proceeds.
- **Count query fails:** treated as "no crossing"; request proceeds.
- **Anonymous session:** skipped entirely — no count query is issued.
- **Env var set to 0, negative, or garbage:** default applies.
- **Version save vs new trip:** a new version of an existing lineage never
  changes the active-trip count and never emits.
- **Hot path:** the plan-session check adds at most one count query, and it
  runs off the request path (fire-and-forget alongside the existing session
  instrumentation) — a slow analytics database cannot delay first-token
  time.

## Out of Scope

- **Any enforcement, throttling, messaging, or paywall UI.** No user-facing
  surface changes for non-admins.
- Anonymous-user cap measurement (no durable identity).
- Places/Duffel/Ticketmaster quota measurement (COGS metering is separate).
- The `usage_counters` strict-metering table (documented above as the
  upgrade path; built only if enforcement is decided).
- Backfilling crossings that happened before this shipped.

## Open Questions

- None blocking. The cap defaults remain the §4 placeholders on purpose —
  this feature exists to produce the data that replaces them.
