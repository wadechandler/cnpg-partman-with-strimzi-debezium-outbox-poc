-- Replay outbox: partition on insert time (created_at), not original event time.
-- Debezium CDC publishes rows to cnpg-outbox-poc.events.retry.

CREATE TABLE IF NOT EXISTS replay_outbox (
    id                UUID           NOT NULL,
    organization_id   UUID           NOT NULL,
    client_id         UUID           NOT NULL,
    contact_id        UUID           NOT NULL,
    event_type        TEXT           NOT NULL,
    schema_version    INT            NOT NULL DEFAULT 1,
    event_created_at  TIMESTAMPTZ    NOT NULL,
    payload           JSONB          NOT NULL DEFAULT '{}'::jsonb,
    source_dlq        TEXT           NOT NULL CHECK (source_dlq IN ('retry', 'true')),
    retry_reason      TEXT           NOT NULL DEFAULT 'Retrying from operations for some reason',
    created_at        TIMESTAMPTZ    NOT NULL DEFAULT now(),
    PRIMARY KEY (id, created_at)
) PARTITION BY RANGE (created_at);

CREATE INDEX IF NOT EXISTS replay_outbox_id_idx
    ON replay_outbox (id);
CREATE INDEX IF NOT EXISTS replay_outbox_org_client_created_idx
    ON replay_outbox (organization_id, client_id, created_at);
CREATE INDEX IF NOT EXISTS replay_outbox_created_idx
    ON replay_outbox (created_at);

-- Debezium needs REPLICA IDENTITY FULL (or UNIQUE) for deletes/updates; inserts-only is fine with DEFAULT.
ALTER TABLE replay_outbox REPLICA IDENTITY FULL;

ALTER TABLE replay_outbox OWNER TO app;
GRANT ALL ON TABLE replay_outbox TO app;
