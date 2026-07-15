# Plan: Flight Connectivity Check

> **HOW.** See `spec.md` for what/why. Repo conventions: `../../CLAUDE.md`.

## Technical Approach

One new agent tool, `check_flight_connectivity`, in the `/plan` tool registry.
A dedicated fan-out tool (not prompt-only reuse of `search_flights`) because:
one agent iteration instead of N, a compact indicative summary instead of N
ranked-offer payloads re-sent every iteration, no `flights` SSE card spam
(the Flutter provider has a single flight-offers slot that N searches would
clobber), and per-leg cacheability. Results are *indicative* (mins across raw
offers — cheapest, fastest, min stops may be different offers), so unlike
bookable offers they are safe to cache briefly.

## Go API Changes

`src/packages/api/`:

- **`duffel_service.go`:** add `SupplierTimeoutMS int` (`json:"-"`) to
  `FlightSearchRequest`; when set, append `&supplier_timeout=<ms>` to the
  `POST /air/offer_requests?return_offers=true` path. Keeps the public
  `/flights/search` request shape unchanged.
- **`plan_connectivity.go` (new):** tool definition + dispatcher.
  - Constants: max 5 candidates, max 3 calls/session, concurrency 5,
    30s overall tool deadline (`var` for tests), 10s Duffel supplier timeout.
  - `connectivityCache = newTTLCache[legConnectivity](45min, 2000)` keyed
    `ORIG|DEST|YYYY-MM-DD` (per leg, so overlapping candidate sets hit).
  - Dispatcher: session cap → truncate candidates → resolve IATAs via
    existing `resolveIATA` (24h-cached) → deduped leg list (origin→candidate,
    candidate→onward; skip degenerate) → semaphore-bounded fan-out of
    `duffelService.SearchFlightOffers` under `context.WithTimeout` → reduce
    to `legConnectivity{Cheapest, Currency, FastestMin, MinStops, OfferCount}`
    → `summarizeOffers`-style compact text. Partial results: timed-out legs
    report "timed out — connectivity unknown"; `isError=true` only when every
    leg failed. Workers never write SSE (`s.w` stays on the handler goroutine).
- **`plan_tool_registry.go`:** `connectivityCalls int` on `planSession`;
  registry entry inserted directly after `searchFlightsTool` (one-time
  prompt-cache invalidation, shipped together with the prompt edits);
  `searchFlightsTool` description gains a pointer to the new tool for
  multi-candidate comparisons.
- **`plan_handler.go`:** `basePrompt` gains the check-before-recommending +
  warn-on-traveler-proposed-stopover rule. `planMaxIterations` unchanged —
  the whole comparison is one iteration.

## Flutter Changes

`src/packages/flutter-app/lib/`:

- **`widgets/chat_panel.dart`:** `_toolLabel` case for
  `check_flight_connectivity` → "Checking route connectivity...". Nothing
  else: no new SSE event in v1 (unknown event types are already ignored, so a
  comparison card can be added later without breaking older clients).

## Contract Parity  ← anti-drift gate

No new JSON crosses the API↔Flutter boundary (tool results are text inside
the existing SSE `tool_result` event; `FlightSearchRequest.SupplierTimeoutMS`
is `json:"-"`). No Dart models or codegen.

| JSON key | Go type | Dart type | Nullable? | ✓ |
|----------|---------|-----------|-----------|---|
| — (none) | — | — | — | ✓ |

## Cross-cutting

- **Env vars:** none new (reuses `DUFFEL_ACCESS_TOKEN` / `DUFFEL_BASE_URL`).
- **Cost guardrails:** ≤30 Duffel offer requests per session worst case
  (5 candidates × 2 legs × 3 calls), dampened by the 45-min leg cache;
  `supplier_timeout=10000` keeps individual searches snappy.

## Verification

- `make api-fmt && make api-vet` clean; `go test ./...` in `src/packages/api`.
- Unit: reduction math, fan-out dedup + supplier_timeout propagation, partial
  timeout, candidate/session caps, cache hits, unresolvable candidates —
  against a path-aware stub `DuffelService` (pattern from
  `duffel_service_test.go`).
- Integration: fake-Anthropic harness scripts a `check_flight_connectivity`
  turn; assert `tool_call`/`tool_result` SSE events, **no** `flights` event,
  and the summary text reaches the model's next request.
- Manual: `make api-run` with the Duffel sandbox; prompt "I'm in San Andrés
  and need to get to Burlington VT — any nice island stopover on the way?";
  confirm the check runs, the reply discloses price/duration tradeoffs, and
  the chip label shows in chat.
