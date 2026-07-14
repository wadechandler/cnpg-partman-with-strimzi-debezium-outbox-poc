// Package demoids provides stable demo UUIDs for org/client/contacts.
package demoids

// Stable demo tenant identifiers (RFC 4122 version-4 shape, fixed for replayability).
const (
	OrganizationID = "a1000000-0000-4000-8000-000000000001"
	ClientID       = "a2000000-0000-4000-8000-000000000001"
)

// Demo contact IDs used by the event generator when --contact-id is omitted.
const (
	ContactAlice = "b1000000-0000-4000-8000-000000000001"
	ContactBob   = "b1000000-0000-4000-8000-000000000002"
	ContactCarol = "b1000000-0000-4000-8000-000000000003"
)

// Contacts is the ordered list of demo contacts.
var Contacts = []string{
	ContactAlice,
	ContactBob,
	ContactCarol,
}

// ContactAt returns a demo contact ID by index (wraps).
func ContactAt(i int) string {
	if len(Contacts) == 0 {
		return ContactAlice
	}
	if i < 0 {
		i = -i
	}
	return Contacts[i%len(Contacts)]
}
