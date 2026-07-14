// Package event defines the wire JSON envelope for POC domain events.
package event

import (
	"encoding/json"
	"fmt"
	"time"

	"github.com/google/uuid"
)

// Event type constants (fake health-engagement POC types).
const (
	TypeBloodPressureReading = "blood_pressure.reading"
	TypePrescriptionUpdated  = "prescription.updated"
	TypeAppointmentReminder  = "appointment.reminder"
	TypeLabResultAvailable   = "lab.result.available"
	TypeWearableSync         = "wearable.sync"
)

// AllTypes lists every supported event type.
var AllTypes = []string{
	TypeBloodPressureReading,
	TypePrescriptionUpdated,
	TypeAppointmentReminder,
	TypeLabResultAvailable,
	TypeWearableSync,
}

// Envelope is the camelCase JSON event shape on the wire.
type Envelope struct {
	ID             string          `json:"id"`
	OrganizationID string          `json:"organizationId"`
	ClientID       string          `json:"clientId"`
	ContactID      string          `json:"contactId"`
	EventType      string          `json:"eventType"`
	SchemaVersion  int             `json:"schemaVersion"`
	CreatedAt      time.Time       `json:"createdAt"`
	Payload        json.RawMessage `json:"payload"`
}

// Encode marshals an envelope to JSON.
func Encode(e *Envelope) ([]byte, error) {
	if e == nil {
		return nil, fmt.Errorf("event: encode nil envelope")
	}
	b, err := json.Marshal(e)
	if err != nil {
		return nil, fmt.Errorf("event: encode: %w", err)
	}
	return b, nil
}

// Decode unmarshals JSON into an envelope.
func Decode(data []byte) (*Envelope, error) {
	var e Envelope
	if err := json.Unmarshal(data, &e); err != nil {
		return nil, fmt.Errorf("event: decode: %w", err)
	}
	return &e, nil
}

// SamplePayload returns a realistic sample payload for the given event type.
func SamplePayload(eventType string) (json.RawMessage, error) {
	var v any
	switch eventType {
	case TypeBloodPressureReading:
		v = map[string]any{
			"systolicMmHg":  128,
			"diastolicMmHg": 82,
			"pulseBpm":      72,
			"deviceId":      "bp-cuff-demo-01",
			"measuredAt":    time.Now().UTC().Format(time.RFC3339Nano),
		}
	case TypePrescriptionUpdated:
		v = map[string]any{
			"prescriptionId": "rx-demo-1001",
			"medication":     "lisinopril",
			"dosageMg":       10,
			"status":         "active",
			"updatedBy":      "pharmacist-demo",
		}
	case TypeAppointmentReminder:
		v = map[string]any{
			"appointmentId": "appt-demo-42",
			"scheduledAt":   time.Now().UTC().Add(48 * time.Hour).Format(time.RFC3339Nano),
			"location":      "Main Clinic — Room 3",
			"providerName":  "Dr. Rivera",
			"channel":       "sms",
		}
	case TypeLabResultAvailable:
		v = map[string]any{
			"labOrderId": "lab-demo-77",
			"panel":      "lipid",
			"status":     "final",
			"results": map[string]any{
				"ldlMgDl":  110,
				"hdlMgDl":  55,
				"trigMgDl": 140,
			},
		}
	case TypeWearableSync:
		v = map[string]any{
			"deviceId":     "wearable-demo-09",
			"steps":        8432,
			"heartRateAvg": 68,
			"syncedAt":     time.Now().UTC().Format(time.RFC3339Nano),
			"source":       "demo-watch",
		}
	default:
		return nil, fmt.Errorf("event: unknown type %q", eventType)
	}
	b, err := json.Marshal(v)
	if err != nil {
		return nil, fmt.Errorf("event: sample payload: %w", err)
	}
	return b, nil
}

// NewSample builds a complete sample envelope for the given type and IDs.
func NewSample(eventType, organizationID, clientID, contactID string, createdAt time.Time) (*Envelope, error) {
	payload, err := SamplePayload(eventType)
	if err != nil {
		return nil, err
	}
	if createdAt.IsZero() {
		createdAt = time.Now().UTC()
	}
	return &Envelope{
		ID:             uuid.NewString(),
		OrganizationID: organizationID,
		ClientID:       clientID,
		ContactID:      contactID,
		EventType:      eventType,
		SchemaVersion:  1,
		CreatedAt:      createdAt.UTC(),
		Payload:        payload,
	}, nil
}

// ValidType reports whether eventType is a known POC type.
func ValidType(eventType string) bool {
	for _, t := range AllTypes {
		if t == eventType {
			return true
		}
	}
	return false
}
