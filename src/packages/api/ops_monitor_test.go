package main

import (
	"context"
	"encoding/json"
	"sync"
	"testing"
	"time"

	"github.com/google/uuid"

	"travel-route-planner/store"
)

// fakeMailbox records ops-alert emails the monitor would send.
type fakeMailbox struct {
	mu   sync.Mutex
	sent []struct{ to, subject, body string }
}

func (m *fakeMailbox) send(to, subject, body string) error {
	m.mu.Lock()
	defer m.mu.Unlock()
	m.sent = append(m.sent, struct{ to, subject, body string }{to, subject, body})
	return nil
}

func (m *fakeMailbox) count() int {
	m.mu.Lock()
	defer m.mu.Unlock()
	return len(m.sent)
}

// newTestMonitor wires a monitor to the real store (test DB) with a controllable
// DB-ping and a fake mailbox.
func newTestMonitor(mailbox *fakeMailbox, emailOn bool, ping *bool) *healthMonitor {
	return &healthMonitor{
		interval: time.Minute,
		listAdmins: func(ctx context.Context) ([]store.ListAdminUsersRow, error) {
			return store.New(dbPool).ListAdminUsers(ctx)
		},
		insertNotify: func(ctx context.Context, p store.InsertNotificationParams) error {
			_, err := store.New(dbPool).InsertNotification(ctx, p)
			return err
		},
		sendEmail:    mailbox.send,
		emailEnabled: func() bool { return emailOn },
		pingDBFn:     func(context.Context) bool { return *ping },
	}
}

func opsNotifCount(t *testing.T, u uuid.UUID, typ string) int {
	t.Helper()
	rows, err := store.New(dbPool).ListNotificationsByUser(context.Background(),
		store.ListNotificationsByUserParams{UserID: u, Limit: 50})
	if err != nil {
		t.Fatalf("list notifications: %v", err)
	}
	n := 0
	for _, r := range rows {
		if r.Type == typ {
			n++
		}
	}
	return n
}

// A healthy->degraded->healthy sequence fires exactly one alert per transition
// (in-app notification per admin + one email per admin), and a repeat degraded
// tick fires nothing. Only admins are notified.
func TestHealthMonitorTransitions(t *testing.T) {
	requireDB(t)
	resetDB(t)
	writeFreshHeartbeat(t, time.Now()) // isolate the DB signal from backups

	admin1, _ := createTestUser(t, "opsadmin1@example.com")
	admin2, _ := createTestUser(t, "opsadmin2@example.com")
	makeAdmin(t, admin1.ID)
	makeAdmin(t, admin2.ID)
	nonAdmin, _ := createTestUser(t, "regular@example.com")

	mailbox := &fakeMailbox{}
	dbUp := true
	m := newTestMonitor(mailbox, true, &dbUp)
	ctx := context.Background()
	now := time.Now()

	// Tick 1: healthy, starting state healthy => no transition, no alerts.
	m.runOnce(ctx, now)
	if c := opsNotifCount(t, admin1.ID, notificationTypeOpsAlert); c != 0 {
		t.Fatalf("healthy tick alerted admin1: %d", c)
	}
	if mailbox.count() != 0 {
		t.Fatalf("healthy tick emailed: %d", mailbox.count())
	}

	// Tick 2: DB goes down => degraded transition => one alert per admin + email.
	dbUp = false
	m.runOnce(ctx, now)
	for _, a := range []uuid.UUID{admin1.ID, admin2.ID} {
		if c := opsNotifCount(t, a, notificationTypeOpsAlert); c != 1 {
			t.Fatalf("admin %s ops_alert count = %d, want 1", a, c)
		}
	}
	if c := opsNotifCount(t, nonAdmin.ID, notificationTypeOpsAlert); c != 0 {
		t.Fatalf("non-admin received ops_alert: %d", c)
	}
	if mailbox.count() != 2 {
		t.Fatalf("degrade emails = %d, want 2 (one per admin)", mailbox.count())
	}
	// Payload carries degraded + reasons.
	rows, _ := store.New(dbPool).ListNotificationsByUser(ctx,
		store.ListNotificationsByUserParams{UserID: admin1.ID, Limit: 50})
	var p map[string]any
	_ = json.Unmarshal(rows[0].Payload, &p)
	if p["degraded"] != true {
		t.Fatalf("payload degraded = %v, want true", p["degraded"])
	}

	// Tick 3: still degraded => no transition => no new alerts/emails (dedup).
	m.runOnce(ctx, now)
	if c := opsNotifCount(t, admin1.ID, notificationTypeOpsAlert); c != 1 {
		t.Fatalf("repeat degraded tick re-alerted: count = %d, want 1", c)
	}
	if mailbox.count() != 2 {
		t.Fatalf("repeat degraded tick re-emailed: %d, want 2", mailbox.count())
	}

	// Tick 4: DB recovers => recovery transition => ops_recovered per admin + email.
	dbUp = true
	m.runOnce(ctx, now)
	for _, a := range []uuid.UUID{admin1.ID, admin2.ID} {
		if c := opsNotifCount(t, a, notificationTypeOpsRecovered); c != 1 {
			t.Fatalf("admin %s ops_recovered count = %d, want 1", a, c)
		}
	}
	if mailbox.count() != 4 {
		t.Fatalf("recovery emails total = %d, want 4", mailbox.count())
	}
}

// With SMTP unconfigured, a transition still writes in-app notifications but
// sends no email (email is the only gated channel).
func TestHealthMonitorNoEmailWhenUnconfigured(t *testing.T) {
	requireDB(t)
	resetDB(t)
	writeFreshHeartbeat(t, time.Now())

	admin, _ := createTestUser(t, "opsadmin@example.com")
	makeAdmin(t, admin.ID)

	mailbox := &fakeMailbox{}
	dbUp := false // start degraded on first tick
	m := newTestMonitor(mailbox, false /* email off */, &dbUp)

	m.runOnce(context.Background(), time.Now())

	if c := opsNotifCount(t, admin.ID, notificationTypeOpsAlert); c != 1 {
		t.Fatalf("in-app ops_alert count = %d, want 1", c)
	}
	if mailbox.count() != 0 {
		t.Fatalf("email sent while SMTP unconfigured: %d", mailbox.count())
	}
}
