-- Partitioned DLQ event tables. Partition key: created_at (time only).
-- Tenant segregation: organization_id / client_id / contact_id indexes.

CREATE TABLE IF NOT EXISTS events_retry_dlq (
    id              UUID           NOT NULL,
    organization_id UUID           NOT NULL,
    client_id       UUID           NOT NULL,
    contact_id      UUID           NOT NULL,
    event_type      TEXT           NOT NULL,
    schema_version  INT            NOT NULL DEFAULT 1,
    created_at      TIMESTAMPTZ    NOT NULL,
    payload         JSONB          NOT NULL DEFAULT '{}'::jsonb,
    headers         JSONB          NOT NULL DEFAULT '{}'::jsonb,
    kafka_topic     TEXT,
    kafka_partition INT,
    kafka_offset    BIGINT,
    ingested_at     TIMESTAMPTZ    NOT NULL DEFAULT now(),
    PRIMARY KEY (id, created_at)
) PARTITION BY RANGE (created_at);

CREATE INDEX IF NOT EXISTS events_retry_dlq_id_idx
    ON events_retry_dlq (id);
CREATE INDEX IF NOT EXISTS events_retry_dlq_org_client_created_idx
    ON events_retry_dlq (organization_id, client_id, created_at);
CREATE INDEX IF NOT EXISTS events_retry_dlq_contact_created_idx
    ON events_retry_dlq (contact_id, created_at);
CREATE INDEX IF NOT EXISTS events_retry_dlq_type_created_idx
    ON events_retry_dlq (event_type, created_at);

CREATE TABLE IF NOT EXISTS events_true_dlq (
    id              UUID           NOT NULL,
    organization_id UUID           NOT NULL,
    client_id       UUID           NOT NULL,
    contact_id      UUID           NOT NULL,
    event_type      TEXT           NOT NULL,
    schema_version  INT            NOT NULL DEFAULT 1,
    created_at      TIMESTAMPTZ    NOT NULL,
    payload         JSONB          NOT NULL DEFAULT '{}'::jsonb,
    headers         JSONB          NOT NULL DEFAULT '{}'::jsonb,
    kafka_topic     TEXT,
    kafka_partition INT,
    kafka_offset    BIGINT,
    ingested_at     TIMESTAMPTZ    NOT NULL DEFAULT now(),
    PRIMARY KEY (id, created_at)
) PARTITION BY RANGE (created_at);

CREATE INDEX IF NOT EXISTS events_true_dlq_id_idx
    ON events_true_dlq (id);
CREATE INDEX IF NOT EXISTS events_true_dlq_org_client_created_idx
    ON events_true_dlq (organization_id, client_id, created_at);
CREATE INDEX IF NOT EXISTS events_true_dlq_contact_created_idx
    ON events_true_dlq (contact_id, created_at);
CREATE INDEX IF NOT EXISTS events_true_dlq_type_created_idx
    ON events_true_dlq (event_type, created_at);

ALTER TABLE events_retry_dlq OWNER TO app;
ALTER TABLE events_true_dlq OWNER TO app;
GRANT ALL ON TABLE events_retry_dlq TO app;
GRANT ALL ON TABLE events_true_dlq TO app;
GRANT ALL ON ALL SEQUENCES IN SCHEMA public TO app;
