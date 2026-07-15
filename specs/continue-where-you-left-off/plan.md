# Plan: Continue Where You Left Off

> HOW. See `spec.md` for what & why.

## Technical Approach

Persist each authenticated, non-trip-bound plan conversation as **one row**
(`plan_chat_sessions`) keyed `(user_id, chat_id)`, upserted twice per turn:
synchronously at turn start (the user's message survives an immediate stream
death) and via `defer` at turn end (appends the accumulated assistant text —
the same text the client commits, including its error path). The transcript is
stored as the client-format wire history (`[{role, content}]` JSONB) plus the
compaction `summary`, which together are exactly what a live client would
resend — so a resumed conversation is indistinguishable from one that never
left.

Key decisions:
- **Graduation is a read-time `NOT EXISTS` against `trips.chat_id`**, not a
  status flag: no coupling to `persistTrip`, no race with the turn continuing
  after `create_itinerary`, and abandoned refine chats (which reuse a trip's
  `chat_id`) are excluded for free.
- **Trip-bound sessions (`trip_id` set) are never persisted** — they patch a
  trip in place; nothing to continue.
- **Compaction-aware persistence:** the handler snapshots `req.Messages` /
  `req.Summary` before the compaction block mutates them; if compaction
  succeeds this turn, the compacted messages + new summary are persisted
  (matching the client's post-`compacted` wire state), otherwise the
  originals are (never the summary-as-message prepend, which would duplicate
  context on resume).
- **Dismiss is a hard DELETE** — a still-live client legitimately recreates
  the row on its next turn.

## Go API Changes

- **Migration** `migrations/00031_plan_chat_sessions.sql`: table above +
  `(user_id, updated_at DESC)` index + `UNIQUE (user_id, chat_id)`.
- **Queries** `query/chat_sessions.sql` → `make api-sqlc`:
  `UpsertPlanChatSession`, `ListResumablePlanChatSessions` (summary columns
  only, `NOT EXISTS` trips filter, `LIMIT 10`), `GetPlanChatSessionByChatID`,
  `DeletePlanChatSession :execrows`, `DeleteStalePlanChatSessions` (60 days,
  called opportunistically from the list handler).
- **Handlers** `chat_session_handler.go`: `savePlanChatSession` (best-effort,
  log-and-swallow), `listChatSessionsHandler`, `getChatSessionHandler`,
  `deleteChatSessionHandler`.
- **Hook** in `plan_handler.go`: gate
  `authed && dbPool != nil && chat_id != "" && boundTripID == nil`; start
  upsert + deferred end upsert (`context.Background()`); `turnText`
  accumulation beside the `text_delta` send.
- **Routes** in `main.go` behind `authMiddleware`: `GET /chats`,
  `GET /chats/{chatId}`, `DELETE /chats/{chatId}` + startup log lines.

## Flutter Changes

- **Model** `models/chat_session.dart`: `ChatSessionSummary`,
  `ChatSessionMessage`, `ChatSessionDetail` (+ `make flutter-build-models`).
- **Service** `services/chats_api_service.dart`: `listResumableChats()`,
  `getChat(chatId)`, `dismissChat(chatId)`.
- **Provider** `providers/resumable_chats_provider.dart`: `FutureProvider`,
  `[]` when signed out; UI reads `valueOrNull` (fail quiet).
- **Hydration** `providers/plan_provider.dart`:
  `resumeConversation({chatId, messages, summary})` — resets, restores
  `_chatId`, messages, and `compactedSummary` (with `compactedCount: 0`).
- **UI** `screens/trips_list_screen.dart`: "Continue where you left off"
  section above trip cards; entries tap-to-resume (fetch detail → hydrate →
  switch to Plan tab) with dismiss; refresh on pull-to-refresh, dismiss,
  resume, and on `savedTripId` changes.

## Contract Parity

| JSON key | Go type | Dart type | Nullable? | ✓ |
|----------|---------|-----------|-----------|---|
| `chat_id` | `string` | `String` | no | ✓ |
| `title` | `string` | `String` | no | ✓ |
| `preview` | `string` | `String` | no | ✓ |
| `message_count` | `int` | `int` | no | ✓ |
| `created_at` / `updated_at` | `time.Time` | `DateTime` | no | ✓ |
| `messages[].role` / `.content` | `string` | `String` | no | ✓ |
| `summary` | `string` | `String?` (defaults '') | no | ✓ |

## Cross-cutting

- No new env vars. No CORS changes (same-origin gateway). Degraded mode: the
  persistence gate skips when `dbPool == nil`; `/chats` 503s via
  `authMiddleware`'s existing nil-pool check and the UI fails quiet.

## Verification

- `make api-fmt && make api-vet`; `go test ./...` in `src/packages/api`.
- `make flutter-build-models` → `make flutter-analyze` → `make flutter-test`.
- Manual via gateway (`make docker-dev`, API image rebuild): send one authed
  plan message → `GET /api/v1/chats` lists it; resume in UI restores the
  transcript; drive to `create_itinerary` → entry gone; DELETE → 204;
  anonymous/degraded → no section, no errors.
