# Partitioning and retention

## POC choice

| Table | Partition key | Interval | Retention (POC) |
|-------|---------------|----------|-----------------|
| `events_retry_dlq` | event `created_at` | 5 minutes | ~2 hours |
| `events_true_dlq` | event `created_at` | 5 minutes | ~2 hours |
| `replay_outbox` | **outbox insert** `created_at` | 5 minutes | ~20 minutes (visible cleanup) |

Tenant fields (`organization_id`, `client_id`, `contact_id`) are **indexes**, not partition keys — avoids partition explosion with UUID tenants.

## Production-shaped DLQ retention (documented only)

For real systems, prefer **daily** partitions on DLQ tables and retain N days:

```sql
-- Illustrative — not applied by default in this POC
SELECT partman.create_parent(
    p_parent_table := 'public.events_retry_dlq',
    p_control := 'created_at',
    p_interval := '1 day',
    p_premake := 7
);
UPDATE partman.part_config
SET retention = '30 days',
    retention_keep_table = false
WHERE parent_table = 'public.events_retry_dlq';
```

Outbox retention can stay short (minutes/hours) because rows exist to drive CDC, not long-term audit (audit belongs in DLQ or elsewhere).

## Debezium note

Logical decoding emits changes against **partition child** relations. The connector uses `table.include.list: public.replay_outbox.*` so parent and children are captured, then `RegexRouter` sends them to `cnpg-outbox-poc.events.retry`.
