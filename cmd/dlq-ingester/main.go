// Command dlq-ingester consumes DLQ Kafka topics and inserts rows into Postgres.
//
// Ingest uses time-bounded batches (size + max wait). Env overrides:
//
//	INGEST_BATCH_SIZE     — max messages per flush (default 50)
//	INGEST_BATCH_MAX_WAIT — linger after the first message in a batch (default 200ms)
package main

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"log"
	"os"
	"os/signal"
	"strconv"
	"strings"
	"sync"
	"syscall"
	"time"

	"github.com/jackc/pgx/v5/pgxpool"
	kafkago "github.com/segmentio/kafka-go"

	"github.com/wadechandler/cnpg-partman-with-strimzi-debezium-outbox-poc/internal/event"
	pockafka "github.com/wadechandler/cnpg-partman-with-strimzi-debezium-outbox-poc/internal/kafka"
)

const (
	consumerGroup = "dlq-ingester"

	// defaultBatchSize is a teaching default for POC throughput, not a production tune.
	defaultBatchSize = 50
	// defaultBatchMaxWait flushes a partial batch so single messages are not delayed forever.
	defaultBatchMaxWait = 200 * time.Millisecond
	// shutdownFlushTimeout bounds the final DB+Kafka flush after cancel.
	shutdownFlushTimeout = 5 * time.Second
)

func main() {
	bootstrap := envOr("KAFKA_BOOTSTRAP", "localhost:30092")
	databaseURL := os.Getenv("DATABASE_URL")
	if databaseURL == "" {
		log.Fatal("DATABASE_URL is required")
	}

	batchSize := envIntOr("INGEST_BATCH_SIZE", defaultBatchSize)
	if batchSize < 1 {
		log.Fatal("INGEST_BATCH_SIZE must be >= 1")
	}
	batchMaxWait := envDurationOr("INGEST_BATCH_MAX_WAIT", defaultBatchMaxWait)
	if batchMaxWait < 0 {
		log.Fatal("INGEST_BATCH_MAX_WAIT must be >= 0")
	}

	brokers := splitCSV(bootstrap)
	if len(brokers) == 0 {
		log.Fatal("KAFKA_BOOTSTRAP is empty")
	}

	ctx, stop := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
	defer stop()

	pool, err := pgxpool.New(ctx, databaseURL)
	if err != nil {
		log.Fatalf("postgres connect: %v", err)
	}
	defer pool.Close()

	if err := pool.Ping(ctx); err != nil {
		log.Fatalf("postgres ping: %v", err)
	}

	targets := []struct {
		topic string
		table string
	}{
		{topic: pockafka.TopicRetryDLQ, table: "events_retry_dlq"},
		{topic: pockafka.TopicTrueDLQ, table: "events_true_dlq"},
	}

	var wg sync.WaitGroup
	errCh := make(chan error, len(targets))

	for _, t := range targets {
		t := t
		reader := pockafka.NewReader(brokers, t.topic, consumerGroup)
		wg.Add(1)
		go func() {
			defer wg.Done()
			defer func() {
				if err := reader.Close(); err != nil {
					log.Printf("close reader %s: %v", t.topic, err)
				}
			}()
			if err := consumeLoop(ctx, reader, pool, t.table, batchSize, batchMaxWait); err != nil && !errors.Is(err, context.Canceled) {
				errCh <- fmt.Errorf("%s: %w", t.topic, err)
			}
		}()
	}

	log.Printf("dlq-ingester listening on %s (group=%s batchSize=%d batchMaxWait=%s)", strings.Join([]string{
		pockafka.TopicRetryDLQ, pockafka.TopicTrueDLQ,
	}, ", "), consumerGroup, batchSize, batchMaxWait)

	<-ctx.Done()
	log.Printf("shutdown signal received, waiting for consumers...")
	wg.Wait()
	close(errCh)
	for err := range errCh {
		log.Printf("consumer error: %v", err)
	}
	log.Printf("dlq-ingester stopped")
}

func consumeLoop(ctx context.Context, reader *kafkago.Reader, pool *pgxpool.Pool, table string, batchSize int, maxWait time.Duration) error {
	batch := make([]kafkago.Message, 0, batchSize)

	flush := func(flushCtx context.Context) error {
		if len(batch) == 0 {
			return nil
		}
		if err := flushBatch(flushCtx, reader, pool, table, batch); err != nil {
			return err
		}
		batch = batch[:0]
		return nil
	}

	for {
		fetchCtx := ctx
		var cancel context.CancelFunc
		if len(batch) > 0 {
			fetchCtx, cancel = context.WithTimeout(ctx, maxWait)
		}

		msg, err := pockafka.FetchOne(fetchCtx, reader)
		if cancel != nil {
			cancel()
		}

		if err != nil {
			if len(batch) > 0 && errors.Is(err, context.DeadlineExceeded) && ctx.Err() == nil {
				if err := flush(ctx); err != nil {
					return err
				}
				continue
			}
			if errors.Is(err, context.Canceled) || errors.Is(ctx.Err(), context.Canceled) {
				flushCtx, flushCancel := context.WithTimeout(context.Background(), shutdownFlushTimeout)
				flushErr := flush(flushCtx)
				flushCancel()
				if flushErr != nil {
					return fmt.Errorf("shutdown flush: %w", flushErr)
				}
				return context.Canceled
			}
			return err
		}

		batch = append(batch, msg)
		if len(batch) >= batchSize {
			if err := flush(ctx); err != nil {
				return err
			}
		}
	}
}

func flushBatch(ctx context.Context, reader *kafkago.Reader, pool *pgxpool.Pool, table string, msgs []kafkago.Message) error {
	if len(msgs) == 0 {
		return nil
	}

	first, last := msgs[0], msgs[len(msgs)-1]
	if err := insertBatch(ctx, pool, table, msgs); err != nil {
		return fmt.Errorf("insert batch size=%d offsets=%d..%d: %w", len(msgs), first.Offset, last.Offset, err)
	}
	if err := pockafka.Commit(ctx, reader, msgs...); err != nil {
		return fmt.Errorf("commit batch size=%d offsets=%d..%d: %w", len(msgs), first.Offset, last.Offset, err)
	}
	log.Printf("ingested batch size=%d topic=%s table=%s firstOffset=%d lastOffset=%d",
		len(msgs), first.Topic, table, first.Offset, last.Offset)
	return nil
}

func insertBatch(ctx context.Context, pool *pgxpool.Pool, table string, msgs []kafkago.Message) error {
	if len(msgs) == 0 {
		return nil
	}

	const colsPerRow = 12
	args := make([]any, 0, len(msgs)*colsPerRow)
	var b strings.Builder
	b.Grow(256 + len(msgs)*96)

	// Table names are fixed constants from the caller, not user input.
	fmt.Fprintf(&b, `
INSERT INTO %s (
    id, organization_id, client_id, contact_id,
    event_type, schema_version, created_at, payload,
    headers, kafka_topic, kafka_partition, kafka_offset
) VALUES `, table)

	for i, msg := range msgs {
		env, err := event.Decode(msg.Value)
		if err != nil {
			return fmt.Errorf("decode event offset=%d: %w", msg.Offset, err)
		}
		headersJSON, err := json.Marshal(pockafka.HeadersToMap(msg.Headers))
		if err != nil {
			return fmt.Errorf("marshal headers offset=%d: %w", msg.Offset, err)
		}
		payload := env.Payload
		if len(payload) == 0 {
			payload = json.RawMessage(`{}`)
		}

		base := i*colsPerRow + 1
		if i > 0 {
			b.WriteByte(',')
		}
		fmt.Fprintf(&b, `(
    $%d::uuid, $%d::uuid, $%d::uuid, $%d::uuid,
    $%d, $%d, $%d, $%d::jsonb,
    $%d::jsonb, $%d, $%d, $%d
)`,
			base, base+1, base+2, base+3,
			base+4, base+5, base+6, base+7,
			base+8, base+9, base+10, base+11,
		)

		args = append(args,
			env.ID,
			env.OrganizationID,
			env.ClientID,
			env.ContactID,
			env.EventType,
			env.SchemaVersion,
			env.CreatedAt.UTC(),
			[]byte(payload),
			headersJSON,
			msg.Topic,
			msg.Partition,
			msg.Offset,
		)
	}
	b.WriteString(`
ON CONFLICT (id, created_at) DO NOTHING`)

	tx, err := pool.Begin(ctx)
	if err != nil {
		return fmt.Errorf("begin tx: %w", err)
	}
	defer tx.Rollback(ctx)

	if _, err := tx.Exec(ctx, b.String(), args...); err != nil {
		return fmt.Errorf("exec insert: %w", err)
	}
	if err := tx.Commit(ctx); err != nil {
		return fmt.Errorf("commit tx: %w", err)
	}
	return nil
}

func envOr(key, fallback string) string {
	if v := os.Getenv(key); v != "" {
		return v
	}
	return fallback
}

func envIntOr(key string, fallback int) int {
	v := os.Getenv(key)
	if v == "" {
		return fallback
	}
	n, err := strconv.Atoi(v)
	if err != nil {
		log.Fatalf("%s: invalid int %q: %v", key, v, err)
	}
	return n
}

func envDurationOr(key string, fallback time.Duration) time.Duration {
	v := os.Getenv(key)
	if v == "" {
		return fallback
	}
	d, err := time.ParseDuration(v)
	if err != nil {
		log.Fatalf("%s: invalid duration %q: %v", key, v, err)
	}
	return d
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
