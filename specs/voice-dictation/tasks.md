# Tasks: Voice Dictation

> Dependency-ordered. `[P]` = can run in parallel with its siblings (no shared
> files / no ordering dependency). Work top to bottom; verification is last.

## API (Go)

- [x] Implement `transcription_service.go` (OpenAI-compatible multipart
      forwarder, Groq defaults, env config, startup warning) + service tests
- [x] Implement `transcribe_handler.go` (POST /transcribe raw-bytes,
      GET /transcribe/availability, degraded-mode 503) + handler tests
- [x] Register routes + dedicated `transcribeLimiter` + startup log in
      `main.go`
- [x] Add 10 MiB `/api/v1/transcribe` lane to `bodyLimitMiddleware`
      (+ extend middleware test)
- [x] Add `TRANSCRIPTION_API_KEY` / `TRANSCRIPTION_BASE_URL` /
      `TRANSCRIPTION_MODEL` to `.env.sample`

## Gateway

- [x] [P] `client_max_body_size 10m;` in `dockerize/development/nginx/default.conf`
      `/api/` location
- [x] [P] `client_max_body_size 10m;` in
      `dockerize/deployment/nginx/snippets/app-locations.conf` `/api/` location

## Flutter — deps & platform

- [x] Add `speech_to_text` + `record` to `pubspec.yaml` (verify pins against
      Flutter 3.35.4) and pub get
- [x] [P] iOS `Info.plist` mic + speech usage strings
- [x] [P] Android `RECORD_AUDIO` permission + speech `<queries>` intent
- [x] [P] macOS audio-input entitlements + usage string

## Flutter — services & UI

- [x] `lib/services/dictation_engine.dart` (abstract + `SpeechToTextEngine` +
      `RecorderEngine`)
- [x] [P] `lib/services/transcribe_api_service.dart`
- [x] `lib/services/dictation_controller.dart` (append semantics, status
      machine, runtime fallback)
- [x] `lib/providers/dictation_provider.dart` (engine factory + availability
      FutureProvider)
- [x] `chat_panel.dart`: `_ChatPanelState` owns the controller; `_InputBar`
      mic button states; SnackBar errors
- [x] Complete the Contract Parity table in `plan.md` (every row ✓)

## Verification

- [x] Flutter tests: `dictation_controller_test.dart`,
      `chat_panel_dictation_test.dart`, `transcribe_api_service_test.dart`
- [x] `make api-fmt && make api-vet` clean
- [x] `make flutter-analyze` clean
- [x] `make flutter-test` / `make api-test` pass
- [ ] Manual end-to-end via gateway (`make docker-dev` →
      `http://localhost:3000`): every acceptance criterion in `spec.md`
      checked off (Chrome live path; fallback path; hidden-mic case;
      dictate-while-streaming)
- [ ] Deployment-build COOP/COEP check
- [x] Privacy page sentence (`dockerize/static/privacy.html`)
