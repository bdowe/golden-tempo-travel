package main

import (
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"testing"

	"github.com/google/uuid"
)

func addCustomTodo(t *testing.T, token, tripID, title string) string {
	t.Helper()
	rec := doJSON(t, "POST", "/api/v1/trips/"+tripID+"/booking-todos", token, map[string]any{
		"kind": "other", "title": title,
	})
	if rec.Code != http.StatusCreated {
		t.Fatalf("add todo %q = %d: %s", title, rec.Code, rec.Body.String())
	}
	return decode(t, rec)["id"].(string)
}

// listTodosViaSync exercises the same read path the app uses on trip load: an
// empty derived payload upserts nothing but returns the full ordered list.
func listTodosViaSync(t *testing.T, token, tripID string) []map[string]any {
	t.Helper()
	rec := doJSON(t, "PUT", "/api/v1/trips/"+tripID+"/booking-todos", token, []map[string]any{})
	if rec.Code != http.StatusOK {
		t.Fatalf("sync todos = %d: %s", rec.Code, rec.Body.String())
	}
	return decodeTodoList(t, rec)
}

func decodeTodoList(t *testing.T, rec *httptest.ResponseRecorder) []map[string]any {
	t.Helper()
	var list []map[string]any
	if err := json.Unmarshal(rec.Body.Bytes(), &list); err != nil {
		t.Fatalf("decode list %q: %v", rec.Body.String(), err)
	}
	return list
}

func TestReorderBookingTodos(t *testing.T) {
	resetDB(t)
	owner, token := createTestUser(t, "owner@example.com")
	trip := createTestTrip(t, owner.ID, 0)
	tripID := trip.ID.String()

	a := addCustomTodo(t, token, tripID, "Museum tickets")
	b := addCustomTodo(t, token, tripID, "Train passes")
	c := addCustomTodo(t, token, tripID, "Dinner reservation")

	rec := doJSON(t, "PUT", "/api/v1/trips/"+tripID+"/booking-todos/order", token, map[string]any{
		"todo_ids": []string{c, a, b},
	})
	if rec.Code != http.StatusNoContent {
		t.Fatalf("reorder = %d: %s", rec.Code, rec.Body.String())
	}

	// The order must come back through the app's own load path (sync), which
	// also proves a sync doesn't clobber user-assigned positions.
	todos := listTodosViaSync(t, token, tripID)
	if len(todos) != 3 {
		t.Fatalf("todos = %d, want 3", len(todos))
	}
	wantOrder := []string{c, a, b}
	for i, todo := range todos {
		if todo["id"] != wantOrder[i] {
			t.Fatalf("todos[%d] = %v, want %s", i, todo["id"], wantOrder[i])
		}
		if pos := todo["position"].(float64); int(pos) != i {
			t.Fatalf("todos[%d] position = %v, want %d", i, pos, i)
		}
	}
}

func TestReorderBookingTodosValidation(t *testing.T) {
	resetDB(t)
	owner, token := createTestUser(t, "owner@example.com")
	trip := createTestTrip(t, owner.ID, 0)
	tripID := trip.ID.String()
	a := addCustomTodo(t, token, tripID, "Museum tickets")

	cases := []struct {
		name string
		body map[string]any
		want int
	}{
		{"empty list", map[string]any{"todo_ids": []string{}}, http.StatusBadRequest},
		{"unknown id", map[string]any{"todo_ids": []string{uuid.NewString()}}, http.StatusConflict},
		{"malformed id", map[string]any{"todo_ids": []string{"not-a-uuid"}}, http.StatusConflict},
		{"duplicate id", map[string]any{"todo_ids": []string{a, a}}, http.StatusConflict},
	}
	for _, tc := range cases {
		rec := doJSON(t, "PUT", "/api/v1/trips/"+tripID+"/booking-todos/order", token, tc.body)
		if rec.Code != tc.want {
			t.Fatalf("%s = %d, want %d: %s", tc.name, rec.Code, tc.want, rec.Body.String())
		}
	}

	// A subset that omits some todos is valid: only the submitted rows are
	// renumbered (the client sends its residual list, not the full set).
	addCustomTodo(t, token, tripID, "Train passes")
	rec := doJSON(t, "PUT", "/api/v1/trips/"+tripID+"/booking-todos/order", token, map[string]any{
		"todo_ids": []string{a},
	})
	if rec.Code != http.StatusNoContent {
		t.Fatalf("subset reorder = %d: %s", rec.Code, rec.Body.String())
	}

	// Strangers get the usual 404; anonymous gets 401.
	_, strangerToken := createTestUser(t, "stranger@example.com")
	if rec := doJSON(t, "PUT", "/api/v1/trips/"+tripID+"/booking-todos/order", strangerToken, map[string]any{
		"todo_ids": []string{a},
	}); rec.Code != http.StatusNotFound {
		t.Fatalf("stranger reorder = %d, want 404", rec.Code)
	}
	if rec := doJSON(t, "PUT", "/api/v1/trips/"+tripID+"/booking-todos/order", "", map[string]any{
		"todo_ids": []string{a},
	}); rec.Code != http.StatusUnauthorized {
		t.Fatalf("anonymous reorder = %d, want 401", rec.Code)
	}
}
