package main

import (
	"io"
	"mime"
	"net/http"
)

// TranscribeResponse is the success shape for POST /transcribe.
type TranscribeResponse struct {
	Text   string `json:"text"`
	Status string `json:"status"`
}

// TranscribeAvailabilityResponse tells the client whether the server-side
// dictation fallback is configured, so the mic button can be hidden up front
// instead of failing after the user has already spoken.
type TranscribeAvailabilityResponse struct {
	Available bool `json:"available"`
}

// transcribeHandler accepts a short recorded audio clip as raw request-body
// bytes (Content-Type declares the container format) and returns the
// transcribed text. It is the fallback path for browsers without built-in
// speech recognition; see specs/voice-dictation. Unauthenticated to match
// /plan, bounded by its own rate limiter and the 10 MiB body lane in
// bodyLimitMiddleware.
func transcribeHandler(w http.ResponseWriter, r *http.Request) {
	if !transcriptionService.Configured() {
		writeJSONError(w, http.StatusServiceUnavailable, "Transcription is not configured")
		return
	}

	// MediaRecorder reports types like "audio/webm;codecs=opus" — parse down
	// to the bare media type before the allowlist check.
	mediaType, _, err := mime.ParseMediaType(r.Header.Get("Content-Type"))
	if err != nil {
		writeJSONError(w, http.StatusBadRequest, "Content-Type must be a supported audio type")
		return
	}
	if _, ok := transcribeMimeExtensions[mediaType]; !ok {
		writeJSONError(w, http.StatusBadRequest, "Content-Type must be one of: audio/webm, audio/ogg, audio/mp4, audio/wav")
		return
	}

	audio, err := io.ReadAll(r.Body)
	if err != nil {
		// MaxBytesReader trips mid-read for chunked bodies over the cap.
		writeJSONError(w, http.StatusRequestEntityTooLarge, "request body too large")
		return
	}
	if len(audio) == 0 {
		writeJSONError(w, http.StatusBadRequest, "audio body is required")
		return
	}

	text, err := transcriptionService.Transcribe(r.Context(), audio, mediaType)
	if err != nil {
		ctxLog(r.Context()).Error("transcription failed", "error", err, "bytes", len(audio), "mime", mediaType)
		writeJSONError(w, http.StatusBadGateway, "Failed to transcribe audio")
		return
	}

	writeJSON(w, http.StatusOK, TranscribeResponse{Text: text, Status: "success"})
}

// transcribeAvailabilityHandler reports whether the fallback path exists.
// Always answers; leaks no key material.
func transcribeAvailabilityHandler(w http.ResponseWriter, r *http.Request) {
	writeJSON(w, http.StatusOK, TranscribeAvailabilityResponse{
		Available: transcriptionService.Configured(),
	})
}
