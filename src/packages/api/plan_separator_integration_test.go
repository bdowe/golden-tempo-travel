package main

import (
	"net/http"
	"testing"
)

// Text on either side of a tool call must reach the client — and the
// persisted transcript — with a paragraph separator at the boundary, so the
// live rendering, a later resume, and stale clients all agree
// (specs/chat-polish). The separator is inserted server-side at the delta
// site; the Flutter provider keeps a mirror rule that sees the emitted
// newline and does not double it.

func TestPlanSeparatorStreamedAndPersisted(t *testing.T) {
	resetDB(t)
	newFakeAnthropic(t,
		textThenToolTurn("Let me check stays.", "suggest_stays", `{"destination":"Paris"}`),
		textTurn("The best area is Le Marais."))

	_, token := createTestUser(t, "separator@example.com")
	rec := doJSON(t, "POST", "/api/v1/plan", token, PlanRequest{
		ChatID:   "chat-separator",
		Messages: []PlanChatMessage{{Role: "user", Content: "Where should I stay in Paris?"}},
	})
	if rec.Code != http.StatusOK {
		t.Fatalf("/plan = %d: %s", rec.Code, rec.Body.String())
	}
	events := planEvents(t, rec.Body.String())
	if errs := eventsOfType(events, "error"); len(errs) != 0 {
		t.Fatalf("unexpected error events: %v", errs)
	}
	const want = "Let me check stays.\n\nThe best area is Le Marais."
	if got := joinedText(events); got != want {
		t.Fatalf("streamed text = %q, want %q", got, want)
	}

	// The deferred session upsert ran when the handler returned, so the
	// resumable transcript already carries the same separated text.
	chatRec := doJSON(t, "GET", "/api/v1/chats/chat-separator", token, nil)
	if chatRec.Code != http.StatusOK {
		t.Fatalf("GET chat = %d: %s", chatRec.Code, chatRec.Body.String())
	}
	chat := decode(t, chatRec)
	msgs, _ := chat["messages"].([]any)
	if len(msgs) == 0 {
		t.Fatal("persisted chat has no messages")
	}
	last, _ := msgs[len(msgs)-1].(map[string]any)
	if last["role"] != "assistant" {
		t.Fatalf("last persisted message role = %v, want assistant", last["role"])
	}
	if last["content"] != want {
		t.Fatalf("persisted assistant text = %q, want %q", last["content"], want)
	}
}

// A turn that opens with a tool call (no text before it) must not gain a
// leading separator.
func TestPlanToolFirstTurnNoLeadingSeparator(t *testing.T) {
	resetDB(t)
	newFakeAnthropic(t,
		toolTurn("suggest_stays", `{"destination":"Paris"}`),
		textTurn("Browse these."))

	rec := doJSON(t, "POST", "/api/v1/plan", "", PlanRequest{
		ChatID:   "chat-no-lead-sep",
		Messages: []PlanChatMessage{{Role: "user", Content: "Where should I stay?"}},
	})
	if rec.Code != http.StatusOK {
		t.Fatalf("/plan = %d: %s", rec.Code, rec.Body.String())
	}
	if got := joinedText(planEvents(t, rec.Body.String())); got != "Browse these." {
		t.Fatalf("streamed text = %q, want %q", got, "Browse these.")
	}
}
