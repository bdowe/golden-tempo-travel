# Tasks: Conversation Compaction

> Dependency-ordered. `[P]` = can run in parallel with its siblings.

## API (Go)

- [ ] `plan_compactor.go`: constants, `summarizePlanConversation`,
      `compactPlanMessages`, summary-message rendering, defensive truncation
- [ ] `plan_compactor_test.go`: split/threshold logic, transcript trimming,
      forced-tool call via fake-Anthropic, failure path (default non-tool answer)
- [ ] `plan_handler.go`: `Summary` field + validation, `planMaxMessages` → 60,
      compaction block **before** session construction, `compacting`/`compacted`
      SSE events, instrumentation bools, comment rewrite
- [ ] `plan_integration_test.go`: threshold crossing (events + wire shape),
      summarizer failure (graceful), summary pass-through below threshold,
      oversized summary rejection

## UI (Flutter)

- [ ] `plan_service.dart`: `summary` named param, body field; update fake
      signatures in `plan_provider_stream_test.dart`,
      `plan_provider_queue_test.dart`, `plan_service_error_test.dart`
- [ ] `plan_provider.dart`: `compactedSummary`/`compactedCount`/`isCompacting`
      state, `_sendNow` projection, `compacting`/`compacted` cases,
      `isCompacting` cleared on error/stream end
- [ ] `chat_panel.dart`: "Summarizing earlier conversation…" chip
- [ ] `plan_provider_compaction_test.dart`: compacted-state update, next-send
      projection, retry-after-error, queued-drain across boundary,
      `isCompacting` lifecycle
- [ ] `plan_service` body test: `summary` serialized when present, absent otherwise

## Verification

- [ ] `make api-fmt && make api-vet` clean
- [ ] `cd src/packages/api && go test ./...` pass
- [ ] `make flutter-analyze` clean, `make flutter-test` pass
- [ ] Cheap live E2E (25 scripted messages, buried fact recalled) or in-app
      check with `planCompactThreshold = 6` via `make docker-dev`
