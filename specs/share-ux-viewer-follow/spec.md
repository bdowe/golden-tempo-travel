# Spec: Native Share Sheet & Viewer Follow

## Context

Two rough edges remain in sharing. First, sharing is clipboard-only: on a
phone, "Copy share link" then switching apps to paste is clunky when every
other app opens the OS share sheet. Second, a read-only share link is
stateless — a friend who wants to keep watching the trip has either a buried
browser link or a frozen copy. This feature adds the native share sheet on
mobile, and lets a viewer-link recipient "Keep in my trips": a read-only
membership that shows the live trip in their own app as the owner plans.

## User Stories

- As a **trip owner on my phone**, I want **the OS share sheet** so that
  **sending the link to a friend is one tap into Messages/WhatsApp**.
- As a **friend with a view link**, I want **the trip pinned in my own app,
  staying current** so that **I don't need to re-find the link or settle for
  a stale copy**.
- As a **trip owner**, I want **viewers clearly read-only and manageable**
  so that **sharing widely never risks stray edits**.

## Acceptance Criteria

- [ ] On iOS/Android, "Share link…" and "Share co-planner invite…" open the
      OS share sheet with a "{title} · {dates}" message + URL (anchored
      correctly on iPad); on web/desktop the actions copy to the clipboard
      with the existing snackbar.
- [ ] Opening a viewer link offers "Keep in my trips"; after joining, the
      trip appears under "Shared with you" marked "Shared by {owner}", and
      opening it shows the live trip read-only.
- [ ] Viewers see no edit affordances (no rename/dates/status editing, no
      add/edit/delete on places, stays, transport), no AI refine or chat, and
      no booking checklist; their reads stay fresh via the same silent
      polling co-planners get.
- [ ] Viewer mutations are rejected server-side with the same not-found
      posture as strangers.
- [ ] An editor link upgrades a viewer to co-planner; a viewer link never
      downgrades an editor.
- [ ] Members can remove a shared trip from their own list (viewer or
      editor); the owner can remove individual viewers from Manage access,
      which now labels each person "Can edit" or "Viewer".

## API Surface

### `POST /api/v1/shared/{token}/join` (behavior change)
- Viewer tokens no longer 403: they create a viewer-role membership.
  Response `access` reflects the resulting role (upgrade-never-downgrade).

### `GET /api/v1/trips/{id}` (behavior change)
- Now readable by viewer members; `access` may be `viewer`; booking todos are
  omitted for viewers (same boundary as the public share view); `chat_id`
  stays null for all non-owners.

### `GET /api/v1/trips/shared-with-me`, `GET /trips/{id}/collaborators`
- Rows carry the member's actual `role`/`access` instead of assuming editor.

### `DELETE /api/v1/trips/{id}/collaborators/me`
- The caller leaves a trip shared with them (editor or viewer). Owners get
  404 (they aren't members).

## Data Model

No migration. The existing membership row's `role` column now takes the
value `viewer`; the join upsert upgrades roles but never downgrades.

## UI Behavior

- **Share menu (mobile):** items read "Share link…" / "Share co-planner
  invite…" and open the share sheet; desktop/web keep the copy labels.
- **Shared-trip screen (viewer link):** primary "Keep in my trips", secondary
  "Or save a separate copy". Editor links unchanged.
- **Trip detail (viewer):** banner "Shared by {owner} — view only" with an
  eye icon; static status pill; no edit pencils, item menus, add buttons,
  refine surfaces, or booking checklist; an app-bar "Remove from my trips"
  action (confirm dialog) for any non-owner member.
- **Trips list:** viewer cards get an eye icon + "Shared by {owner}"; editor
  cards keep the group icon + "Planned with {owner}".
- **Manage access sheet:** rows labeled "Can edit" / "Viewer"; removal works
  for both.

## Edge Cases & Error States

- Viewer opens a cached copy offline: the existing offline read-only mode
  already hides edit affordances.
- Owner revokes links: existing followers keep access (same semantics as
  co-planners); the revoke snackbar says so.
- iPad share popover requires an anchor rect — derived from the share menu
  button; sharing is skipped gracefully if the anchor is gone.

## Out of Scope

- Viewer-role email invites.
- Public OG-preview changes (viewer follow reuses existing share links).
- Live sync beyond the freshness polling that already exists.

## Open Questions

None — resolved during planning: viewers never see booking todos; CTA copy
"Keep in my trips"; clipboard remains the web/desktop behavior.
