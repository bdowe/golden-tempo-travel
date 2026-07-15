# Tasks: Continue Where You Left Off

## API (Go)

- [x] Migration `00031_plan_chat_sessions.sql`
- [x] `query/chat_sessions.sql` + `make api-sqlc`
- [x] `chat_session_handler.go` (save helper + list/get/delete handlers)
- [x] Persistence hook in `plan_handler.go` (start + deferred end upsert,
      compaction-aware snapshot, `turnText` accumulation)
- [x] Routes + startup log lines in `main.go`
- [x] Integration tests (`chat_session_integration_test.go`)

## Models & codegen (Flutter)

- [x] `models/chat_session.dart` + `make flutter-build-models`
- [x] Contract Parity table in `plan.md`

## UI (Flutter)

- [x] [P] `services/chats_api_service.dart`
- [x] [P] `providers/resumable_chats_provider.dart`
- [x] `PlanNotifier.resumeConversation` in `providers/plan_provider.dart`
- [x] "Continue where you left off" section in `trips_list_screen.dart`
      (+ dismiss, resume→Plan tab, invalidation)

## Verification

- [x] `make api-fmt && make api-vet` clean; `go test ./...` passes
- [x] `make flutter-analyze` clean (CI flags); `make flutter-test` passes
- [x] Manual end-to-end via gateway: session persists after one authed turn;
      section renders on Trips; resume hydrates + next turn carries full
      history; graduation on trip insert; dismiss 204/404; anonymous 401
