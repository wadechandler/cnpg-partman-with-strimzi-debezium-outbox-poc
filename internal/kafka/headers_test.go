package kafka_test

import (
	"testing"

	kafkago "github.com/segmentio/kafka-go"

	"github.com/wadechandler/cnpg-partman-with-strimzi-debezium-outbox-poc/internal/kafka"
)

func TestHeadersRoundTrip(t *testing.T) {
	t.Parallel()

	in := map[string]string{
		kafka.HeaderDLQReason:   "simulated delivery failure",
		kafka.HeaderRetryReason: "ops requeue",
	}
	headers := kafka.MapToHeaders(in)
	out := kafka.HeadersToMap(headers)

	if out[kafka.HeaderDLQReason] != in[kafka.HeaderDLQReason] {
		t.Fatalf("dlq-reason: got %q want %q", out[kafka.HeaderDLQReason], in[kafka.HeaderDLQReason])
	}
	if kafka.GetHeader(headers, kafka.HeaderRetryReason) != in[kafka.HeaderRetryReason] {
		t.Fatalf("retry-reason mismatch")
	}
}

func TestGetHeaderMissing(t *testing.T) {
	t.Parallel()
	if got := kafka.GetHeader([]kafkago.Header{}, kafka.HeaderDLQReason); got != "" {
		t.Fatalf("expected empty, got %q", got)
	}
}
