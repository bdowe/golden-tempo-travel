# Spec: Flight Connectivity Check

> **WHAT & WHY only.** Tech details live in `plan.md`.

## Context

The AI planning agent recommends destinations and stopovers without checking
whether reasonable flights exist. On a real trip (San Andrés, Colombia →
Burlington, VT) it suggested Bermuda and the Bahamas as interim stops — routes
that are ~22 hours with layovers or $4–5k when a sensible hop should cost
$500–600. Travelers trust the agent's suggestions; a suggestion that is
practically unreachable erodes that trust and wastes planning time. The agent
should verify flight feasibility (price, duration, stops) *before* recommending
where to go, prefer well-connected options, and disclose the tradeoff plainly
when a poorly connected place is still worth suggesting.

## User Stories

- As a **traveler asking for routing ideas**, I want the agent's suggested
  stopovers to be places I can actually fly to at sane cost and duration, so
  that I don't build a plan around an impractical hop.
- As a **traveler who proposes my own stopover**, I want the agent to warn me
  early if that route is unusually long or expensive, so I can reconsider
  before falling in love with the idea.
- As a **traveler comparing candidate destinations**, I want the agent to
  weigh real connectivity (price / time / nonstop availability) across the
  options in one pass, so its recommendation reflects reality, not vibes.

## Acceptance Criteria

- [ ] When the agent is about to suggest a destination or stopover the
      traveler didn't name, it first checks flight connectivity for its
      candidates and prefers well-connected ones.
- [ ] When the agent still suggests (or the traveler proposes) a poorly
      connected place, the agent states the typical price and total travel
      time plainly in its reply.
- [ ] Comparing several candidates costs one agent step and does not flood the
      chat with flight-offer cards; the comparison appears in the agent's
      prose.
- [ ] While the check runs, the chat shows a "checking route connectivity"
      activity indicator (same treatment as other agent tools).
- [ ] Connectivity numbers are presented as indicative; the agent still runs a
      real flight search on the chosen destination for bookable options.
- [ ] If some routes can't be checked in time, the agent gets whatever
      completed plus a clear "unknown" marker for the rest — a slow provider
      never kills the whole comparison.

## API Surface

No new public REST endpoint. The capability is a new internal agent tool on
the existing `POST /api/v1/plan` SSE stream:

### Agent tool `check_flight_connectivity`
- **Purpose:** compare indicative flight connectivity for 2–5 candidate
  destinations from an origin (and optionally each candidate → an onward
  destination, for stopover comparisons) in a single call.
- **Request (tool input):** `origin` (city or IATA), `candidates` (2–5 city
  names or IATA codes), `depart_date` (YYYY-MM-DD; a representative date when
  the traveler has no fixed dates), `onward_destination` (optional).
- **Response (tool result):** compact per-candidate summary — cheapest price,
  fastest total duration, minimum stops / nonstop availability per leg —
  plus rows for unresolvable places and timed-out legs.
- **Errors:** the tool only fails outright when nothing could be checked
  (bad origin, or every leg failed); partial results are a success.

## Data Model

Nothing persisted. Per-leg connectivity summaries are cached in memory for a
short window (they are indicative, unlike bookable offers which are never
cached).

## UI Behavior

- **Surface:** the existing plan chat. No new cards in v1.
- **Happy path:** traveler asks for routing ideas → tool-activity chip shows
  "Checking route connectivity..." → agent's reply compares candidates with
  real numbers and recommends accordingly.
- **States:** the generic tool chip covers loading; results/errors surface in
  the agent's prose.

## Edge Cases & Error States

- Unresolvable place name → named as unresolvable in the summary; the rest of
  the comparison proceeds.
- Flight provider slow/down → per-leg timeout markers; total wall-clock is
  bounded so the SSE stream stays responsive.
- No service on a route for the date → reported as "no flights found"
  (itself a strong connectivity signal).
- More than 5 candidates → truncated to 5, noted in the result.
- Runaway tool use → per-session call cap with a friendly "decide with what
  you have" message.

## Out of Scope

- A visual comparison card/chip in chat (forward-compatible; may come later).
- Multi-date or flexible-date connectivity scanning.
- Ground/ferry connectivity (Rome2Rio links and `suggest_ferries` already
  cover those modes).
- Changing how `search_flights` presents bookable offers.

## Open Questions

None — UI treatment (minimal v1) and scope (agent suggestions + warnings on
traveler-proposed stops) were decided with the product owner on 2026-07-14.
