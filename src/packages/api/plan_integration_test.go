package main

import (
	"context"
	"encoding/json"
	"net/http"
	"strings"
	"testing"

	"github.com/google/uuid"
)

// End-to-end /plan coverage through buildRouter, with the Anthropic API
// replaced by the scriptable fake (fake_anthropic_test.go). Each test drives
// a real SSE session — request validation, the agent tool loop, tool
// execution against the test DB, persistence, and the client-facing event
// stream — with zero external calls.

// planEvents parses every `data: {...}` SSE line the /plan handler wrote.
func planEvents(t *testing.T, body string) []map[string]any {
	t.Helper()
	var events []map[string]any
	for _, line := range strings.Split(body, "\n") {
		data, ok := strings.CutPrefix(line, "data: ")
		if !ok {
			continue
		}
		var m map[string]any
		if err := json.Unmarshal([]byte(data), &m); err != nil {
			t.Fatalf("unparseable SSE data line %q: %v", line, err)
		}
		events = append(events, m)
	}
	return events
}

func eventsOfType(events []map[string]any, typ string) []map[string]any {
	var out []map[string]any
	for _, e := range events {
		if e["type"] == typ {
			out = append(out, e)
		}
	}
	return out
}

// eventData returns the event's data payload as a map (nil if absent).
func eventData(e map[string]any) map[string]any {
	d, _ := e["data"].(map[string]any)
	return d
}

// joinedText reassembles the streamed answer from text_delta events.
func joinedText(events []map[string]any) string {
	var b strings.Builder
	for _, e := range eventsOfType(events, "text_delta") {
		if txt, ok := eventData(e)["text"].(string); ok {
			b.WriteString(txt)
		}
	}
	return b.String()
}

// (a) A text-only turn streams multiple deltas that reassemble to the full
// answer, with no error event — the plain conversational path.
func TestPlanTextTurnStreamsDeltas(t *testing.T) {
	resetDB(t)
	const answer = "Lisbon in May is lovely — shall I plan three days?"
	newFakeAnthropic(t, textTurn(answer))

	rec := doJSON(t, "POST", "/api/v1/plan", "", PlanRequest{
		ChatID:   "chat-text",
		Messages: []PlanChatMessage{{Role: "user", Content: "where should I go in May?"}},
	})
	if rec.Code != http.StatusOK {
		t.Fatalf("/plan = %d, want 200", rec.Code)
	}
	events := planEvents(t, rec.Body.String())
	if deltas := eventsOfType(events, "text_delta"); len(deltas) < 2 {
		t.Fatalf("text_delta events = %d, want >= 2 (the fake splits text across frames)", len(deltas))
	}
	if got := joinedText(events); got != answer {
		t.Fatalf("reassembled text = %q, want %q", got, answer)
	}
	if errs := eventsOfType(events, "error"); len(errs) != 0 {
		t.Fatalf("unexpected error events: %v", errs)
	}
}

// (b) Tool loop: the model requests the DB-backed get_trip tool, the handler
// executes it against the test DB, the tool_result round-trips to the model
// (asserted on the fake's second request body), and the final text streams.
func TestPlanToolLoopRoundTripsToolResult(t *testing.T) {
	resetDB(t)
	fa := newFakeAnthropic(t,
		toolTurn("get_trip", `{}`),
		textTurn("You have one saved trip: Test Trip."))

	user, token := createTestUser(t, "tool-loop@example.com")
	createTestTrip(t, user.ID, 2)

	rec := doJSON(t, "POST", "/api/v1/plan", token, PlanRequest{
		ChatID:   "chat-tools",
		Messages: []PlanChatMessage{{Role: "user", Content: "what trips do I have saved?"}},
	})
	if rec.Code != http.StatusOK {
		t.Fatalf("/plan = %d, want 200", rec.Code)
	}
	events := planEvents(t, rec.Body.String())

	calls := eventsOfType(events, "tool_call")
	if len(calls) != 1 || eventData(calls[0])["name"] != "get_trip" {
		t.Fatalf("tool_call events = %v, want exactly one get_trip", calls)
	}
	results := eventsOfType(events, "tool_result")
	if len(results) != 1 || eventData(results[0])["name"] != "get_trip" {
		t.Fatalf("tool_result events = %v, want exactly one get_trip", results)
	}
	if got := joinedText(events); got != "You have one saved trip: Test Trip." {
		t.Fatalf("final text = %q", got)
	}
	if errs := eventsOfType(events, "error"); len(errs) != 0 {
		t.Fatalf("unexpected error events: %v", errs)
	}

	// The second model request must carry the executed tool's result back —
	// including content that only exists in the database.
	reqs := fa.requestBodies()
	if len(reqs) != 2 {
		t.Fatalf("model requests = %d, want 2 (tool turn + follow-up)", len(reqs))
	}
	followUp := string(reqs[1])
	if !strings.Contains(followUp, `"tool_result"`) {
		t.Fatalf("follow-up request carries no tool_result block: %s", followUp)
	}
	if !strings.Contains(followUp, "Test Trip") {
		t.Fatalf("tool_result did not round-trip DB content (missing trip title): %s", followUp)
	}
}

// (c) create_itinerary end-to-end: the streamed `done` event carries a
// trip_id, and that trip — title, summary and items — is really persisted.
func TestPlanCreateItineraryPersistsTrip(t *testing.T) {
	resetDB(t)
	newFakeAnthropic(t,
		toolTurn("create_itinerary", `{
			"title":"Athens Weekend","summary":"Two easy days in Athens.",
			"locations":[
				{"name":"Acropolis","latitude":37.9715,"longitude":23.7267,"day":1,"city":"Athens","category":"attraction","time_of_day":"morning"},
				{"name":"Ta Karamanlidika","latitude":37.9808,"longitude":23.7247,"day":1,"city":"Athens","category":"restaurant","time_of_day":"evening"}
			]}`),
		textTurn("Saved your Athens weekend!"))

	user, token := createTestUser(t, "finalizer@example.com")

	rec := doJSON(t, "POST", "/api/v1/plan", token, PlanRequest{
		ChatID:   "chat-athens",
		Messages: []PlanChatMessage{{Role: "user", Content: "plan me a weekend in Athens"}},
	})
	if rec.Code != http.StatusOK {
		t.Fatalf("/plan = %d, want 200", rec.Code)
	}
	events := planEvents(t, rec.Body.String())

	dones := eventsOfType(events, "done")
	if len(dones) != 1 {
		t.Fatalf("done events = %d, want 1", len(dones))
	}
	done := eventData(dones[0])
	tripID, _ := done["trip_id"].(string)
	if tripID == "" {
		t.Fatalf("done event carries no trip_id: %v", done)
	}
	if locs, _ := done["locations"].([]any); len(locs) != 2 {
		t.Fatalf("done event locations = %v, want 2", done["locations"])
	}
	if errs := eventsOfType(events, "error"); len(errs) != 0 {
		t.Fatalf("unexpected error events: %v", errs)
	}

	// The trip is readable through the normal REST surface.
	tripRec := doJSON(t, "GET", "/api/v1/trips/"+tripID, token, nil)
	if tripRec.Code != http.StatusOK {
		t.Fatalf("GET trip = %d: %s", tripRec.Code, tripRec.Body.String())
	}
	trip := decode(t, tripRec)
	if trip["title"] != "Athens Weekend" {
		t.Fatalf("persisted title = %v, want Athens Weekend", trip["title"])
	}
	items, _ := trip["items"].([]any)
	if len(items) != 2 {
		t.Fatalf("persisted items = %d, want 2", len(items))
	}

	// Settle the async trip_created analytics before the next test truncates.
	waitForEventCount(t, user.ID, "trip_created", 1)
}

// (c, trip-bound) update_itinerary_section on a bound trip replaces the
// section in the DB and streams a trip_updated event with the trip's id.
func TestPlanBoundSessionUpdatesSectionAndStreamsTripUpdated(t *testing.T) {
	resetDB(t)
	newFakeAnthropic(t,
		toolTurn("update_itinerary_section", `{"scope":"trip","items":[{"name":"New Cafe","latitude":37.98,"longitude":23.74,"day":1}]}`),
		textTurn("Swapped the whole plan for the cafe."))

	user, token := createTestUser(t, "refiner@example.com")
	trip := createTestTrip(t, user.ID, 2)

	rec := doJSON(t, "POST", "/api/v1/plan", token, PlanRequest{
		TripID:   trip.ID.String(),
		Messages: []PlanChatMessage{{Role: "user", Content: "replace everything with one cafe"}},
	})
	if rec.Code != http.StatusOK {
		t.Fatalf("/plan = %d, want 200", rec.Code)
	}
	events := planEvents(t, rec.Body.String())

	updated := eventsOfType(events, "trip_updated")
	if len(updated) != 1 || eventData(updated[0])["trip_id"] != trip.ID.String() {
		t.Fatalf("trip_updated events = %v, want exactly one for trip %s", updated, trip.ID)
	}
	if errs := eventsOfType(events, "error"); len(errs) != 0 {
		t.Fatalf("unexpected error events: %v", errs)
	}
	// A bound session must never create a new trip version.
	if dones := eventsOfType(events, "done"); len(dones) != 0 {
		t.Fatalf("unexpected done events on a bound session: %v", dones)
	}

	var count int
	var name string
	if err := dbPool.QueryRow(context.Background(),
		`SELECT count(*), min(name) FROM itinerary_items WHERE trip_id = $1`,
		trip.ID).Scan(&count, &name); err != nil {
		t.Fatalf("items query: %v", err)
	}
	if count != 1 || name != "New Cafe" {
		t.Fatalf("items after update = %d/%q, want 1/\"New Cafe\"", count, name)
	}
}

// (d) A mid-turn model error (SSE `error` event after deltas already
// streamed) surfaces to the client as a /plan error event, not a hang or a
// silent truncation.
func TestPlanMidTurnModelErrorSurfaces(t *testing.T) {
	resetDB(t)
	newFakeAnthropic(t, errorTurn("Overloaded"))

	rec := doJSON(t, "POST", "/api/v1/plan", "", PlanRequest{
		ChatID:   "chat-err",
		Messages: []PlanChatMessage{{Role: "user", Content: "plan something"}},
	})
	if rec.Code != http.StatusOK {
		t.Fatalf("/plan = %d, want 200 (headers are sent before the model call)", rec.Code)
	}
	events := planEvents(t, rec.Body.String())

	// The pre-error delta proves the failure hit MID-turn.
	if deltas := eventsOfType(events, "text_delta"); len(deltas) == 0 {
		t.Fatal("no text_delta before the error; the error was not mid-turn")
	}
	errs := eventsOfType(events, "error")
	if len(errs) != 1 {
		t.Fatalf("error events = %d, want 1", len(errs))
	}
	if msg, _ := eventData(errs[0])["message"].(string); msg == "" {
		t.Fatalf("error event carries no message: %v", errs[0])
	}
	if dones := eventsOfType(events, "done"); len(dones) != 0 {
		t.Fatalf("unexpected done events after error: %v", dones)
	}
}

// (e) The local-ingest anti-hallucination gate: extraction (a NON-streaming
// forced-tool call through the same seam) drafts a pin, Google verification
// cannot fill coordinates (no Places key), and publish is refused while the
// draft has no coordinates.
func TestLocalIngestUnverifiedDraftCannotPublish(t *testing.T) {
	resetDB(t)
	fa := newFakeAnthropic(t)
	fa.scriptNonStreamingTool("draft_local_content",
		`{"recommendations":[{"name":"To Steki","category":"restaurant","neighborhood":"Psyrri","tip":"Go before 8pm","quote":"","tags":["food"],"search_hint":"To Steki taverna, Athens"}]}`)

	// Force the verify step to fail: the Places singleton captured its key at
	// process init, so blank it directly (integration tests never run parallel).
	oldKey := placesService.APIKey
	placesService.APIKey = ""
	t.Cleanup(func() { placesService.APIKey = oldKey })

	admin, adminToken := createTestUser(t, "curator@example.com")
	makeAdmin(t, admin.ID)

	srcRec := doJSON(t, "POST", "/api/v1/admin/local/sources", adminToken,
		map[string]any{"name": "Maria", "location": "Athens"})
	if srcRec.Code != http.StatusCreated {
		t.Fatalf("create source = %d: %s", srcRec.Code, srcRec.Body.String())
	}
	sourceID, _ := decode(t, srcRec)["id"].(string)

	ingRec := doJSON(t, "POST", "/api/v1/admin/local/ingest", adminToken, map[string]any{
		"source_id": sourceID,
		"city":      "Athens",
		"kind":      "notes",
		"raw_text":  "Maria says To Steki in Psyrri is the move, go before 8pm.",
	})
	if ingRec.Code != http.StatusCreated {
		t.Fatalf("ingest = %d: %s", ingRec.Code, ingRec.Body.String())
	}
	var ing struct {
		Recommendations []struct {
			ID            uuid.UUID `json:"id"`
			Status        string    `json:"status"`
			Latitude      *float64  `json:"latitude"`
			PlaceVerified bool      `json:"place_verified"`
		} `json:"recommendations"`
		Verified   int `json:"verified"`
		Unverified int `json:"unverified"`
	}
	if err := json.Unmarshal(ingRec.Body.Bytes(), &ing); err != nil {
		t.Fatalf("decode ingest response: %v", err)
	}
	if len(ing.Recommendations) != 1 || ing.Verified != 0 || ing.Unverified != 1 {
		t.Fatalf("ingest = %d recs / %d verified / %d unverified, want 1/0/1: %s",
			len(ing.Recommendations), ing.Verified, ing.Unverified, ingRec.Body.String())
	}
	draft := ing.Recommendations[0]
	if draft.Status != "draft" || draft.Latitude != nil || draft.PlaceVerified {
		t.Fatalf("draft = %+v, want unverified draft with nil coordinates", draft)
	}

	// The gate: a coordinate-less draft cannot be published.
	pubRec := doJSON(t, "POST", "/api/v1/admin/local/recommendations/"+draft.ID.String()+"/publish", adminToken, nil)
	if pubRec.Code != http.StatusUnprocessableEntity {
		t.Fatalf("publish unverified draft = %d, want 422: %s", pubRec.Code, pubRec.Body.String())
	}
	if body := pubRec.Body.String(); !strings.Contains(body, "not verified") {
		t.Fatalf("publish rejection reason = %s, want the not-verified message", body)
	}

	// Still a draft afterwards — the gate blocked, it didn't archive or mutate.
	var status string
	if err := dbPool.QueryRow(context.Background(),
		`SELECT status FROM local_recommendations WHERE id = $1`, draft.ID).Scan(&status); err != nil {
		t.Fatalf("status query: %v", err)
	}
	if status != "draft" {
		t.Fatalf("status after blocked publish = %q, want draft", status)
	}
}
