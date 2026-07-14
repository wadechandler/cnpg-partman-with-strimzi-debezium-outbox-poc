// Command event-generator publishes sample domain events to DLQ topics.
package main

import (
	"context"
	"flag"
	"fmt"
	"log"
	"os"
	"os/signal"
	"strings"
	"syscall"
	"time"

	kafkago "github.com/segmentio/kafka-go"

	"github.com/wadechandler/cnpg-partman-with-strimzi-debezium-outbox-poc/internal/demoids"
	"github.com/wadechandler/cnpg-partman-with-strimzi-debezium-outbox-poc/internal/event"
	pockafka "github.com/wadechandler/cnpg-partman-with-strimzi-debezium-outbox-poc/internal/kafka"
)

func main() {
	var (
		bootstrap = flag.String("bootstrap-servers", "localhost:30092", "Kafka bootstrap servers (comma-separated)")
		count     = flag.Int("count", 10, "Number of events to publish (per selected DLQ target when both)")
		typesFlag = flag.String("types", "all", "Comma-separated event types, or \"all\"")
		dlq       = flag.String("dlq", "both", "Target DLQ: retry|true|both")
		orgID     = flag.String("organization-id", demoids.OrganizationID, "Organization UUID")
		clientID  = flag.String("client-id", demoids.ClientID, "Client UUID")
		contactID = flag.String("contact-id", "", "Contact UUID (default: rotate demo contacts)")
		dlqReason = flag.String("dlq-reason", "simulated delivery failure", "Value for dlq-reason header")
		spread    = flag.Duration("spread", 0, "Backdate createdAt evenly across this duration (e.g. 24h)")
	)
	flag.Parse()

	types, err := parseTypes(*typesFlag)
	if err != nil {
		log.Fatalf("types: %v", err)
	}
	topics, err := parseDLQTargets(*dlq)
	if err != nil {
		log.Fatalf("dlq: %v", err)
	}
	if *count < 1 {
		log.Fatal("--count must be >= 1")
	}

	brokers := splitCSV(*bootstrap)
	if len(brokers) == 0 {
		log.Fatal("--bootstrap-servers is required")
	}

	ctx, stop := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
	defer stop()

	writers := make(map[string]*kafkago.Writer, len(topics))
	for _, topic := range topics {
		writers[topic] = pockafka.NewWriter(brokers, topic)
	}
	defer func() {
		for topic, w := range writers {
			if err := w.Close(); err != nil {
				log.Printf("close writer %s: %v", topic, err)
			}
		}
	}()

	now := time.Now().UTC()
	published := 0
	for _, topic := range topics {
		w := writers[topic]
		for i := 0; i < *count; i++ {
			if ctx.Err() != nil {
				log.Printf("interrupted after %d publishes", published)
				return
			}
			typ := types[i%len(types)]
			cid := *contactID
			if cid == "" {
				cid = demoids.ContactAt(i)
			}
			createdAt := now
			if *spread > 0 && *count > 1 {
				frac := float64(i) / float64(*count-1)
				createdAt = now.Add(-time.Duration(frac * float64(*spread)))
			} else if *spread > 0 {
				createdAt = now.Add(-*spread)
			}

			env, err := event.NewSample(typ, *orgID, *clientID, cid, createdAt)
			if err != nil {
				log.Fatalf("sample: %v", err)
			}
			body, err := event.Encode(env)
			if err != nil {
				log.Fatalf("encode: %v", err)
			}
			headers := map[string]string{
				pockafka.HeaderDLQReason: *dlqReason,
			}
			if err := pockafka.Publish(ctx, w, []byte(env.ID), body, headers); err != nil {
				log.Fatalf("publish to %s: %v", topic, err)
			}
			published++
			log.Printf("published id=%s type=%s topic=%s createdAt=%s",
				env.ID, env.EventType, topic, env.CreatedAt.Format(time.RFC3339Nano))
		}
	}
	log.Printf("done: published %d event(s) to %d topic(s)", published, len(topics))
}

func parseTypes(s string) ([]string, error) {
	s = strings.TrimSpace(s)
	if s == "" || strings.EqualFold(s, "all") {
		return append([]string(nil), event.AllTypes...), nil
	}
	parts := splitCSV(s)
	out := make([]string, 0, len(parts))
	for _, p := range parts {
		if !event.ValidType(p) {
			return nil, fmt.Errorf("unknown event type %q (known: %s)", p, strings.Join(event.AllTypes, ", "))
		}
		out = append(out, p)
	}
	if len(out) == 0 {
		return nil, fmt.Errorf("no event types selected")
	}
	return out, nil
}

func parseDLQTargets(s string) ([]string, error) {
	switch strings.ToLower(strings.TrimSpace(s)) {
	case "retry":
		return []string{pockafka.TopicRetryDLQ}, nil
	case "true":
		return []string{pockafka.TopicTrueDLQ}, nil
	case "both":
		return []string{pockafka.TopicRetryDLQ, pockafka.TopicTrueDLQ}, nil
	default:
		return nil, fmt.Errorf("want retry|true|both, got %q", s)
	}
}

func splitCSV(s string) []string {
	parts := strings.Split(s, ",")
	out := make([]string, 0, len(parts))
	for _, p := range parts {
		p = strings.TrimSpace(p)
		if p != "" {
			out = append(out, p)
		}
	}
	return out
}
