# Tasks: Chat Image Attachments

> Dependency-ordered. `[P]` = can run in parallel with its siblings.

## API (Go)

- [ ] `PlanImage` type + `Images` field on `PlanChatMessage`; caps constants
- [ ] Guard-block validation (allowlist, counts, size, user-role-only) as SSE errors
- [ ] Anthropic conversion: image blocks before text, empty-`Data` skip, no empty text block
- [ ] `savePlanChatSession` strips image data (keeps media type)
- [ ] `planMaxRequestBodyBytes` → 20 MiB; nginx `client_max_body_size` → 20m (both configs)
- [ ] Compactor comment (images intentionally drop from summaries)
- [ ] Tests: `plan_images_test.go` (block order, image-only, validation, placeholder skip), persistence stripping, middleware lane

## Models & wire (Flutter)

- [ ] `PlanAttachment` (memoized base64) + `PlanMessage.attachments`
- [ ] Provider threading: sendMessage/queue/drain/retry + history `images` mapping; image-only sends
- [ ] `streamPlan` signature → `List<Map<String, dynamic>>`
- [ ] Resume mapping → placeholder attachments
- [ ] Contract Parity table in `plan.md` (every row ✓)

## UI (Flutter)

- [ ] pubspec: `desktop_drop`, `file_picker`, `image`
- [ ] [P] `image_attachment_pipeline.dart` (validate, pass-through, downscale+encode)
- [ ] [P] `DropTarget` + overlay on `ChatPanel`
- [ ] Paperclip button + pending-chips row + `_send` changes
- [ ] Bubble thumbnails + resume placeholders (incl. queued bubbles)

## Verification

- [ ] `make api-fmt && make api-vet` clean; `go test ./...` passes
- [ ] `make flutter-analyze` clean; `make flutter-test` passes
- [ ] Manual end-to-end via gateway: every acceptance criterion in `spec.md`
