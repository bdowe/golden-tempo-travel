package main

import "testing"

// TestShouldWarnSigningSecrets covers the pure decision behind the production
// startup warning: warn only when running in production with neither signing
// secret set. Anything else (dev, or at least one secret present) stays quiet.
func TestShouldWarnSigningSecrets(t *testing.T) {
	tests := []struct {
		name         string
		goEnv        string
		exportSecret string
		unsubSecret  string
		want         bool
	}{
		{name: "production, both empty -> warn", goEnv: "production", want: true},
		{name: "production, whitespace-only secrets -> warn", goEnv: "production", exportSecret: "  ", unsubSecret: "\t", want: true},
		{name: "production, export set -> quiet", goEnv: "production", exportSecret: "abc", want: false},
		{name: "production, unsub set -> quiet", goEnv: "production", unsubSecret: "abc", want: false},
		{name: "production, both set -> quiet", goEnv: "production", exportSecret: "abc", unsubSecret: "def", want: false},
		{name: "dev, both empty -> quiet", goEnv: "", want: false},
		{name: "development env, both empty -> quiet", goEnv: "development", want: false},
		{name: "staging, both empty -> quiet", goEnv: "staging", want: false},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			if got := shouldWarnSigningSecrets(tt.goEnv, tt.exportSecret, tt.unsubSecret); got != tt.want {
				t.Errorf("shouldWarnSigningSecrets(%q, %q, %q) = %v, want %v", tt.goEnv, tt.exportSecret, tt.unsubSecret, got, tt.want)
			}
		})
	}
}
