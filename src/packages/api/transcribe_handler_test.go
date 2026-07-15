package main

import (
	"bytes"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"testing"
	"time"
)

// swapTranscription swaps the process-wide singleton for a test and restores
// it afterward (same pattern as other singleton-backed handler tests).
func swapTranscription(t *testing.T, svc *TranscriptionService) {
	t.Helper()
	prev := transcriptionService
	transcriptionService = svc
	t.Cleanup(func() { transcriptionService = prev })
}

func postTranscribe(contentType string, body []byte) *httptest.ResponseRecorder {
	req := httptest.NewRequest("POST", "/api/v1/transcribe", bytes.NewReader(body))
	if contentType != "" {
		req.Header.Set("Content-Type", contentType)
	}
	rec := httptest.NewRecorder()
	transcribeHandler(rec, req)
	return rec
}

func TestTranscribeHandlerUnconfigured(t *testing.T) {
	swapTranscription(t, &TranscriptionService{Client: http.DefaultClient})

	rec := postTranscribe("audio/webm", []byte("audio"))
	if rec.Code != http.StatusServiceUnavailable {
		t.Fatalf("status = %d, want 503", rec.Code)
	}
	var resp Response
	if err := json.Unmarshal(rec.Body.Bytes(), &resp); err != nil {
		t.Fatalf("bad JSON: %v", err)
	}
	if resp.Status != "error" || resp.Message != "Transcription is not configured" {
		t.Fatalf("resp = %+v, want degraded-mode configured error", resp)
	}
}

func TestTranscribeHandlerValidation(t *testing.T) {
	var captured capturedTranscribeRequest
	swapTranscription(t, stubTranscription(t, http.StatusOK, `{"text":"ok"}`, &captured))

	cases := []struct {
		name        string
		contentType string
		body        []byte
		wantCode    int
	}{
		{"missing content type", "", []byte("audio"), http.StatusBadRequest},
		{"unsupported content type", "text/plain", []byte("audio"), http.StatusBadRequest},
		{"empty body", "audio/webm", nil, http.StatusBadRequest},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			if rec := postTranscribe(tc.contentType, tc.body); rec.Code != tc.wantCode {
				t.Fatalf("status = %d, want %d", rec.Code, tc.wantCode)
			}
		})
	}
}

func TestTranscribeHandlerHappyPath(t *testing.T) {
	var captured capturedTranscribeRequest
	swapTranscription(t, stubTranscription(t, http.StatusOK, `{"text":"two days in athens"}`, &captured))

	// MediaRecorder reports parameters; the handler must strip them.
	rec := postTranscribe("audio/webm;codecs=opus", []byte("fake-opus"))
	if rec.Code != http.StatusOK {
		t.Fatalf("status = %d, want 200 (body: %s)", rec.Code, rec.Body.String())
	}
	var resp TranscribeResponse
	if err := json.Unmarshal(rec.Body.Bytes(), &resp); err != nil {
		t.Fatalf("bad JSON: %v", err)
	}
	if resp.Text != "two days in athens" || resp.Status != "success" {
		t.Fatalf("resp = %+v", resp)
	}
	if captured.filename != "audio.webm" {
		t.Fatalf("upstream filename = %q, want audio.webm", captured.filename)
	}
	if string(captured.fileBytes) != "fake-opus" {
		t.Fatal("audio bytes not forwarded verbatim")
	}
}

func TestTranscribeHandlerUpstreamFailure(t *testing.T) {
	var captured capturedTranscribeRequest
	swapTranscription(t, stubTranscription(t, http.StatusTooManyRequests, `{"error":"rate limited"}`, &captured))

	rec := postTranscribe("audio/ogg", []byte("fake-ogg"))
	if rec.Code != http.StatusBadGateway {
		t.Fatalf("status = %d, want 502", rec.Code)
	}
	var resp Response
	if err := json.Unmarshal(rec.Body.Bytes(), &resp); err != nil {
		t.Fatalf("bad JSON: %v", err)
	}
	if resp.Message != "Failed to transcribe audio" {
		t.Fatalf("message = %q, want generic upstream-failure message", resp.Message)
	}
}

func TestTranscribeAvailabilityHandler(t *testing.T) {
	cases := []struct {
		key  string
		want bool
	}{
		{"", false},
		{"gsk_test", true},
	}
	for _, tc := range cases {
		swapTranscription(t, &TranscriptionService{
			APIKey: tc.key,
			Client: &http.Client{Timeout: time.Second},
		})
		rec := httptest.NewRecorder()
		transcribeAvailabilityHandler(rec, httptest.NewRequest("GET", "/api/v1/transcribe/availability", nil))
		if rec.Code != http.StatusOK {
			t.Fatalf("status = %d, want 200", rec.Code)
		}
		var resp TranscribeAvailabilityResponse
		if err := json.Unmarshal(rec.Body.Bytes(), &resp); err != nil {
			t.Fatalf("bad JSON: %v", err)
		}
		if resp.Available != tc.want {
			t.Fatalf("available = %v with key %q, want %v", resp.Available, tc.key, tc.want)
		}
	}
}
