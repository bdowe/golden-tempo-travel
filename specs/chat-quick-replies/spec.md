# Spec: Chat Quick Replies

> **WHAT & WHY only.** See `plan.md` for the technical approach.

## Context

The planning agent frequently ends its turn with a question ("Does Prague
feel right?", "What budget suits you?"). Today the only way to answer is to
type — friction that is worst on mobile, where most short answers are two or
three words. One-tap reply chips (the pattern travelers know from every
messaging app) remove that friction and keep the conversation moving. This
was chosen over dropdown menus: chips read as part of the conversation and
never hide the free-text path.

## User Stories

- As a **traveler**, I want to tap a suggested answer instead of typing it,
  so short replies take one touch.
- As a **traveler**, I want the suggestions to actually match the question
  the agent just asked, not generic canned options.
- As a **Spanish-language traveler**, I want the suggestions in my language.
- As a **traveler**, I can always ignore the chips and type freely.

## Acceptance Criteria

- [ ] When the agent's reply ends with a question or choice, 2–4 tappable
  reply chips appear under the reply after it finishes streaming.
- [ ] Tapping a chip sends exactly the chip text as the traveler's message,
  and the chips disappear.
- [ ] Chips never appear while a reply is still streaming, alongside an
  error, or while a queued follow-up is waiting.
- [ ] A turn that produces an itinerary shows the itinerary banner, not
  reply chips.
- [ ] Chips work in both the Plan tab and a trip's refine panel.
- [ ] Suggestions are in the conversation's language.
- [ ] Reopening a conversation later ("Continue where you left off") does
  not restore chips (accepted for v1).
- [ ] No "suggest_replies…" tool spinner is ever visible in the chat.

## API Surface

One new SSE event on the existing `POST /api/v1/plan` stream:

### `suggest_replies` (server → client event)
- **Payload:** `{"replies": [string]}` — 2–4 short, sanitized,
  deduplicated strings in the conversation language.
- **Compatibility:** already-deployed clients ignore unknown event types;
  no request changes, no new endpoints.

## Data Model

None. Suggestions are transient per-turn UI state — deliberately not
persisted (no migration).

## UI Behavior

- **Surface:** a wrap of tappable chips in the chat tail, under the
  assistant's reply (above the itinerary banner slot), in both ChatPanel
  hosts.
- **Happy path:** agent asks a question → stream ends → chips appear → tap
  → chip text becomes the traveler's message → chips gone → normal turn.
- **States:** hidden while streaming, on error (error banner owns the
  tail), while a follow-up is queued, and when the model offered none.

## Edge Cases & Error States

- Model calls the tool mid-turn and keeps talking: chips stay hidden until
  the stream closes, then show under the finished reply.
- Model calls it twice in one turn: last call wins.
- Model sends empty/oversized/duplicate strings: sanitized server-side;
  an all-invalid call shows nothing and the model is told why.
- Model violates the prompt and calls it in a text-less turn: chips may
  render under the previous assistant bubble — accepted; revisit if seen.
- Stream errors after the event: the error clears the chips.

## Out of Scope

- Persisting/restoring chips across resume.
- Per-chip icons, analytics on chip usage, dark mode.
- Any change to compaction (suggestions never enter the summary).

## Open Questions

None.
