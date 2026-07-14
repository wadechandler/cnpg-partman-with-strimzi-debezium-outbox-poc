# cnpg-outbox-poc-infra

Helm chart for POC **platform CRs** only: CNPG Cluster (+ NodePort), KafkaNodePool + Kafka, KafkaTopics, KafkaConnect (Debezium image), and KafkaConnector.

**Operators are not installed here.** `infra/scripts/setup.sh` Helm-installs CloudNativePG and Strimzi operators, creates namespaces, then installs this chart (SQL ConfigMap + platform CRs), syncs the DB secret, and patches the connector password.

Bootstrap SQL lives in [`files/sql/`](files/sql/) (`002`–`005`); the chart renders ConfigMap `postgres.sqlConfigMap`. Ops examples stay at repo-root [`sql/ops/`](../../sql/ops/) (not in the ConfigMap).

## Versions

| Component | Default |
|-----------|---------|
| Strimzi operator (setup.sh) | `0.51.0` |
| Kafka / Connect `spec.version` | `4.2.0` |
| Debezium base image | `quay.io/strimzi/kafka:0.51.0-kafka-4.2.0` |

Keep `kafka.version`, `debezium.connectVersion`, and the Debezium Dockerfile `STRIMZI_VERSION` / `KAFKA_VERSION` in sync.

## Install

```bash
# After operators exist (see setup.sh):
helm upgrade --install cnpg-outbox-poc-infra ./charts/cnpg-outbox-poc-infra \
  --namespace cnpg-outbox-poc
```

Resources set `metadata.namespace` from values (`namespaces.app` / `namespaces.kafka`), so one release can target both namespaces. Helm’s release namespace is mostly bookkeeping.

## Inspect rendered CRs

This chart is the **only** source of truth for platform CRs. For a flat YAML view (teaching / review), render on demand — do not maintain a parallel `infra/manifests/` tree:

```bash
make render-infra
# or: helm template cnpg-outbox-poc-infra ./charts/cnpg-outbox-poc-infra --namespace cnpg-outbox-poc
```

## Injecting a separate Postgres vs Kafka layout

Teammates can point Debezium at a remote/shared DB while Kafka stays local (or the reverse):

| Goal | Values |
|------|--------|
| Postgres in another namespace/cluster | `postgres.serviceHost` and/or `debezium.database.hostname` |
| Debezium DB credentials user/db | `debezium.database.user`, `debezium.database.dbname`, `debezium.database.port` |
| Kafka bootstrap for Connect | `kafka.bootstrapServers` (default builds from `kafka.clusterName` + `namespaces.kafka`) |
| Topic naming | `global.topicPrefix` (topics + Connect storage topics + retry route) |
| Heartbeat topic prefix | `debezium.heartbeatTopicPrefix` (default `__debezium-heartbeat`; not retry) |
| CNPG image / storage / NodePort | `postgres.*` |
| Kafka version / NodePorts | `kafka.*` |

### Which value is the Debezium DB host?

1. If `debezium.database.hostname` is non-empty → use it.
2. Else → use `postgres.serviceHost` (default `cnpg-outbox-db-rw.cnpg-outbox-poc.svc`).

Example override:

```bash
helm upgrade --install cnpg-outbox-poc-infra ./charts/cnpg-outbox-poc-infra \
  --set postgres.serviceHost=my-pg-rw.db-prod.svc \
  --set debezium.database.hostname=my-pg-rw.db-prod.svc
```

### Password

`database.password` is **not** set in values. `setup.sh` copies the CNPG superuser secret into the Kafka namespace and patches the KafkaConnector.

## Related app chart

`charts/cnpg-outbox-poc` (dlq-ingester) should use matching `kafka.bootstrapServers` and `database.host` / `database.secretName` — see comments in that chart’s `values.yaml`.
