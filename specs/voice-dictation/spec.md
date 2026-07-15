# Spec: Voice Dictation

> **WHAT & WHY only.** No tech choices, file names, libraries, or code. If a
> sentence names a file or a package, it belongs in `plan.md`, not here.

## Context

Typing a full trip request or follow-up on a phone (or while multitasking) is
slow; speaking it is faster and more natural. This feature lets the user
dictate a chat message: tap a mic button in the composer, speak, and the
transcript appears in the text field for review before sending. It is
**dictation, not voice chat** — the assistant's replies stay text-only, and
nothing is sent until the user taps send.

## User Stories

- As a **traveler planning a trip**, I want to **speak my request instead of
  typing it** so that **I can describe a trip quickly and hands-free**.
- As a **user who made a dictation mistake**, I want the **transcript to land
  in the input box, editable**, so that **I can fix errors before the agent
  sees them and wastes a turn**.
- As a **user of a browser without built-in speech recognition**, I want
  **dictation to still work** so that **the feature isn't Chrome-only**.
- As a **user whose browser and server both lack speech support**, I want the
  **mic button to simply not appear** so that **I'm never offered a button
  that fails**.

## Acceptance Criteria

- [ ] A mic button appears in the chat composer (both the Agent tab and the
      trip refine panel) when at least one dictation path is available.
- [ ] Tapping the mic starts listening (after the browser's permission prompt
      on first use); the button visibly changes state while listening.
- [ ] In browsers with built-in speech recognition, the transcript appears
      live in the input field as the user speaks.
- [ ] In browsers without built-in speech recognition (when the server-side
      fallback is configured), audio is recorded, a transcribing indicator is
      shown after stopping, and the final transcript is inserted.
- [ ] Dictated text is **appended** to whatever the user had already typed —
      existing text is never overwritten.
- [ ] The user can edit the transcript and must tap send (or press enter) to
      send it; nothing is auto-sent.
- [ ] Listening stops on: tapping the mic again, ~3 seconds of silence, or a
      60-second maximum.
- [ ] Typing in the input field while listening stops the dictation session
      and keeps the user's edit.
- [ ] Dictating while the assistant is streaming a reply works; the sent
      message queues exactly like a typed one.
- [ ] When neither dictation path is available (unsupported browser and no
      server transcription configured), the mic button is not rendered.
- [ ] Microphone-permission denial and transcription failures surface as a
      brief, non-blocking notice — never as a chat error.

## API Surface

### `POST /api/v1/transcribe`
- **Purpose:** transcribe a short recorded audio clip to text (fallback path
  for browsers without built-in speech recognition).
- **Request:** raw audio bytes in the request body; the content type declares
  the audio format (webm/ogg/mp4/wav). No other fields.
- **Response:** the transcribed `text` and a `status` of `success`.
- **Errors:** missing/unsupported content type or empty body → invalid-request
  error; clip larger than the size cap → too-large error; transcription
  provider not configured → service-unavailable error (same degraded-mode
  behavior as other optional providers); provider failure → upstream error
  with a generic message.
- **Auth:** none required — mirrors the plan chat, which works anonymously.
  Protected by its own rate limit.

### `GET /api/v1/transcribe/availability`
- **Purpose:** let the client decide up front whether the fallback path
  exists, so the mic can be hidden instead of failing after the user speaks.
- **Request:** none.
- **Response:** `available` — whether server-side transcription is configured.
- **Errors:** none (always answers).

## Data Model

None. Nothing about a dictation is persisted — audio is transcribed and
discarded; the resulting text only exists as a normal chat message if and when
the user sends it.

## UI Behavior

- **Screen / surface:** the chat composer — the mic button sits between the
  text field and the send button, in both the Agent tab and the trip refine
  panel.
- **Happy path:** tap mic → (first time) grant permission → speak → words
  appear in the field (live path) or after a short transcribing state
  (fallback path) → edit if needed → tap send.
- **States:**
  - *Idle:* outlined mic icon.
  - *Listening:* filled/accented mic icon, visually distinct.
  - *Transcribing (fallback only):* small progress indicator in place of the
    mic.
  - *Unavailable:* button absent.
  - *Error:* transient notice (e.g. "Microphone access was blocked",
    "Couldn't transcribe audio — you can type instead"); composer unaffected.

## Edge Cases & Error States

- **Permission denied:** transient notice; button returns to idle.
- **No speech detected / empty transcript:** silent no-op; no message, no
  error.
- **Browser advertises speech recognition but it fails at start** (some
  privacy-focused browsers): fall back to the record-and-upload path for the
  rest of the session if it's available, else show the unavailable notice.
- **Server fallback not configured:** the availability check reports false;
  in browsers that also lack built-in recognition the mic is hidden. A
  service-unavailable response mid-session likewise hides the mic going
  forward.
- **Recording caps:** 60 seconds / 10 MiB per clip — enough for a long spoken
  message, small enough to bound cost and abuse on an unauthenticated
  endpoint (which also has its own rate limit).
- **Privacy:** built-in browser recognition sends audio to the browser
  vendor's speech service (e.g. Google for Chrome, Apple for Safari); the
  fallback sends audio to our configured transcription provider. Audio is
  never stored by this app. The public privacy page should mention this when
  the feature ships.

## Out of Scope

- Voice chat / spoken assistant replies (text-to-speech).
- Auto-sending on end of speech.
- Language selection UI (browser/provider defaults are used).
- Persisting or replaying audio.
- Dictation anywhere other than the chat composer (e.g. search fields).

## Open Questions

None — transcription approach (browser-native with server fallback) and send
behavior (fill composer, user sends) were decided with the product owner.
