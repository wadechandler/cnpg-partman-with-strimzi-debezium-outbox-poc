-- Ensure application role owns partitioned tables created during bootstrap.
ALTER TABLE IF EXISTS events_retry_dlq OWNER TO app;
ALTER TABLE IF EXISTS events_true_dlq OWNER TO app;
ALTER TABLE IF EXISTS replay_outbox OWNER TO app;
GRANT ALL ON ALL TABLES IN SCHEMA public TO app;
GRANT ALL ON ALL TABLES IN SCHEMA partman TO app;
GRANT USAGE, CREATE ON SCHEMA public TO app;

DO $$
DECLARE r record;
BEGIN
  FOR r IN
    SELECT c.oid::regclass AS child
    FROM pg_inherits i
    JOIN pg_class c ON c.oid = i.inhrelid
    JOIN pg_class p ON p.oid = i.inhparent
    WHERE p.relname IN ('events_retry_dlq', 'events_true_dlq', 'replay_outbox')
  LOOP
    EXECUTE format('ALTER TABLE %s OWNER TO app', r.child);
    EXECUTE format('GRANT ALL ON TABLE %s TO app', r.child);
  END LOOP;
END$$;
