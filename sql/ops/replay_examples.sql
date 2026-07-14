-- Ops examples: filter DLQ rows and insert into replay_outbox for Debezium → retry topic.
-- Run via: make psql
--
-- Set retry_reason as desired. Default matches the POC narrative.

-- Replay by organization + client (retry DLQ):
-- INSERT INTO replay_outbox (
--     id, organization_id, client_id, contact_id, event_type, schema_version,
--     event_created_at, payload, source_dlq, retry_reason
-- )
-- SELECT
--     id, organization_id, client_id, contact_id, event_type, schema_version,
--     created_at, payload, 'retry',
--     'Retrying from operations for some reason'
-- FROM events_retry_dlq
-- WHERE organization_id = '00000000-0000-4000-8000-000000000001'
--   AND client_id = '00000000-0000-4000-8000-000000000010'
--   AND created_at > now() - interval '1 hour';

-- Replay a single event by id (add created_at hint if needed for partition pruning):
-- INSERT INTO replay_outbox (
--     id, organization_id, client_id, contact_id, event_type, schema_version,
--     event_created_at, payload, source_dlq, retry_reason
-- )
-- SELECT
--     id, organization_id, client_id, contact_id, event_type, schema_version,
--     created_at, payload, 'true',
--     'Retrying from operations for some reason'
-- FROM events_true_dlq
-- WHERE id = '00000000-0000-4000-8000-000000000099';

SELECT 'See commented examples in sql/ops/replay_examples.sql'::text AS hint;
