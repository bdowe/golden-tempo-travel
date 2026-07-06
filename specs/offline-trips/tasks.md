# Tasks: Offline Trip Cache

## PR 1 — Flutter (`wave8/offline-trips`)
- [x] Spec + plan
- [x] `services/trip_cache.dart` (user-scoped shared_preferences store, MRU
  eviction at 10, network-error classifier, `clearForUser`)
- [x] `providers/trip_cache_provider.dart` (auth-scoped)
- [x] `trips_provider.dart` — write-through + offline fallback, `offlineSince`
- [x] `trip_detail_screen.dart` — write-through + offline fallback (loud path
  only), `_guardOffline()` on every mutation, disabled/hidden affordances
- [x] `widgets/offline_banner.dart` (+ `relativeTime`) on list + detail
- [x] `auth_provider.signOutLocally()` clears the cache (logout, logout-all,
  account deletion)
- [x] Tests: cache unit, provider offline paths, detail + list widget tests
- [ ] Manual airplane-mode verification (Brian; steps in PR body)

## Deferred (spec Out of Scope)
- Offline mutations / write queueing; shared-with-me + public share caching;
  connectivity_plus proactive detection; drift/sqflite storage upgrade;
  offline map tiles.
