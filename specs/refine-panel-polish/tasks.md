# Tasks: Refine Panel Polish

> Dependency-ordered. `[P]` = can run in parallel with its siblings.

## Flutter

- [x] [P] `plan_message.dart`: add `displayLabel`
- [x] [P] `trip_detail_screen.dart`: `_load(silent:)` + coalescing `_refresh()`;
      rewire `onTripUpdated` + `RefreshIndicator`
- [x] `plan_provider.dart`: thread `displayLabel` through
      `sendMessage`/`beginSectionRefinement`; add `tripUpdatedThisTurn`
- [x] `chat_panel.dart`: `_SeedContextChip` itemBuilder branch +
      `_ItineraryUpdatedChip` in `_ChatTail`
- [x] `trip_detail_screen.dart`: pass `displayLabel: 'Refining ${target.label}'`
      in `_openRefine`

## Verification

- [x] Extend `test/plan_provider_stream_test.dart` (trip_updated lifecycle +
      history integrity with displayLabel)
- [x] New `test/chat_panel_seed_chip_test.dart`
- [x] New `test/trip_detail_silent_refresh_test.dart`
- [x] `make flutter-analyze` clean; `make flutter-test` green
- [x] Manual end-to-end (`http://localhost:3000`): every acceptance criterion
      in `spec.md`, wide + narrow layouts
