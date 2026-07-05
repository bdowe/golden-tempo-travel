# Tasks: Chat Streaming Polish

> Dependency-ordered. `[P]` = can run in parallel with its siblings.

## API (Go)

- [x] [P] Reword `plan_handler.go` prompts: no "cards", summarize top options
      in prose, light-markdown formatting line

## Flutter

- [x] Add `gpt_markdown` to `pubspec.yaml` + `flutter pub get`
- [x] [P] Coalesce `text_delta` flushes in `plan_provider.dart` (timer +
      cancel-before-clear + `dispose`)
- [x] [P] New `widgets/result_summary_chip.dart`
- [x] Restructure `chat_panel.dart`: `ListView.builder` + keyed bubbles,
      `_ChatTail` leaf selects, delete card sections, `onViewTrip` param,
      `jumpTo` scroll fix, markdown bubbles + `_StreamingCursor`
- [x] Wire `onViewTrip` in `agent_screen.dart` → `TripDetailScreen`

## Verification

- [x] `make api-fmt && make api-vet` clean
- [x] `make flutter-analyze` clean
- [x] New `test/plan_provider_stream_test.dart` passes; `make flutter-test`
- [x] Manual end-to-end via gateway (`make docker-dev` →
      `http://localhost:3000`): every acceptance criterion in `spec.md`
