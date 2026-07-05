package main

import (
	"strings"
	"testing"

	anthropic "github.com/anthropics/anthropic-sdk-go"
)

// The /plan loop moves its conversation cache breakpoint each iteration by
// zeroing the previous marker in place. That only works if a zeroed
// CacheControlEphemeralParam is dropped from the request JSON entirely —
// otherwise stale markers accumulate and the API 400s at the 5th breakpoint.
func TestZeroedCacheControlOmittedFromJSON(t *testing.T) {
	msg := anthropic.NewUserMessage(anthropic.NewToolResultBlock("tool_1", "result", false))
	blocks := msg.Content
	cc := blocks[len(blocks)-1].GetCacheControl()
	if cc == nil {
		t.Fatal("tool result block has no addressable cache control")
	}

	*cc = anthropic.NewCacheControlEphemeralParam()
	withMarker, err := msg.MarshalJSON()
	if err != nil {
		t.Fatal(err)
	}
	if !strings.Contains(string(withMarker), "cache_control") {
		t.Fatalf("set marker missing from JSON: %s", withMarker)
	}

	*cc = anthropic.CacheControlEphemeralParam{}
	cleared, err := msg.MarshalJSON()
	if err != nil {
		t.Fatal(err)
	}
	if strings.Contains(string(cleared), "cache_control") {
		t.Fatalf("zeroed marker still present in JSON: %s", cleared)
	}
}
