# Plan: Refine Panel Polish

> **HOW.** See `spec.md`. Flutter-only; no Go, endpoint, model-codegen, or env
> changes. Builds directly on the chat-streaming-polish architecture (keyed
> ListView.builder + `_ChatTail` leaf selects in `chat_panel.dart`).

## Technical Approach

Three fixes, all client-side:

1. **Silent in-place refresh.** `trip_updated` currently routes to `_load()`,
   which flips `_loading = true` and swaps the whole screen for a spinner,
   unmounting the streaming chat. Add `_load({bool silent})` — when silent and
   a trip is already displayed, skip the loading/error setStates and swallow
   fetch errors (stale trip stays). New `_refresh()` coalesces bursts with a
   trailing re-run (a `trip_updated` landing mid-fetch queues exactly one more
   pass) and is shared by the panel listener and `RefreshIndicator`.
2. **Seed context chip.** `PlanMessage` gains a UI-only `displayLabel`;
   `sendMessage`/`beginSectionRefinement` thread it through. ChatPanel renders
   labeled messages as a centered `_SeedContextChip` instead of a bubble. The
   server history maps `m.content`, so the full seed still reaches the model.
3. **"Itinerary updated" chip.** New `PlanState.tripUpdatedThisTurn` mirroring
   the `profileUpdateNote` lifecycle (reset on send, set on `trip_updated`);
   rendered by a `_ItineraryUpdatedChip` leaf in `_ChatTail`. Not keyed on
   `tripUpdateCount` — that counter is monotonic and must never reset.

## Go API Changes

None.

## Flutter Changes

- `lib/models/plan_message.dart` — add `displayLabel` (plain in-memory class,
  no codegen).
- `lib/providers/plan_provider.dart` — `sendMessage`/`beginSectionRefinement`
  `displayLabel` params; `tripUpdatedThisTurn` state.
- `lib/widgets/chat_panel.dart` — `_SeedContextChip` branch in itemBuilder;
  `_ItineraryUpdatedChip` in `_ChatTail`.
- `lib/screens/trip_detail_screen.dart` — `_load(silent:)`, `_refresh()`,
  rewire `onTripUpdated` and `RefreshIndicator`, pass the seed displayLabel.
- `lib/widgets/trip_refine_panel.dart` — unchanged.

## Contract Parity

| JSON key | Go type | Dart type | Nullable? | ✓ |
|----------|---------|-----------|-----------|---|
| _(none — no contract changes)_ | | | | ✓ |

## Cross-cutting

None (no env vars, routes, or gateway changes).

## Verification

- `make flutter-analyze`, `make flutter-test` (extended stream test + two new
  widget tests).
- Manual via `make docker-dev` → `http://localhost:3000` (restart flutter
  container + hard refresh): walk the acceptance criteria in `spec.md` on wide
  and narrow layouts.
