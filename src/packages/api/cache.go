package main

import (
	"sync"
	"time"
)

// ttlCache is a small in-memory TTL cache used to avoid repeat calls to
// billable external APIs (Google Places, Duffel place suggestions). Entries
// expire after the TTL; when the cache is full, expired entries are swept and
// arbitrary entries are dropped if it is still over capacity. Good enough for
// a cost cap — not an LRU, deliberately dependency-free.
type ttlCache[V any] struct {
	mu         sync.Mutex
	entries    map[string]ttlCacheEntry[V]
	ttl        time.Duration
	maxEntries int
}

type ttlCacheEntry[V any] struct {
	value     V
	expiresAt time.Time
}

func newTTLCache[V any](ttl time.Duration, maxEntries int) *ttlCache[V] {
	return &ttlCache[V]{
		entries:    make(map[string]ttlCacheEntry[V]),
		ttl:        ttl,
		maxEntries: maxEntries,
	}
}

func (c *ttlCache[V]) get(key string) (V, bool) {
	c.mu.Lock()
	defer c.mu.Unlock()
	e, ok := c.entries[key]
	if !ok || time.Now().After(e.expiresAt) {
		var zero V
		delete(c.entries, key)
		return zero, false
	}
	return e.value, true
}

func (c *ttlCache[V]) set(key string, value V) {
	c.mu.Lock()
	defer c.mu.Unlock()
	if len(c.entries) >= c.maxEntries {
		now := time.Now()
		for k, e := range c.entries {
			if now.After(e.expiresAt) {
				delete(c.entries, k)
			}
		}
		for k := range c.entries {
			if len(c.entries) < c.maxEntries {
				break
			}
			delete(c.entries, k)
		}
	}
	c.entries[key] = ttlCacheEntry[V]{value: value, expiresAt: time.Now().Add(c.ttl)}
}
