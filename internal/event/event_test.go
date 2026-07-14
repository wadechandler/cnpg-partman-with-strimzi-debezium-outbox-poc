package event_test

import (
	"encoding/json"
	"testing"
	"time"

	"github.com/wadechandler/cnpg-partman-with-strimzi-debezium-outbox-poc/internal/event"
)

func TestEncodeDecodeRoundTrip(t *testing.T) {
	t.Parallel()

	created := time.Date(2026, 7, 12, 14, 30, 0, 0, time.UTC)
	payload := json.RawMessage(`{"systolicMmHg":120,"diastolicMmHg":80}`)
	orig := &event.Envelope{
		ID:             "11111111-1111-1111-1111-111111111111",
		OrganizationID: "22222222-2222-2222-2222-222222222222",
		ClientID:       "33333333-3333-3333-3333-333333333333",
		ContactID:      "44444444-4444-4444-4444-444444444444",
		EventType:      event.TypeBloodPressureReading,
		SchemaVersion:  1,
		CreatedAt:      created,
		Payload:        payload,
	}

	data, err := event.Encode(orig)
	if err != nil {
		t.Fatalf("Encode: %v", err)
	}

	// Wire JSON must use camelCase keys.
	var raw map[string]json.RawMessage
	if err := json.Unmarshal(data, &raw); err != nil {
		t.Fatalf("unmarshal raw: %v", err)
	}
	for _, key := range []string{"organizationId", "clientId", "contactId", "eventType", "schemaVersion", "createdAt"} {
		if _, ok := raw[key]; !ok {
			t.Errorf("missing camelCase key %q in %s", key, data)
		}
	}

	got, err := event.Decode(data)
	if err != nil {
		t.Fatalf("Decode: %v", err)
	}

	if got.ID != orig.ID ||
		got.OrganizationID != orig.OrganizationID ||
		got.ClientID != orig.ClientID ||
		got.ContactID != orig.ContactID ||
		got.EventType != orig.EventType ||
		got.SchemaVersion != orig.SchemaVersion {
		t.Fatalf("round-trip mismatch:\n got %+v\nwant %+v", got, orig)
	}
	if !got.CreatedAt.Equal(orig.CreatedAt) {
		t.Fatalf("createdAt: got %v want %v", got.CreatedAt, orig.CreatedAt)
	}
	if string(got.Payload) != string(orig.Payload) {
		t.Fatalf("payload: got %s want %s", got.Payload, orig.Payload)
	}
}

func TestSamplePayloadAllTypes(t *testing.T) {
	t.Parallel()

	for _, typ := range event.AllTypes {
		typ := typ
		t.Run(typ, func(t *testing.T) {
			t.Parallel()
			p, err := event.SamplePayload(typ)
			if err != nil {
				t.Fatalf("SamplePayload(%q): %v", typ, err)
			}
			if !json.Valid(p) {
				t.Fatalf("invalid JSON payload for %q: %s", typ, p)
			}
			env, err := event.NewSample(typ, "org", "client", "contact", time.Time{})
			if err != nil {
				t.Fatalf("NewSample(%q): %v", typ, err)
			}
			if env.EventType != typ || env.SchemaVersion != 1 {
				t.Fatalf("unexpected sample: %+v", env)
			}
		})
	}
}

func TestSamplePayloadUnknown(t *testing.T) {
	t.Parallel()
	if _, err := event.SamplePayload("unknown.type"); err == nil {
		t.Fatal("expected error for unknown type")
	}
}
