package main

import (
	"bytes"
	"encoding/json"
	"net/http/httptest"
	"strings"
	"testing"

	"travel-route-planner/store"
)

func TestPersonalizedSystemPromptNilPrefs(t *testing.T) {
	if got := personalizedSystemPrompt("base", nil); got != "base" {
		t.Fatalf("prompt = %q, want base unchanged", got)
	}
}

func TestPersonalizedSystemPromptEmptyPrefs(t *testing.T) {
	if got := personalizedSystemPrompt("base", &store.TravelerPreference{}); got != "base" {
		t.Fatalf("prompt = %q, want base unchanged", got)
	}
}

func TestPersonalizedSystemPromptIncludesNotesAlone(t *testing.T) {
	p := &store.TravelerPreference{ProfileNotes: strPtr("- vegetarian\n- travels with kids")}
	got := personalizedSystemPrompt("base", p)
	if !strings.Contains(got, "Traveler profile notes (maintained by you):\n- vegetarian\n- travels with kids") {
		t.Fatalf("prompt missing notes block: %q", got)
	}
	if strings.Contains(got, "Traveler preferences —") {
		t.Fatalf("prompt should have no preferences line when fields are unset: %q", got)
	}
}

func TestPersonalizedSystemPromptCombinesFieldsAndNotes(t *testing.T) {
	p := &store.TravelerPreference{
		Budget:       strPtr("mid"),
		ProfileNotes: strPtr("- prefers boutique stays"),
	}
	got := personalizedSystemPrompt("base", p)
	if !strings.Contains(got, "budget: mid") {
		t.Fatalf("prompt missing budget: %q", got)
	}
	if !strings.Contains(got, "- prefers boutique stays") {
		t.Fatalf("prompt missing notes: %q", got)
	}
}

func TestPersonalizedSystemPromptIgnoresWhitespaceNotes(t *testing.T) {
	p := &store.TravelerPreference{ProfileNotes: strPtr("  \n ")}
	if got := personalizedSystemPrompt("base", p); got != "base" {
		t.Fatalf("prompt = %q, want base unchanged for blank notes", got)
	}
}

// runPlanHandler posts a PlanRequest to planHandler directly (the recorder
// implements http.Flusher, which the SSE handler requires) and returns the
// raw event-stream body.
func runPlanHandler(t *testing.T, req PlanRequest) *httptest.ResponseRecorder {
	t.Helper()
	body, err := json.Marshal(req)
	if err != nil {
		t.Fatalf("marshal request: %v", err)
	}
	rec := httptest.NewRecorder()
	planHandler(rec, httptest.NewRequest("POST", "/api/v1/plan", bytes.NewReader(body)))
	return rec
}

// Oversized histories must be rejected with a friendly SSE error event (the
// stream's normal error shape), before any model call or session bookkeeping.
func TestPlanHandlerRejectsTooManyMessages(t *testing.T) {
	msgs := make([]PlanChatMessage, planMaxMessages+1)
	for i := range msgs {
		msgs[i] = PlanChatMessage{Role: "user", Content: "hi"}
	}
	rec := runPlanHandler(t, PlanRequest{Messages: msgs})

	out := rec.Body.String()
	if !strings.Contains(out, `"type":"error"`) {
		t.Fatalf("stream = %q, want an SSE error event", out)
	}
	if !strings.Contains(out, "too long") || !strings.Contains(out, "start a new chat") {
		t.Fatalf("stream = %q, want the conversation-too-long message", out)
	}
	if strings.Count(out, "data: ") != 1 {
		t.Fatalf("stream = %q, want exactly one event (handler must stop after rejecting)", out)
	}
}

func TestPlanHandlerRejectsOversizedMessage(t *testing.T) {
	rec := runPlanHandler(t, PlanRequest{Messages: []PlanChatMessage{
		{Role: "user", Content: strings.Repeat("a", planMaxMessageChars+1)},
	}})

	out := rec.Body.String()
	if !strings.Contains(out, `"type":"error"`) || !strings.Contains(out, "too long") {
		t.Fatalf("stream = %q, want an SSE error event about an oversized message", out)
	}
	if strings.Count(out, "data: ") != 1 {
		t.Fatalf("stream = %q, want exactly one event", out)
	}
}

func TestPlanHandlerRejectsOversizedSummary(t *testing.T) {
	rec := runPlanHandler(t, PlanRequest{
		Summary:  strings.Repeat("a", planMaxMessageChars+1),
		Messages: []PlanChatMessage{{Role: "user", Content: "hi"}},
	})

	out := rec.Body.String()
	if !strings.Contains(out, `"type":"error"`) || !strings.Contains(out, "too long") {
		t.Fatalf("stream = %q, want an SSE error event about an oversized summary", out)
	}
	if strings.Count(out, "data: ") != 1 {
		t.Fatalf("stream = %q, want exactly one event", out)
	}
}

func TestNotesPreview(t *testing.T) {
	if got := notesPreview(nil); got != "" {
		t.Fatalf("preview = %q, want empty for nil", got)
	}
	if got := notesPreview(strPtr("short")); got != "short" {
		t.Fatalf("preview = %q", got)
	}
	long := strings.Repeat("é", 100)
	got := notesPreview(&long)
	if r := []rune(got); len(r) != 81 || !strings.HasSuffix(got, "…") {
		t.Fatalf("preview should be 80 runes + ellipsis, got %d runes: %q", len([]rune(got)), got)
	}
}
