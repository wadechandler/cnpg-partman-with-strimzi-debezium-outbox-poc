// Package kafka provides thin helpers around segmentio/kafka-go.
//
// We use github.com/segmentio/kafka-go rather than the Confluent librdkafka
// binding because it is pure Go (no CGO), builds cleanly for multi-arch
// Linux containers (amd64/arm64), and is adequate for this POC's produce/
// consume loops without a heavyweight client.
package kafka

import (
	"context"
	"fmt"
	"time"

	kafkago "github.com/segmentio/kafka-go"
)

// Header names of interest for DLQ / retry flows.
const (
	HeaderDLQReason   = "dlq-reason"
	HeaderRetryReason = "retry-reason"
)

// Topic names used by this POC.
const (
	TopicRetryDLQ = "cnpg-outbox-poc.events.retry-dlq"
	TopicTrueDLQ  = "cnpg-outbox-poc.events.true-dlq"
	TopicRetry    = "cnpg-outbox-poc.events.retry"
)

// HeadersToMap converts kafka-go headers to a string map (last value wins).
func HeadersToMap(headers []kafkago.Header) map[string]string {
	out := make(map[string]string, len(headers))
	for _, h := range headers {
		out[h.Key] = string(h.Value)
	}
	return out
}

// MapToHeaders converts a string map to kafka-go headers.
func MapToHeaders(m map[string]string) []kafkago.Header {
	if len(m) == 0 {
		return nil
	}
	out := make([]kafkago.Header, 0, len(m))
	for k, v := range m {
		out = append(out, kafkago.Header{Key: k, Value: []byte(v)})
	}
	return out
}

// GetHeader returns the value for key, or "" if absent.
func GetHeader(headers []kafkago.Header, key string) string {
	for _, h := range headers {
		if h.Key == key {
			return string(h.Value)
		}
	}
	return ""
}

// NewWriter builds a kafka-go Writer for the given brokers and topic.
func NewWriter(brokers []string, topic string) *kafkago.Writer {
	return &kafkago.Writer{
		Addr:         kafkago.TCP(brokers...),
		Topic:        topic,
		Balancer:     &kafkago.LeastBytes{},
		RequiredAcks: kafkago.RequireOne,
		Async:        false,
	}
}

// NewReader builds a kafka-go Reader for the given brokers, topic, and group.
// CommitInterval is 0 so offsets are committed only via Commit (FetchMessage +
// explicit CommitMessages), matching commit-after-DB ingest.
func NewReader(brokers []string, topic, groupID string) *kafkago.Reader {
	return kafkago.NewReader(kafkago.ReaderConfig{
		Brokers:        brokers,
		Topic:          topic,
		GroupID:        groupID,
		MinBytes:       1,
		MaxBytes:       10e6,
		CommitInterval: 0,
		StartOffset:    kafkago.FirstOffset,
	})
}

// Publish writes a single message with optional headers.
func Publish(ctx context.Context, w *kafkago.Writer, key, value []byte, headers map[string]string) error {
	if w == nil {
		return fmt.Errorf("kafka: nil writer")
	}
	msg := kafkago.Message{
		Key:     key,
		Value:   value,
		Headers: MapToHeaders(headers),
		Time:    time.Now().UTC(),
	}
	if err := w.WriteMessages(ctx, msg); err != nil {
		return fmt.Errorf("kafka: publish: %w", err)
	}
	return nil
}

// FetchOne reads one message (blocking until ctx done or a message arrives).
func FetchOne(ctx context.Context, r *kafkago.Reader) (kafkago.Message, error) {
	if r == nil {
		return kafkago.Message{}, fmt.Errorf("kafka: nil reader")
	}
	msg, err := r.FetchMessage(ctx)
	if err != nil {
		return kafkago.Message{}, fmt.Errorf("kafka: fetch: %w", err)
	}
	return msg, nil
}

// Commit commits offsets for the given messages (typically a flushed ingest batch).
func Commit(ctx context.Context, r *kafkago.Reader, msgs ...kafkago.Message) error {
	if r == nil {
		return fmt.Errorf("kafka: nil reader")
	}
	if len(msgs) == 0 {
		return nil
	}
	if err := r.CommitMessages(ctx, msgs...); err != nil {
		return fmt.Errorf("kafka: commit: %w", err)
	}
	return nil
}
