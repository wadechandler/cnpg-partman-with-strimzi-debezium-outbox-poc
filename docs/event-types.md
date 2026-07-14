# Fake event types

Wire JSON follows [Google JSON Style Guide](https://google.github.io/styleguide/jsoncstyleguide.xml) (camelCase). Extend use cases via `eventType` + `payload`; keep the envelope stable.

## Two Kafka shapes (same camelCase rule)

| Topic | Produced by | Shape |
|-------|-------------|--------|
| `*.events.retry-dlq` / `*.events.true-dlq` | Go `event-generator` | Domain **envelope** (`organizationId`, `eventType`, `createdAt`, nested `payload` object) |
| `*.events.retry` | Debezium from `replay_outbox` | **Outbox row** projected to camelCase via Connect SMT (`organizationId`, `eventType`, `eventCreatedAt`, `sourceDlq`, `retryReason`, `createdAt`, …). Postgres stays snake_case. |
| `__debezium-heartbeat.*` | Debezium | Slot-progress heartbeats only (`ts_ms`, …) — **not** retry traffic |

Retry-topic messages with `organizationId` / `retryReason` are outbox replays (camelCase via Connect SMT). Heartbeats stay on `__debezium-heartbeat.*` and are not routed onto retry.

| eventType | Sample payload keys | Typical DLQ |
|-----------|---------------------|-------------|
| `blood_pressure.reading` | `systolic`, `diastolic`, `unit`, `measuredAt`, `deviceId` | retry or true |
| `prescription.updated` | `rxId`, `ndc`, `status`, `prescribedAt` | retry |
| `appointment.reminder` | `appointmentId`, `scheduledAt`, `channel` | retry |
| `lab.result.available` | `panel`, `codes`, `resultAt` | true |
| `wearable.sync` | `metric`, `value`, `unit`, `syncedAt` | retry |

## Envelope example

```json
{
  "id": "550e8400-e29b-41d4-a716-446655440000",
  "organizationId": "00000000-0000-4000-8000-000000000001",
  "clientId": "00000000-0000-4000-8000-000000000010",
  "contactId": "00000000-0000-4000-8000-000000000100",
  "eventType": "blood_pressure.reading",
  "schemaVersion": 1,
  "createdAt": "2026-07-12T14:05:00Z",
  "payload": {
    "systolic": 128,
    "diastolic": 82,
    "unit": "mmHg",
    "measuredAt": "2026-07-12T14:04:30Z",
    "deviceId": "bp-demo-1"
  }
}
```

Stable demo UUIDs live in `internal/demoids`.
