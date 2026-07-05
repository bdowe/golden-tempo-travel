# Plan: Chat Streaming Polish

> **HOW.** See `spec.md` for what & why. No new endpoints, models, or env vars —
> this is a rendering/state-flow change in the Flutter chat plus prompt wording
> in the Go API.

## Technical Approach

Three root causes, three fixes:

1. **Per-token full rebuilds** — every SSE `text_delta` did a whole-state
   `copyWith` and `ChatPanel` watched the whole `PlanState`, rebuilding the
   entire conversation per token. Fix: coalesce delta flushes in `PlanNotifier`
   (~48ms one-shot timer), and restructure `ChatPanel` so committed messages
   live in a `ListView.builder` with keys and the live tail (streaming bubble,
   tool chips, result chips, footer) is a column of leaf widgets each watching
   a narrow `select`.
2. **Scroll fighting** — a fresh 200ms `animateTo` per token. Fix: a single
   pending post-frame `jumpTo(maxScrollExtent)` gated by a bool, triggered by
   selects on `streamingText` / `messages.length`.
3. **Raw markdown + card pile-up** — assistant text rendered as plain `Text`;
   five card sections inserted mid-stream. Fix: render assistant bubbles with
   `gpt_markdown` (streaming-oriented flutter_markdown successor), replace the
   in-bubble spinner with a blinking cursor, and replace the card sections with
   one generic `ResultSummaryChip` per result set that links to trip detail
   when a trip id exists.

## Go API Changes

`src/packages/api/plan_handler.go` only — prompt wording:

- Base prompt: drop "shown to the traveler as cards"; instruct summarizing the
  top 2–3 flight options in prose. Add one line asking for light markdown
  (short paragraphs, bold place names, hyphen lists, no headings/tables).
- `summarizeOffers` / `summarizeEvents` tool-result texts (and the nearby
  comment): stop pointing at chat cards; the full list is saved with the trip.

## Flutter Changes

`src/packages/flutter-app/`:

- **pubspec.yaml:** add `gpt_markdown` (transitively pulls `flutter_math_fork`;
  verify web build).
- **providers/plan_provider.dart:** buffer `text_delta` and flush
  `streamingText` on a ~48ms one-shot `Timer`; flush synchronously before
  tool/done/error transitions; cancel the timer *before* the end-of-stream /
  error `copyWith` that clears `streamingText` (a late timer would resurrect a
  ghost bubble) and in `dispose()` (refine-panel family instances dispose
  mid-stream). `PlanState` shape unchanged.
- **widgets/result_summary_chip.dart (new):** generic
  `{icon, accent, label, onTap?}` one-line chip; tappable variant shows
  "View in trip".
- **widgets/chat_panel.dart:** `ListView.builder` + keyed bubbles + `_ChatTail`
  leaf widgets with per-field selects; delete `_FlightOptions`,
  `_EventOptions`, `_LocalRecsSection`, `_FerryOptions`, inline
  `SourceLinksCard`; add `onViewTrip` callback param; scroll fix; markdown
  bubbles + `_StreamingCursor`.
- **screens/agent_screen.dart:** pass `onViewTrip` → push `TripDetailScreen`.
- **Untouched:** `trip_refine_panel.dart`, `trip_detail_screen.dart`, all card
  widget files (still used by flight search / trip detail).

## Contract Parity

No request/response contract changes — the SSE event shapes are unchanged.

| JSON key | Go type | Dart type | Nullable? | ✓ |
|----------|---------|-----------|-----------|---|
| _(none — no contract changes)_ | | | | ✓ |

## Cross-cutting

- No new env vars, routes, or gateway config.
- Chip accents reuse `AppColors.tool*` tokens (design-system conventions).

## Verification

- `make api-fmt && make api-vet` — Go clean.
- `make flutter-analyze` — catches dead imports after card-section removal.
- `make flutter-test` — includes new `test/plan_provider_stream_test.dart`
  (fake `PlanService`: N deltas → far fewer state emissions; committed text
  equals concatenation; no ghost `streamingText` at end).
- Manual via `make docker-dev` → `http://localhost:3000` (API container needs
  `up --build` for the prompt change): walk the acceptance criteria in
  `spec.md` with a flights + Greek-ferries trip ask.
