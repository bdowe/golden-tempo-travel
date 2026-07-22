# Plan: Chat Quick Replies

> **HOW.** See `spec.md` for what/why. Server-driven via a registry tail
> tool; chips are transient client state.

## Technical Approach

A `suggest_replies` agent tool at the tail of the `/plan` tool registry (the
`suggest_stays` client-only-emit template: no DB, no gate, `sendSSE` + short
ack), plus a standing basePrompt instruction to call it last in turns that
ask a question. The Flutter provider stores the list in
`PlanState.suggestedReplies` (whole-list replacement); a `_QuickReplyChips`
leaf in the chat tail renders `ActionChip`s once the stream settles. Chip
text is model-generated in the conversation language, so display == sent and
no ARB keys are needed. Costs one extra (cached-prefix) agent-loop iteration
per suggesting turn; degrades to nothing if the model skips the call.

## Go API Changes

`src/packages/api/`:

- **`plan_tool_registry.go`** — `suggestRepliesTool` def (`replies`: array of
  2–4 strings); ungated tail entry APPENDED after `set_travel_mode`
  (prompt-cache append-only rule; ungated so all three session shapes stay
  pure appends); `runSuggestRepliesTool` dispatcher +
  `sanitizeQuickReplies` (trim, drop empty/oversized(>80 runes)/duplicate,
  cap 4; drop, never truncate). Fewer than 2 usable replies → `is_error`
  tool_result, no SSE. `planSession.itineraryEmitted` (set beside the `done`
  and `trip_updated` emits) makes `suggest_replies` refuse after an
  itinerary in the same turn. `noResultEvent` stays false: `tool_call` is emitted
  unconditionally, so suppressing only `tool_result` would strand a stale
  client's spinner chip; back-to-back call/result is invisible.
- **`plan_handler.go`** — basePrompt gains the behavioral instruction
  (call after question turns, ≤once per reply, last, never with
  create_itinerary/update_itinerary_section, same language as the reply),
  inserted before the closing formatting sentence so
  `TestSystemPromptEnglishUnchanged`'s suffix pin and the
  Spanish-is-English-plus-suffix property both hold. One-time prompt-cache
  re-warm on deploy, accepted.
- **Tests** — order test (`plan_tool_registry_test.go`) three `want` slices;
  tail guard (`plan_integration_test.go`) now expects `suggest_replies`;
  language test gains a `Contains("call suggest_replies")` pin;
  `plan_quick_replies_integration_test.go`: emit+sanitize+ack+tail,
  all-invalid → is_error, duplicate calls pass through, sanitizer unit test.

## Flutter Changes

`src/packages/flutter-app/lib/`:

- **`providers/plan_provider.dart`** — `PlanState.suggestedReplies`
  (`List<String>`, default `const []`, mirrors `activeTools`); cleared in the
  `_sendNow` reset (covers typed send, chip tap, queue drain, retry,
  refinement seeds), the `error` case, the transport `catch`, and the
  `done`/`trip_updated` cases (a turn-local `itineraryThisTurn` flag also
  drops a later `suggest_replies` in the same turn — the banner owns
  itinerary turns in either event order); new `suggest_replies` case
  replaces the list whole (last-write-wins); the `tool_call` case skips
  `suggest_replies` for `activeTools` (no spinner). A `_turn` generation
  counter makes a stream loop superseded by `reset()` self-terminate, so
  late events never leak into a fresh conversation.
- **`widgets/chat_panel.dart`** — `_QuickReplyChips` leaf in `_ChatTail`
  between `_ResultChips` and `_ChatFooter`; narrow record select
  `(replies, isStreaming, hasQueue)`; hidden when empty/streaming/queued;
  `ActionChip` wrap (the `_SuggestionChip` pattern); tap →
  `sendMessage(reply)` verbatim. Works under both hosts via the injected
  listenables.

## Contract Parity

| JSON key | Go type (event payload) | Dart type | Nullable? | ✓ |
|----------|------------------------|-----------|-----------|---|
| replies  | `[]string`             | `List<String>` | no (empty = none) | ✓ |

## Tests

`test/chat_panel_quick_replies_test.dart` — provider: populate/overwrite
(identity-replaced), next-send clears, error clears, never in activeTools;
widget: settled turn shows chips + tap sends verbatim and clears, hidden
while streaming, hidden with a queued follow-up, works under a
trip-refine-shaped host.
