-- name: UpsertPlanChatSession :exec
-- Whole-transcript upsert, twice per /plan turn (start + deferred end).
-- title is set once from the opening message and never overwritten, so the
-- entry keeps a stable identity in the continue list.
INSERT INTO plan_chat_sessions (
    user_id, chat_id, title, preview, summary, messages, message_count
) VALUES ($1, $2, $3, $4, $5, $6, $7)
ON CONFLICT (user_id, chat_id) DO UPDATE SET
    preview = EXCLUDED.preview,
    summary = EXCLUDED.summary,
    messages = EXCLUDED.messages,
    message_count = EXCLUDED.message_count,
    updated_at = now();

-- name: ListResumablePlanChatSessions :many
-- Summary columns only (messages can be large). A chat that already produced
-- a trip is represented by its trip card, so it is excluded here — this also
-- hides abandoned refine chats, whose chat_id belongs to an existing trip.
SELECT id, chat_id, title, preview, message_count, created_at, updated_at
FROM plan_chat_sessions s
WHERE s.user_id = $1
  AND NOT EXISTS (
      SELECT 1 FROM trips t
      WHERE t.user_id = s.user_id AND t.chat_id = s.chat_id
  )
ORDER BY s.updated_at DESC
LIMIT 10;

-- name: GetPlanChatSessionByChatID :one
SELECT * FROM plan_chat_sessions
WHERE user_id = $1 AND chat_id = $2;

-- name: DeletePlanChatSession :execrows
DELETE FROM plan_chat_sessions
WHERE user_id = $1 AND chat_id = $2;

-- name: DeleteStalePlanChatSessions :exec
-- Opportunistic prune (called from the list handler): a conversation idle for
-- two months is abandoned, not "in progress".
DELETE FROM plan_chat_sessions
WHERE updated_at < now() - interval '60 days';
