# Plan: Chat Polish

> **HOW.** Flutter-side plus one small Go change (the separator's
> server-side half). See `spec.md` for what/why.

## Technical Approach

Five independent fixes inside the existing chat architecture, respecting its
two invariants: the `_ChatTail` narrow-select rule (every tail leaf watches a
narrow Riverpod select so the 48ms token flush rebuilds only the streaming
bubble) and whole-list state replacement. `ChatPanel` is shared by two hosts
(AgentScreen and the trip-refine panel), so everything lands in the shared
widgets/provider and works in both.

## Flutter Changes

`src/packages/flutter-app/lib/`:

- **Typing indicator** (`widgets/chat_panel.dart`): new `_TypingIndicatorBubble`
  leaf in `_ChatTail` (between `_CompactingChip` and `_StreamingBubble`)
  watching one derived bool — `isStreaming && streamingText empty/null &&
  activeTools.isEmpty && !isCompacting`. `isStreaming` flips synchronously in
  `_sendNow`, so the indicator appears the instant of send with no server
  event needed; the same condition covers post-tool silent gaps.
  `_TypingDotsBubble` holds one repeating `AnimationController` (lifecycle =
  tree presence, the `_StreamingCursor` pattern) driving three staggered dots.
- **Separator fix** (`providers/plan_provider.dart` `_sendNow`): a turn-local
  `needsSeparator` flag set on `tool_call`/`tool_result` when the text buffer
  is non-empty; the next non-empty `text_delta` prepends `\n\n` unless a
  newline already sits on either side of the boundary (a plain space does NOT
  suppress it). Applied at buffer-append time so the 48ms flush, the mid-turn
  error commit, and the final commit all inherit it unchanged.
- **Single CTA** (`screens/agent_screen.dart` `_ItineraryBanner`): the
  saved-trip branch renders only the "View trip" `FilledButton`; the
  route-planner `OutlinedButton` is removed. The anonymous branch (and
  `_loadIntoPlanner`) is untouched.
- **Bubble width cap** (`widgets/chat_panel.dart`): shared
  `_bubbleMaxWidth(context) = min(width * 0.78, 720)` used by
  `ChatMessageBubble` and `_QueuedBubble`.
- **l10n** (`widgets/result_summary_chip.dart` + `lib/l10n/*.arb`): new key
  `resultChipViewInTrip` (en "View in trip" / es "Ver en el viaje") replaces
  the hardcoded literal; key `agentScreenLoadIntoRoutePlanner` deleted from
  both ARBs (only reference was the removed button). Regenerate with
  `flutter gen-l10n` (generated files are committed).

## Go API Changes

`src/packages/api/plan_handler.go`: the agent loop marks `turnNeedsSeparator`
when an iteration ends in tool calls with text already streamed; the next
text delta is prefixed with `\n\n` (same newline-skip rule as the client) in
BOTH the SSE `text_delta` and the `turnText` accumulation that the deferred
`plan_chat_sessions` upsert persists. Streamed == persisted == rendered; the
client mirror rule sees the emitted newline and doesn't double it, and still
covers older servers. Test harness: `fake_anthropic_test.go` gains
`textThenToolTurn` (text block + tool_use block in one assistant turn);
`plan_separator_integration_test.go` pins the streamed and persisted text.

## Contract Parity

No schema/contract changes (the `text_delta` payload shape is unchanged).

## Tests

- `test/plan_provider_separator_test.dart` — insertion rules (tool boundary,
  model-supplied newline, plain leading space, tool-first turn, consecutive
  pairs, mid-turn error commit) plus real flush timing.
- `test/chat_panel_typing_indicator_test.dart` — visible at send before any
  SSE event, gone at first token, yields to tool/compacting chips, returns in
  the post-tool gap (parkable staged fake service).
- `test/agent_screen_banner_test.dart` — saved trip → only "View trip";
  anonymous → only "Load into Planner". Seeds a non-empty transcript (the
  empty-state gate otherwise swallows the footer).
- `test/chat_panel_bubble_width_test.dart` — 720 cap wide / 78% narrow, plus
  the es label spot-check.
