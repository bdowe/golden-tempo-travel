# Spec: Chat Image Attachments

> **WHAT & WHY only.** No tech choices, file names, libraries, or code. If a
> sentence names a file or a package, it belongs in `plan.md`, not here.

## Context

The AI planning chat is text-only, but trip planning is a visual activity:
travelers hold screenshots of hotel listings, maps, event posters, and photos
of hand-written itineraries. Today they must transcribe those into words. This
feature lets users attach images to a chat message — by dragging them onto the
chat or via an attach button — so the planning agent can see and reason about
them directly, matching the experience users already know from Claude and
ChatGPT.

## User Stories

- As a **traveler**, I want to **drop a screenshot of a hotel listing into the
  chat and ask "is this a good area to stay?"** so that I don't have to
  re-type the listing's details.
- As a **traveler**, I want to **attach a photo of a map or written itinerary**
  so that the agent can fold it into my plan.
- As a **traveler on a phone or tablet**, I want an **attach button that opens
  my gallery** so that I can add images without drag-and-drop.
- As a **returning user**, I want a resumed conversation to **show where
  images were attached** so that the transcript still reads coherently.

## Acceptance Criteria

- [ ] Dragging one or more image files over the chat shows a clear "drop to
      attach" affordance; dropping them attaches the images.
- [ ] An attach button in the composer opens a file/gallery picker filtered to
      images and supports selecting multiple.
- [ ] Attached images appear as thumbnail chips above the input field, each
      removable before sending.
- [ ] Up to 4 images can be attached to one message; attempting more shows a
      friendly notice.
- [ ] A message may be sent with images and no text.
- [ ] Sent messages display their images as thumbnails in the chat transcript.
- [ ] The agent's reply demonstrably reflects the image content (e.g. names
      the city in a dropped photo).
- [ ] Images attached earlier in the conversation remain visible to the agent
      on follow-up turns within the same session.
- [ ] Large photos are downscaled before upload; a multi-megabyte photo sends
      in a few hundred kilobytes without visible quality loss at chat size.
- [ ] Unsupported file types and oversized files are rejected with a friendly
      message; nothing is sent.
- [ ] The same attachment experience works in both the main planning chat and
      the trip-refine chat panel.
- [ ] On the web app, pasting an image from the clipboard (e.g. a screenshot)
      while the message field is focused attaches it like a drop; pasting
      plain text still pastes text normally.
- [ ] Resuming a saved conversation shows an "image" placeholder where images
      were attached; the conversation can continue normally.

## API Surface

No new endpoints. The existing plan-streaming request is extended:

### `POST /api/v1/plan` (extended)
- **Purpose:** each chat message may now carry attached images alongside its
  text.
- **Request:** a message optionally includes a list of images, each with a
  media type (JPEG, PNG, GIF, or WebP) and the encoded image data. Images are
  only valid on user messages. An image with empty data is a placeholder from
  a resumed conversation and is ignored.
- **Response:** unchanged (SSE stream).
- **Errors:** friendly streamed errors (not server faults) when: a message has
  more than 4 images; the request as a whole has more than 12; an image
  exceeds the per-image size cap (~5 MB decoded); the media type is not in the
  allowlist; images appear on an assistant message. Requests over the overall
  body size cap are rejected outright.

### `GET /api/v1/chats/{chatId}` (behavior change)
- Saved transcripts retain each image's media type but not its pixel data, so
  resumed conversations can render placeholders without storing megabytes.

## Data Model

- **Chat message image** — an attachment on a user chat message: a media type
  plus encoded image data. In persisted transcripts the data is stripped and
  only the media type remains (a placeholder marker). No new tables.

## UI Behavior

- **Surface:** the shared chat composer, in the Agent tab and the trip-refine
  panel.
- **Happy path:** user drags an image over the chat → overlay invites the
  drop → thumbnail chip appears above the input (brief processing spinner for
  large photos) → user types a question (optional) → send → the sent bubble
  shows the thumbnail(s) → the agent replies about the image.
- **States:**
  - *Processing:* a spinner chip while an image is being read/downscaled;
    sending is deferred until processing completes.
  - *Attached:* thumbnail chips with a remove (✕) control.
  - *Error:* snackbar for unreadable/oversized/unsupported files and for the
    5th image.
  - *Resumed:* placeholder chip (icon + "Image") where pixels are gone.

## Edge Cases & Error States

- Unsupported type (e.g. PDF, HEIC) → rejected client-side with a notice; the
  server independently rejects non-allowlisted types.
- Oversized source file (>10 MB) → rejected client-side before processing.
- Animated GIF larger than the pass-through threshold → downscaled to a still
  image (animation lost).
- Transparent PNG re-encoded to JPEG → transparency flattened to white.
- Send fails mid-stream → retry re-sends the message including its images.
- Message queued while the agent is streaming → its images are preserved and
  sent when the queue drains.
- Conversation compaction folds old messages into a text summary → their
  images leave the model's context (the newest messages keep theirs).

## Out of Scope

- Camera capture; paste-from-clipboard on native desktop/mobile (web paste
  shipped as a follow-up — native needs a clipboard plugin dependency).
- Image pixels surviving chat resume (placeholder only; no object storage).
- Images on trip itineraries, bookings, or anywhere outside the chat.
- Image generation or editing by the agent.
- Non-image attachments (PDF, documents).

## Open Questions

None — capture scope (drag-drop + attach button) and resume behavior
(placeholder, pixels dropped) were decided at planning time.
