package main

import (
	"fmt"
	"testing"
	"time"
)

func TestTTLCacheHitAndExpiry(t *testing.T) {
	c := newTTLCache[string](50*time.Millisecond, 10)

	if _, ok := c.get("missing"); ok {
		t.Fatal("empty cache should miss")
	}

	c.set("k", "v")
	if got, ok := c.get("k"); !ok || got != "v" {
		t.Fatalf("get after set = (%q, %v), want (v, true)", got, ok)
	}

	time.Sleep(60 * time.Millisecond)
	if _, ok := c.get("k"); ok {
		t.Fatal("entry past TTL should miss")
	}
}

func TestTTLCacheEvictsAtCapacity(t *testing.T) {
	c := newTTLCache[int](time.Minute, 5)
	for i := 0; i < 25; i++ {
		c.set(fmt.Sprintf("key-%d", i), i)
	}
	c.mu.Lock()
	size := len(c.entries)
	c.mu.Unlock()
	if size > 5 {
		t.Fatalf("cache size = %d, want <= capacity 5", size)
	}
}
