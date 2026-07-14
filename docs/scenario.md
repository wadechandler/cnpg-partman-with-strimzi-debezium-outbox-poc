# Scenario

Health engagement platform (narrative): external systems emit extensible events that drive batched engagement workflows. Transient failures go to a **retry DLQ**; validation failures go to a **true DLQ**.

Operators query partitioned DLQ tables and insert selected rows into **`replay_outbox`**. Debezium publishes those inserts to **`cnpg-outbox-poc.events.retry`** for reprocessing.

## Implemented in this POC

- KIND + CNPG (partman) + Strimzi + Debezium
- Go generator + DLQ ingester
- SQL examples for replay
- Short Kafka retention and aggressive outbox partition drop for demos

## Not implemented

- Workflow / batch step engine
- UI over DLQ ops
- Real device or EHR integrations
- Production HA sizing
