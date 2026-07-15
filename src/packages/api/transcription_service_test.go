package main

import (
	"context"
	"io"
	"mime"
	"mime/multipart"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"
)

// capturedTranscribeRequest is what the stub records about the outbound
// multipart request the service builds.
type capturedTranscribeRequest struct {
	authHeader string
	filename   string
	fileBytes  []byte
	model      string
}

// stubTranscription serves a canned {"text": ...} payload and captures the
// multipart request, mirroring the stubDuffel base-URL seam.
func stubTranscription(t *testing.T, status int, respBody string, captured *capturedTranscribeRequest) *TranscriptionService {
	t.Helper()
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		captured.authHeader = r.Header.Get("Authorization")

		mediaType, params, err := mime.ParseMediaType(r.Header.Get("Content-Type"))
		if err != nil || mediaType != "multipart/form-data" {
			t.Errorf("upstream Content-Type = %q, want multipart/form-data", r.Header.Get("Content-Type"))
		}
		mr := multipart.NewReader(r.Body, params["boundary"])
		for {
			part, err := mr.NextPart()
			if err == io.EOF {
				break
			}
			if err != nil {
				t.Errorf("reading multipart: %v", err)
				break
			}
			data, _ := io.ReadAll(part)
			switch part.FormName() {
			case "file":
				captured.filename = part.FileName()
				captured.fileBytes = data
			case "model":
				captured.model = string(data)
			}
		}

		w.Header().Set("Content-Type", "application/json")
		w.WriteHeader(status)
		w.Write([]byte(respBody))
	}))
	t.Cleanup(srv.Close)
	return &TranscriptionService{
		APIKey:  "test-key",
		BaseURL: srv.URL,
		Model:   "whisper-large-v3-turbo",
		Client:  &http.Client{Timeout: 5 * time.Second},
	}
}

func TestTranscribeSendsMultipartAndParsesText(t *testing.T) {
	var captured capturedTranscribeRequest
	svc := stubTranscription(t, http.StatusOK, `{"text":" hello world "}`, &captured)

	audio := []byte{0x1a, 0x45, 0xdf, 0xa3} // arbitrary bytes; format is opaque
	text, err := svc.Transcribe(context.Background(), audio, "audio/webm")
	if err != nil {
		t.Fatalf("Transcribe: %v", err)
	}
	if text != "hello world" {
		t.Fatalf("text = %q, want trimmed %q", text, "hello world")
	}
	if captured.authHeader != "Bearer test-key" {
		t.Fatalf("auth header = %q, want Bearer test-key", captured.authHeader)
	}
	if captured.model != "whisper-large-v3-turbo" {
		t.Fatalf("model field = %q", captured.model)
	}
	if captured.filename != "audio.webm" {
		t.Fatalf("filename = %q, want audio.webm", captured.filename)
	}
	if string(captured.fileBytes) != string(audio) {
		t.Fatal("uploaded file bytes do not match input audio")
	}
}

// Whisper-family endpoints key the container format off the filename
// extension, so each allowed MIME must map to a distinct name.
func TestTranscribeFilenameFollowsMime(t *testing.T) {
	cases := map[string]string{
		"audio/webm": "audio.webm",
		"audio/ogg":  "audio.ogg",
		"audio/mp4":  "audio.mp4",
		"audio/wav":  "audio.wav",
	}
	for mimeType, wantName := range cases {
		var captured capturedTranscribeRequest
		svc := stubTranscription(t, http.StatusOK, `{"text":"ok"}`, &captured)
		if _, err := svc.Transcribe(context.Background(), []byte("a"), mimeType); err != nil {
			t.Fatalf("%s: %v", mimeType, err)
		}
		if captured.filename != wantName {
			t.Fatalf("%s: filename = %q, want %q", mimeType, captured.filename, wantName)
		}
	}
}

func TestTranscribeRejectsUnsupportedMime(t *testing.T) {
	var captured capturedTranscribeRequest
	svc := stubTranscription(t, http.StatusOK, `{"text":"ok"}`, &captured)
	if _, err := svc.Transcribe(context.Background(), []byte("a"), "video/mp4"); err == nil {
		t.Fatal("want error for unsupported mime type")
	}
}

func TestTranscribeUpstreamErrorSurfaces(t *testing.T) {
	var captured capturedTranscribeRequest
	svc := stubTranscription(t, http.StatusInternalServerError, `{"error":"boom"}`, &captured)
	_, err := svc.Transcribe(context.Background(), []byte("a"), "audio/webm")
	if err == nil {
		t.Fatal("want error on upstream 500")
	}
	if !strings.Contains(err.Error(), "500") {
		t.Fatalf("error should carry upstream status, got: %v", err)
	}
}

func TestTranscribeUnconfigured(t *testing.T) {
	svc := &TranscriptionService{Client: http.DefaultClient}
	if svc.Configured() {
		t.Fatal("empty key should report unconfigured")
	}
	if _, err := svc.Transcribe(context.Background(), []byte("a"), "audio/webm"); err == nil {
		t.Fatal("want error when key is missing")
	}
}
