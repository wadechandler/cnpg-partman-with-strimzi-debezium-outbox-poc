# Agents: CNPG + pg_partman + Strimzi + Debezium Outbox POC

Local KIND POC: partitioned DLQ tables, SQL→`replay_outbox`, Debezium→retry topic.

## Hard rules

- **Mutation boundary:** edit files only in this workspace; drive only this POC’s KIND cluster via `infra/scripts`. Do not change host git config, Docker Desktop settings, other repos/clusters, or unrelated system state unless the user asks.
- **Git:** `git init` OK. **No commit / remote / push** until the user tests and explicitly asks.
- **Email:** never put email in project files.
- **Deps:** prefer stdlib; run `make vulncheck` (`govulncheck`) before adding/upgrading modules.
- **Style:** [Google style guides](https://google.github.io/styleguide/) — Go + JSON (camelCase on the wire). Keep this file and `.cursor/rules` concise.
- **Quality:** idiomatic Go (`cmd/` + `internal/`), clear packages — not throwaway spaghetti.

## Stack

| Piece | Choice |
|-------|--------|
| Cluster | KIND (`cnpg-outbox-poc`) |
| Postgres | CNPG + custom image (pg_partman, pg_stat_statements) |
| Kafka | Strimzi KRaft (`poc-kafka`) |
| CDC | Debezium Connect (Strimzi 0.51 / Kafka 4.2): `replay_outbox` → `cnpg-outbox-poc.events.retry` |
| Kafka UI | Kafbat (`make kafbat` → http://127.0.0.1:8080); values in `charts/kafbat-ui/` |
| DLQ→DB | Go `dlq-ingester` |
| Generator | Go `event-generator` |
| Topics prefix | `cnpg-outbox-poc.*` |
| Partitions | Time only; org/client/contact = indexes |

## Layout

See README. Key paths: `infra/` (KIND, images, scripts — no flat CR manifests), `charts/cnpg-outbox-poc-infra` (platform CRs + bootstrap SQL in `files/sql/`), `charts/kafbat-ui/` (Kafbat values; installed by setup.sh), `sql/ops/` (manual replay examples), `cmd/`, `internal/`, `charts/cnpg-outbox-poc` (apps), `docs/`. Use `make render-infra` to inspect rendered CRs.
## Narrative vs implemented

**Story:** health engagement external events → batched workflows → retry/true DLQs.  
**Built:** DLQ ingest, partitioned tables, SQL replay outbox, Debezium retry publish, generator, KIND stack. Not built: full workflow engine, UI, real device integrations.
