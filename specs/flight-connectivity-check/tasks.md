# Tasks: Flight Connectivity Check

> Dependency-ordered. `[P]` = can run in parallel with its siblings.

## API (Go)

- [ ] Add `SupplierTimeoutMS` to `FlightSearchRequest` + query-param plumbing
      in `duffel_service.go`
- [ ] Implement `plan_connectivity.go`: tool definition, leg fan-out with
      semaphore + deadline + per-leg TTL cache, reduction, summary text
- [ ] Registry entry after `search_flights` + `connectivityCalls` session cap
      (`plan_tool_registry.go`)
- [ ] `search_flights` description nudge + `basePrompt` rule
      (`plan_tool_registry.go`, `plan_handler.go`)

## UI (Flutter)

- [ ] [P] `_toolLabel` case in `widgets/chat_panel.dart`

## Tests

- [ ] [P] `duffel_service_test.go`: supplier_timeout present/absent
- [ ] `plan_connectivity_test.go`: reduction, fan-out dedup, partial timeout,
      caps, cache, unresolvable candidate
- [ ] Update expected tool order in `plan_tool_registry_test.go`
- [ ] Integration test via fake-Anthropic harness (no `flights` event;
      summary reaches next model request)

## Verification

- [ ] `make api-fmt && make api-vet` clean
- [ ] `go test ./...` green in `src/packages/api`
- [ ] Manual stopover prompt against Duffel sandbox; chip label visible
