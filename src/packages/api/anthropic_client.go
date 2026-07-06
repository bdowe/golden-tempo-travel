package main

import (
	"os"

	anthropic "github.com/anthropics/anthropic-sdk-go"
	"github.com/anthropics/anthropic-sdk-go/option"
)

// newAnthropicClient builds the Anthropic client used by the /plan agent and
// the admin local-content ingest. An optional ANTHROPIC_BASE_URL env var
// redirects API traffic — the seam a fake-Anthropic test harness needs (the
// free-cap integration test drives real /plan sessions through it). Unset
// means production behavior, byte-identical to before. The SDK's default
// option chain also reads ANTHROPIC_BASE_URL, but pinning it explicitly here
// keeps the seam independent of SDK-version behavior and documents it at the
// one place clients are constructed.
func newAnthropicClient(apiKey string) anthropic.Client {
	opts := []option.RequestOption{option.WithAPIKey(apiKey)}
	if base := os.Getenv("ANTHROPIC_BASE_URL"); base != "" {
		opts = append(opts, option.WithBaseURL(base))
	}
	return anthropic.NewClient(opts...)
}
