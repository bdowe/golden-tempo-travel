# Plan: Conversation Compaction

## Technical Approach

Server-side compaction, done once per threshold crossing, with the result
handed back to the client via a new SSE event so subsequent turns send the
compacted form. The server rewrites `req.Messages` in place to
`[summary-as-first-user-message] + last N messages` before the session is
constructed, so everything downstream (Anthropic message building, the profile
distiller reading `s.req.Messages`) works unchanged. The client keeps its full
display transcript and tracks only `(compactedSummary, compactedCount)` used
when projecting the wire history.

Key decisions:
- **Summarizer = one non-streamed forced-tool Haiku 4.5 call**
  (`record_summary`, MaxTokens 1024), mirroring `profile_distiller.go` — no
  preamble to parse, cheap (~$0.01–0.02), 1–3s.
- **Threshold 24 / keep 10**: compaction fires roughly every 6 turns; the kept
  window preserves ~5 verbatim exchanges for local coherence and always
  contains the just-sent user message (makes retry safe by construction).
- **`planMaxMessages` 40 → 60**: now purely a runaway/abuse backstop. Old
  clients that ignore the new events get re-compacted server-side every turn
  between 24 and 60 messages.
- **Failure = proceed uncompacted** and log; never fail a turn the user is
  waiting on. History is ≤ 60 messages so cost stays bounded.
- Compaction *reduces* total spend — the original reason for the cap — because
  a compacted ~13-message history is re-billed across up to 15 agent
  iterations instead of a growing 40+.

## Go API Changes

`src/packages/api/`:

- **New `plan_compactor.go`** (modeled on `profile_distiller.go`):
  - `planCompactThreshold = 24`, `planCompactKeep = 10`,
    `compactTimeout = 30s`, `compactMaxInputChars = 60000`.
  - `summarizePlanConversation(ctx, client, prevSummary, older)` — forced-tool
    Haiku call; system prompt requires preserving dates, cities/order,
    travelers, chosen flights/ferries/stays, budget/pace/constraints, agreed
    vs rejected places, itinerary-created state, open questions; never invent;
    newest state wins; merge `prevSummary`; ≤ ~1,500 chars.
  - `compactPlanMessages(ctx, client, msgs)` →
    `(newMessages, summary, throughIndex, error)`;
    `throughIndex = len(msgs) - planCompactKeep`; reuses the
    `buildDistillationTranscript` flattening with oldest-first trim.
  - Summary rendered as a first user message:
    `"Summary of the conversation so far (earlier messages were removed to
    save space — treat this as established context):\n\n" + summary`;
    defensively rune-truncated to `planMaxMessageChars`.
- **`plan_handler.go`:**
  - `PlanRequest.Summary string` + rune-length validation.
  - `planMaxMessages` → 60; comment block rewritten (threshold = UX lever,
    cap = backstop). Existing guards stay first and unchanged in order.
  - Compaction block runs **before** `session := &planSession{...}` (which
    captures `req` by value — the ordering trap). At/above threshold: emit
    `compacting`, call the compactor under `compactTimeout`; on success
    replace `req.Messages`/`req.Summary` and emit `compacted`; on failure log
    and proceed. Below threshold with a `summary`: just prepend the rendered
    summary message.
  - `plan_session_completed` instrumentation gains `compacted` /
    `compaction_failed` bools.
  - Prompt caching unaffected (only `messages` changes).

## Flutter Changes

`src/packages/flutter-app/lib/`:

- **`services/plan_service.dart`:** `streamPlan` gains `String? summary`;
  body includes `summary` when non-empty. (All test fakes overriding
  `streamPlan` need signature updates.)
- **`providers/plan_provider.dart`:**
  - `PlanState` gains `String? compactedSummary` (sentinel copyWith),
    `int compactedCount` (default 0), `bool isCompacting`. Scalars only —
    no interaction with the chat-panel list invariants. `reset()` clears them.
  - `_sendNow` sends `messages.sublist(compactedCount)` +
    `summary: compactedSummary`.
  - New cases: `compacting` → `isCompacting: true`; `compacted` → store
    summary, `compactedCount += through_index` (clamped), clear
    `isCompacting`. Also clear `isCompacting` on `error` and stream end (the
    server sends no failure event).
- **`widgets/chat_panel.dart`:** transient "Summarizing earlier conversation…"
  chip via a narrow `select` on `isCompacting` (same pattern as tool chips).
- No models/codegen: the wire additions are a plain string field and SSE
  events handled as dynamic maps, like the rest of the plan protocol.

## Contract Parity

| JSON key | Go type | Dart side | Nullable? | ✓ |
|----------|---------|-----------|-----------|---|
| `summary` (request) | `string` (`omitempty` semantics via guard) | `String?` named param | yes | ☑ |
| `compacted.summary` (SSE) | `string` | `event.data['summary'] as String?` | no | ☑ |
| `compacted.through_index` (SSE) | `int` | `(event.data['through_index'] as num?)?.toInt()` | no | ☑ |

## Cross-cutting

- No new env vars; the compactor uses the existing `ANTHROPIC_API_KEY` client
  and the `ANTHROPIC_BASE_URL` test seam.
- No gateway changes (same endpoint).

## Verification

- `make api-fmt && make api-vet`; `cd src/packages/api && go test ./...`
  (fake-Anthropic harness covers the compactor and integration paths).
- `make flutter-analyze && make flutter-test`.
- Cheap live E2E: 25 short scripted messages with a fact buried early; assert
  `compacting`/`compacted` in the SSE stream and recall of the buried fact.
- In-app: temporarily set `planCompactThreshold = 6`, `make docker-dev`
  (API image rebuild), watch the chip and the shrinking request payload.
