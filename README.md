# CNPG + pg_partman + Strimzi + Debezium Outbox POC

MIT-licensed local proof of concept: **CloudNativePG** (custom image with **pg_partman**), **Strimzi** Kafka, **Debezium** CDC from a replay outbox, and small **Go** utilities — all on **KIND**.

## Scenario (narrative)

Imagine a health engagement platform. Extensible **external events** (blood pressure, prescriptions, appointments, labs, wearables) drive batched workflows. Failures land on a **retry DLQ** (transient) or **true DLQ** (bad data), with Kafka headers `dlq-reason` / `retry-reason`.

This repo does **not** implement the full workflow engine. It implements the infrastructure slice: DLQ → partitioned Postgres → ops SQL into `replay_outbox` → Debezium → retry topic.

## What is implemented

1. Time-based partitioning (5-minute buckets for the POC) on DLQ tables and `replay_outbox`
2. Visible outbox partition cleanup (~20 minutes retention)
3. Debezium CDC: `replay_outbox` → `cnpg-outbox-poc.events.retry` (short Kafka retention)
4. Go `dlq-ingester`: DLQ topics → `events_retry_dlq` / `events_true_dlq` (time-bounded batches; see [docs/outbox-at-scale.md](docs/outbox-at-scale.md))
5. Go `event-generator`: sample events onto DLQs
6. Custom CNPG image + extensions (`pg_partman`, `pg_stat_statements`)
7. KIND + Helm bootstrap (operators + parameterized infra chart)
8. Multi-arch-ready Go container builds

## Versions / Helm

| Piece | Version / location |
|-------|--------------------|
| Strimzi operator | Helm chart **0.51.0** (`setup.sh`) |
| Kafka | **4.2.0** (KRaft) |
| Debezium Connect base | `quay.io/strimzi/kafka:0.51.0-kafka-4.2.0` |
| Platform CRs | [`charts/cnpg-outbox-poc-infra`](charts/cnpg-outbox-poc-infra) |
| App (dlq-ingester) | [`charts/cnpg-outbox-poc`](charts/cnpg-outbox-poc) |
| Kafbat UI | upstream `kafbat-ui/kafka-ui` + [`charts/kafbat-ui/values.yaml`](charts/kafbat-ui/values.yaml) |

Teammates inject names/hosts via infra chart values — e.g. `postgres.serviceHost` / `debezium.database.hostname` for a separate DB cluster, `kafka.bootstrapServers` for Kafka, `global.topicPrefix` for topics. Operators stay installed by `setup.sh`. Platform CRs and CNPG bootstrap SQL (`files/sql/00*.sql` → ConfigMap) live only in the infra chart (no parallel flat YAML). To inspect what Helm will apply: `make render-infra`.

## Quick start

```bash
make check
make up          # build images, create KIND cluster, install stack
make generate    # publish sample DLQ events
make psql        # explore tables / run sql/ops/replay_examples.sql
make kafbat      # browse topics in Kafbat UI (http://127.0.0.1:8080)
make verify
make down        # delete KIND cluster
```

### Browse topics

After `make up`, open Kafbat UI with a local port-forward (not started by setup — that would hang `make up`):

```bash
make kafbat
# → http://127.0.0.1:8080
```

Skip install with `SKIP_KAFBAT=1` when running setup. Values: [`charts/kafbat-ui/values.yaml`](charts/kafbat-ui/values.yaml).

Generator options:

```bash
make generate ARGS='--types blood_pressure.reading,prescription.updated --dlq both --count 5 --spread 15m'
```

## Topics (`cnpg-outbox-poc.*`)

| Topic | Role |
|-------|------|
| `events.original` | Named for narrative; unused |
| `events.retry-dlq` | Transient failures |
| `events.true-dlq` | Validation / bad data |
| `events.retry` | Debezium output from outbox |

## Schema sketch

Wire JSON (camelCase, [Google JSON style](https://google.github.io/styleguide/jsoncstyleguide.xml)): `id`, `organizationId`, `clientId`, `contactId`, `eventType`, `schemaVersion`, `createdAt`, `payload`.

Postgres uses snake_case. **Partition by `created_at` only**; tenant columns are indexed (not partition keys). See [docs/partitioning.md](docs/partitioning.md) and [docs/event-types.md](docs/event-types.md).

For production-shaped throughput (≈1–2k outbox writes/sec and beyond), see [docs/outbox-at-scale.md](docs/outbox-at-scale.md).

## Ops replay

`make psql`, then use the commented examples in [`sql/ops/replay_examples.sql`](sql/ops/replay_examples.sql) to `INSERT INTO replay_outbox … SELECT … FROM events_*_dlq`.

## Requirements

- Docker, KIND, kubectl, Helm, Go 1.22+
- Do **not** use Docker Desktop’s “Enable Kubernetes” for this POC — scripts use standalone `kind`

## License

MIT — see [LICENSE](LICENSE).

## Agent notes

See [AGENTS.md](AGENTS.md). No git commit/push until you ask; mutation boundary is this workspace + this KIND cluster only.
