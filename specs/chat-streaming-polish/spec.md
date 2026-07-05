# Spec: Chat Streaming Polish

## Context

The AI planning chat feels janky: streamed text stutters and repaints the whole
conversation as it arrives, the auto-scroll fights itself, the assistant's
formatting (bold, lists) shows as raw asterisks, and large result cards
(flights, events, local picks, ferries) jump into the conversation while text
is still loading. All of that card content already has a durable home in the
trip detail view (booking checklist, embedded events, itinerary pins). The
outcome: a calm, professional chat — smooth live text, proper formatting, and
quiet one-line result summaries that link to the trip instead of inline cards.

## User Stories

- As a **traveler planning a trip in the chat**, I want streamed replies to
  render smoothly with real formatting so that the assistant feels polished
  and readable.
- As a **traveler**, I want search results summarized in one quiet line that
  links to my trip so that the conversation isn't buried under cards.
- As a **traveler re-reading earlier messages mid-stream**, I want the chat to
  stop auto-scrolling until I return to the bottom so that I don't lose my
  place.

## Acceptance Criteria

- [ ] Streamed reply text appears smoothly (no visible stutter/flicker) even in
      long conversations.
- [ ] Assistant messages render markdown: bold, lists, links — no raw `**` or
      `-` artifacts once the message completes.
- [ ] While streaming, a subtle blinking cursor marks the live message (no
      spinner inside the text bubble).
- [ ] Flight / event / local-pick / ferry / event-source results appear as a
      single compact summary line each (icon + count + route/city), not as
      stacks of cards.
- [ ] Once the trip is saved, tapping a summary line opens the trip detail
      view; before that it is a plain non-tappable label.
- [ ] In the trip-detail refine panel, summary lines are plain labels (the trip
      is already on screen).
- [ ] Scrolling up during a stream pauses auto-follow; scrolling back to the
      bottom resumes it without rubber-banding.
- [ ] The assistant no longer tells the traveler to look at "cards" in the
      chat.
- [ ] Trip detail continues to surface the full results (booking checklist,
      embedded events, itinerary pins) unchanged.

## API Surface

No endpoint changes. The `/api/v1/plan` SSE stream and its event types are
unchanged; only the assistant's prompt wording changes (how it refers to
results shown in the app).

## Data Model

No new or changed entities.

## UI Behavior

- **Surface:** the Agent tab chat and the trip-detail refine panel (shared
  chat surface).
- **Happy path:** traveler asks for a trip → text streams in smoothly with a
  blinking cursor → tool activity shows as small chips → each result set
  arrives as one summary line → on completion the itinerary banner appears and
  summary lines become tappable links to the trip.
- **States:** empty (existing empty state), streaming (cursor + tool chips),
  results (summary lines), error (existing error banner) — all unchanged in
  placement, only calmer in rendering.

## Edge Cases & Error States

- Mid-stream markdown (unclosed `**`, half-finished lists) may render literally
  for a moment and snap to styled when the token closing it arrives — accepted.
- A stream that errors or is disposed mid-flight must not leave a ghost
  streaming bubble behind.
- Result sets with zero items produce no summary line (same as today's cards).

## Out of Scope

- Adding new result surfaces to trip detail (it already covers the content).
- Persisting flight/event/ferry results beyond what is saved today.
- Typewriter/character-by-character animation effects.

## Open Questions

None.
