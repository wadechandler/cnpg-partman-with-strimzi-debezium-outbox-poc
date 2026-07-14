# Outbox / Debezium at higher throughput

This POC runs a single-node Kafka, one Connect worker, and `tasksMax: 1`. That is fine for demos. At roughly **1–2k outbox inserts/sec** (or sustained millions/day), treat the following as the main knobs and failure modes.

## What “scale” means here

The hot path is: **INSERT into `replay_outbox` → WAL → Debezium → Kafka retry topic**. Bottlenecks are usually (1) Postgres WAL/slot lag, (2) Connect throughput / transforms, (3) Kafka produce capacity — not the SQL `INSERT…SELECT` itself if batched.

## Postgres / CNPG

| Concern | Guidance |
|---------|----------|
| WAL / slot lag | Watch replication slot lag (`pg_replication_slots`). If Debezium falls behind, WAL retention grows and disks fill. |
| Partitioned outbox | Keep `table.include.list` covering parent **and** children (`public.replay_outbox.*`). New partitions must land in the publication (partman + Debezium filtered mode). |
| Outbox retention | Short retention (as in this POC) is good at scale; do not let outbox history become your audit store. |
| Batching ops replay | Prefer set-based `INSERT…SELECT` with tight filters over row-by-row ops UI loops. |
| CNPG sizing | More IOPS/CPU on the primary; consider CNPG HA + resources before Connect replicas. |

## Debezium / Kafka Connect (Strimzi)

| Concern | Guidance |
|---------|----------|
| Workers | Scale `KafkaConnect.spec.replicas` for CPU; connector tasks for Postgres CDC are still often **1 task** (single slot / single stream). Horizontal Connect helps other connectors more than one pg slot. |
| `tasksMax` | Postgres connector is effectively single-task for one slot. Do not expect `tasksMax: N` to shard one publication the way sink connectors do. |
| Snapshot vs streaming | Avoid large snapshots in prod; use `snapshot.mode` carefully. Streaming should stay near tip of WAL. |
| SMTs | Each transform costs CPU. Prefer lean unwrap + routing; avoid heavy per-message work in Connect. |
| Heartbeats | Keep heartbeats (`heartbeat.interval.ms`) so slots can advance when the outbox is quiet on a busy shared DB. They must land on `__debezium-heartbeat.*`, **never** on the retry topic (SMT predicates). |
| Offset / config topics | Internal Connect topics need enough partitions/replication for your HA story (POC uses RF=1). |

## Kafka (Strimzi)

| Concern | Guidance |
|---------|----------|
| Partitions on retry topic | Size for **downstream consumers**, not Debezium (source is one stream). Start from consumer parallelism needs. |
| Producer batching | Connect producer configs (`linger.ms`, batch size, compression) matter at 1–2k/s. |
| Retention | Short TTL on retry (as here) if consumers are real-time; do not rely on Kafka as long-term DLQ archive. |
| Brokers | Move off single-node KRaft for anything production-like; RF≥3, disk/network headroom. |

## Application / ops patterns

- **Idempotent retry consumers** — replays will duplicate; keys/`id` matter.
- **Backpressure** — if retry consumers stall, Kafka retains; pair with alerts on lag.
- **Separate “true DLQ” path** — bad data should not hammer the same retry pipeline forever.
- **Measure** — Connect task metrics, slot lag, topic produce rate, consumer lag.

## DLQ ingest batching (`dlq-ingester`)

The ingester does **not** commit Kafka offsets per message. It accumulates a small batch, writes Postgres in one transaction, then commits Kafka.

| Knob | Default (POC) | Env override | Why |
|------|---------------|--------------|-----|
| Batch size | **50** | `INGEST_BATCH_SIZE` | Fewer DB round-trips / commits than one-row-at-a-time. |
| Max wait (linger) | **200ms** | `INGEST_BATCH_MAX_WAIT` | Flush a partial batch so a single (or few) messages are not stuck waiting for a full batch. |

Both matter: size alone under-fills on quiet topics; wait alone can still flush one row at a time under load. **Commit-after-DB** keeps the consumer fail-fast — if the multi-row `INSERT … ON CONFLICT DO NOTHING` fails, offsets for that batch are not committed.

These defaults are a **teaching** starting point for the POC, not a production sizing prescription. Tune from measured lag, insert latency, and duplicate-safe idempotency (`ON CONFLICT (id, created_at)`).

## Heartbeats vs retry topic

Debezium heartbeats (when enabled) go to `__debezium-heartbeat.<topic.prefix>`. Connector SMTs (`unwrap` / `rename` / `route`) apply only when the source topic matches `*.public.replay_outbox*` so heartbeats are not rewritten onto `*.events.retry`.

## What this POC deliberately does *not* do

Single broker, RF=1, one Connect pod, aggressive local retention, no HA Postgres. Use it to learn the pattern; re-size for load tests before quoting production numbers.
