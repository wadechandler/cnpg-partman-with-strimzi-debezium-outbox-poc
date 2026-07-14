-- pg_partman: 5-minute partitions for POC visibility.
-- Outbox: aggressive retention (~20 minutes). DLQ tables: longer retention for SQL demos.

SELECT partman.create_parent(
    p_parent_table := 'public.events_retry_dlq',
    p_control := 'created_at',
    p_interval := '5 minutes',
    p_premake := 4
);

SELECT partman.create_parent(
    p_parent_table := 'public.events_true_dlq',
    p_control := 'created_at',
    p_interval := '5 minutes',
    p_premake := 4
);

SELECT partman.create_parent(
    p_parent_table := 'public.replay_outbox',
    p_control := 'created_at',
    p_interval := '5 minutes',
    p_premake := 4
);

-- Retention: keep DLQ partitions ~2 hours; drop outbox partitions after ~20 minutes.
UPDATE partman.part_config
SET infinite_time_partitions = true,
    retention = '2 hours',
    retention_keep_table = false,
    retention_keep_index = false
WHERE parent_table IN ('public.events_retry_dlq', 'public.events_true_dlq');

UPDATE partman.part_config
SET infinite_time_partitions = true,
    retention = '20 minutes',
    retention_keep_table = false,
    retention_keep_index = false
WHERE parent_table = 'public.replay_outbox';
