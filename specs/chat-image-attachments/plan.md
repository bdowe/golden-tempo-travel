# Plan: Chat Image Attachments

> **HOW.** Translates `spec.md` into a file-level technical approach. See
> `../../CLAUDE.md` for repo conventions.

## Technical Approach

Inline base64 images in the existing `/plan` JSON request — no upload endpoint,
no object store. Each `PlanChatMessage` gains an optional `images` array
(`{media_type, data}`); the handler emits Anthropic image content blocks ahead
of the text block for user messages. The client downscales images before send
(longest side ≤1568px — Anthropic's effective max — re-encoded JPEG ~q80) so a
photo lands at ~100–300 KB; that keeps the resend-whole-history-every-turn
pattern and the twice-per-turn JSONB transcript upserts tolerable. Persisted
transcripts strip pixel data but keep `media_type` as a placeholder marker, so
resumed chats render an "image" chip and resend a valid (empty-data, skipped)
history.

Key decisions:
- **Inline base64 over upload-by-reference:** one request, no storage infra,
  matches degraded-mode statelessness; bounded by caps + client downscaling.
- **Separate `images` field, never in `content`:** keeps the existing
  `planMaxMessageChars` rune cap and the compactor's text-only distillation
  untouched.
- **Engine-native decode + pure-Dart encode** on the client: browser codecs do
  the heavy decode/resize (no main-thread jank); the `image` package only
  encodes the already-small result.

## Go API Changes

`src/packages/api/`:

- **`plan_handler.go`** — `PlanImage{MediaType, Data}` type; `Images
  []PlanImage` on `PlanChatMessage`; constants `planMaxImagesPerMessage=4`,
  `planMaxImagesPerRequest=12`, `planMaxImageBase64Len=6_800_000` (≈5 MB
  decoded); validation in the existing guard block (media-type allowlist
  jpeg/png/gif/webp, counts, size, user-role-only) as friendly SSE `error`
  events; conversion builds `NewUserMessage(imageBlocks..., textBlock)` via
  `anthropic.NewImageBlockBase64`, skipping empty-`Data` placeholders and
  never emitting an empty text block (image-only messages).
- **`plan_compactor.go`** — comment only: folded images intentionally drop
  from summaries (`buildDistillationTranscript` reads `.Content`).
- **`chat_session_handler.go`** — `savePlanChatSession` blanks `Data` on every
  persisted image (keeps `MediaType`) before `json.Marshal`.
- **`middleware.go`** — `planMaxRequestBodyBytes` 4 MiB → 20 MiB; comment
  notes the body cap is the effective aggregate image bound.
- **nginx** — `client_max_body_size` 10m → 20m in
  `dockerize/development/nginx/default.conf` and
  `dockerize/deployment/nginx/snippets/app-locations.conf`.

## Flutter Changes

`src/packages/flutter-app/lib/`:

- **Models** — `models/plan_message.dart`: `PlanAttachment{Uint8List? bytes,
  String mediaType}` with memoized `base64Data` (history re-serializes every
  turn); `PlanMessage.attachments` (default `const []`). Hand-rolled, no
  `.g.dart`.
- **Service** — `services/plan_service.dart`: `streamPlan` takes
  `List<Map<String, dynamic>>`; new `services/image_attachment_pipeline.dart`
  (validate → dimensions via `ui.ImageDescriptor` → pass-through if ≤1568px &
  ≤500 KB → engine downscale + JPEG q80 encode, alpha flattened to white).
- **Provider** — `providers/plan_provider.dart`: `sendMessage(...,
  attachments)` threaded through `QueuedMessage`/`_drainQueue`/`_sendNow`/
  `retryLastSend`; history maps `images` for byte-bearing attachments only;
  empty-text sends allowed with attachments.
- **Widgets** — `widgets/chat_panel.dart`: `DropTarget` (desktop_drop) around
  the panel with a drop overlay; paperclip button (file_picker,
  `FileType.image`, `withData`, multiple) in `_InputBar`; pending-chips row
  (thumbnails + ✕) above the input; bubbles render `Image.memory` thumbnails
  or an icon placeholder for `bytes == null` (resume).
- **Screens** — `screens/trips_list_screen.dart`: resume mapping parses
  `images` into null-byte placeholder attachments.
- **pubspec** — add `desktop_drop`, `file_picker`, `image`.

## Contract Parity  ← anti-drift gate

| JSON key | Go type (`plan_handler.go`) | Dart type | Nullable? | ✓ |
|----------|-----------------------------------|----------------------|-----------|---|
| `images` | `[]PlanImage` `omitempty` | `List<Map>` entry omitted when absent | yes | ☐ |
| `images[].media_type` | `string` | `String mediaType` | no | ☐ |
| `images[].data` | `string` (base64, "" when stripped) | `String` from memoized `base64Data` | no | ☐ |

## Cross-cutting

- **Env vars:** none.
- **Gateway:** existing `/api/v1/plan` path; only the `client_max_body_size`
  bump above.
- **Cost:** each ~1568px image ≈1,100–1,600 input tokens, re-sent per
  agent-loop iteration (mitigated by prompt caching, the 4/12 caps, and
  compaction folding old images away).

## Verification

- `make api-fmt && make api-vet`; `go test ./...` in `src/packages/api`.
- `make flutter-analyze && make flutter-test` (no codegen — models are
  hand-rolled).
- Manual via gateway (`make docker-dev`, API `up --build`, gateway recreate
  for nginx): walk every acceptance criterion in `spec.md` — drag-drop with
  overlay, paperclip, 4-cap, remove chip, image-only send, agent answers
  about the image, follow-up turn retains context, trip-refine panel,
  resume placeholder, oversized/unsupported rejection (client + `curl` a
  hand-built bad payload).
