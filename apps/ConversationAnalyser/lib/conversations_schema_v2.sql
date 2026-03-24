-- Conversations Analysis Database v2
-- PostgreSQL standalone schema for temporary storage and repeat incident analysis
-- Designed for Genesys Cloud analytics conversation details payloads.

BEGIN;

CREATE EXTENSION IF NOT EXISTS pgcrypto;

CREATE SCHEMA IF NOT EXISTS convo;

-- ---------------------------------------------------------------------------
-- Ingest lineage
-- ---------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS convo.ingest_runs (
    ingest_run_id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    source_system           TEXT NOT NULL DEFAULT 'genesys_cloud',
    source_endpoint         TEXT NOT NULL DEFAULT '/api/v2/analytics/conversations/details/query',
    source_region           TEXT,
    interval_start_utc      TIMESTAMPTZ,
    interval_end_utc        TIMESTAMPTZ,
    interval_text           TEXT,
    filter_json             JSONB,
    requested_by            TEXT,
    request_id              TEXT,
    incident_key            TEXT,
    case_key                TEXT,
    notes                   TEXT,
    run_started_utc         TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    run_completed_utc       TIMESTAMPTZ,
    status                  TEXT NOT NULL DEFAULT 'running',
    conversation_count      INTEGER NOT NULL DEFAULT 0,
    inserted_count          INTEGER NOT NULL DEFAULT 0,
    updated_count           INTEGER NOT NULL DEFAULT 0,
    skipped_count           INTEGER NOT NULL DEFAULT 0,
    error_count             INTEGER NOT NULL DEFAULT 0,
    created_utc             TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_utc             TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT ck_ingest_runs_status CHECK (status IN ('running','completed','failed','partial','cancelled'))
);

CREATE TABLE IF NOT EXISTS convo.ingest_errors (
    ingest_error_id         BIGSERIAL PRIMARY KEY,
    ingest_run_id           UUID NOT NULL REFERENCES convo.ingest_runs(ingest_run_id) ON DELETE CASCADE,
    conversation_id         UUID,
    entity_type             TEXT,
    entity_key              TEXT,
    error_stage             TEXT,
    error_message           TEXT NOT NULL,
    error_detail            JSONB,
    created_utc             TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- ---------------------------------------------------------------------------
-- Raw preservation layer
-- ---------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS convo.raw_conversations (
    raw_conversation_id     BIGSERIAL PRIMARY KEY,
    ingest_run_id           UUID REFERENCES convo.ingest_runs(ingest_run_id) ON DELETE SET NULL,
    conversation_id         UUID NOT NULL,
    payload_sha256          TEXT,
    payload_json            JSONB NOT NULL,
    source_received_utc     TIMESTAMPTZ,
    inserted_utc            TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    last_seen_utc           TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    is_current              BOOLEAN NOT NULL DEFAULT TRUE,
    UNIQUE (conversation_id, payload_sha256)
);

CREATE INDEX IF NOT EXISTS ix_raw_conversations_conversation_id
    ON convo.raw_conversations (conversation_id);

CREATE INDEX IF NOT EXISTS ix_raw_conversations_current
    ON convo.raw_conversations (conversation_id, is_current, inserted_utc DESC);

CREATE INDEX IF NOT EXISTS ix_raw_conversations_payload_json_gin
    ON convo.raw_conversations USING GIN (payload_json);

-- ---------------------------------------------------------------------------
-- Reference / dimension layer
-- ---------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS convo.dim_division (
    division_id             UUID PRIMARY KEY,
    division_name           TEXT,
    source_json             JSONB,
    first_seen_utc          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    last_seen_utc           TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS convo.dim_queue (
    queue_id                UUID PRIMARY KEY,
    queue_name              TEXT,
    source_json             JSONB,
    first_seen_utc          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    last_seen_utc           TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS convo.dim_user (
    user_id                 UUID PRIMARY KEY,
    user_name               TEXT,
    email                   TEXT,
    source_json             JSONB,
    first_seen_utc          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    last_seen_utc           TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS convo.dim_metric_name (
    metric_name             TEXT PRIMARY KEY,
    metric_description      TEXT,
    metric_unit             TEXT,
    first_seen_utc          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    last_seen_utc           TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS convo.dim_segment_type (
    segment_type            TEXT PRIMARY KEY,
    description             TEXT,
    first_seen_utc          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    last_seen_utc           TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS convo.dim_media_type (
    media_type              TEXT PRIMARY KEY,
    description             TEXT,
    first_seen_utc          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    last_seen_utc           TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- ---------------------------------------------------------------------------
-- Core normalized layer
-- ---------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS convo.conversations (
    conversation_id                         UUID PRIMARY KEY,
    latest_ingest_run_id                    UUID REFERENCES convo.ingest_runs(ingest_run_id) ON DELETE SET NULL,
    raw_current_id                          BIGINT REFERENCES convo.raw_conversations(raw_conversation_id) ON DELETE SET NULL,
    conversation_start_utc                  TIMESTAMPTZ NOT NULL,
    conversation_end_utc                    TIMESTAMPTZ,
    originating_direction                   TEXT NOT NULL,
    media_stats_min_conversation_mos        NUMERIC(10,6),
    media_stats_min_conversation_rfactor    NUMERIC(10,6),
    participant_count                       INTEGER NOT NULL DEFAULT 0,
    session_count                           INTEGER NOT NULL DEFAULT 0,
    segment_count                           INTEGER NOT NULL DEFAULT 0,
    metric_count                            INTEGER NOT NULL DEFAULT 0,
    first_ingested_utc                      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    last_ingested_utc                       TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    last_analyzed_utc                       TIMESTAMPTZ,
    retention_expires_utc                   TIMESTAMPTZ,
    incident_key                            TEXT,
    case_key                                TEXT,
    tags                                    TEXT[],
    source_payload_version                  TEXT,
    source_json                             JSONB
);

CREATE INDEX IF NOT EXISTS ix_conversations_start
    ON convo.conversations (conversation_start_utc DESC);

CREATE INDEX IF NOT EXISTS ix_conversations_end
    ON convo.conversations (conversation_end_utc DESC);

CREATE INDEX IF NOT EXISTS ix_conversations_incident
    ON convo.conversations (incident_key, case_key);

CREATE INDEX IF NOT EXISTS ix_conversations_tags_gin
    ON convo.conversations USING GIN (tags);

CREATE TABLE IF NOT EXISTS convo.conversation_divisions (
    conversation_id         UUID NOT NULL REFERENCES convo.conversations(conversation_id) ON DELETE CASCADE,
    division_id             UUID NOT NULL REFERENCES convo.dim_division(division_id) ON DELETE RESTRICT,
    PRIMARY KEY (conversation_id, division_id)
);

CREATE TABLE IF NOT EXISTS convo.participants (
    participant_pk          BIGSERIAL PRIMARY KEY,
    participant_id          UUID NOT NULL,
    conversation_id         UUID NOT NULL REFERENCES convo.conversations(conversation_id) ON DELETE CASCADE,
    participant_name        TEXT,
    purpose                 TEXT NOT NULL,
    user_id                 UUID REFERENCES convo.dim_user(user_id) ON DELETE SET NULL,
    external_contact_id     TEXT,
    address_normalized      TEXT,
    ani                     TEXT,
    dnis                    TEXT,
    team_id                 TEXT,
    queue_id                UUID REFERENCES convo.dim_queue(queue_id) ON DELETE SET NULL,
    participant_index       INTEGER,
    source_json             JSONB,
    created_utc             TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_utc             TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE (conversation_id, participant_id)
);

CREATE INDEX IF NOT EXISTS ix_participants_conversation
    ON convo.participants (conversation_id, purpose);

CREATE INDEX IF NOT EXISTS ix_participants_user
    ON convo.participants (user_id, conversation_id);

CREATE TABLE IF NOT EXISTS convo.sessions (
    session_pk              BIGSERIAL PRIMARY KEY,
    session_key             TEXT NOT NULL UNIQUE,
    session_id              UUID NOT NULL,
    conversation_id         UUID NOT NULL REFERENCES convo.conversations(conversation_id) ON DELETE CASCADE,
    participant_pk          BIGINT NOT NULL REFERENCES convo.participants(participant_pk) ON DELETE CASCADE,
    media_type              TEXT NOT NULL REFERENCES convo.dim_media_type(media_type) ON DELETE RESTRICT,
    direction               TEXT NOT NULL,
    peer_id                 UUID,
    provider                TEXT,
    used_routing            TEXT,
    selected_agent_id       UUID REFERENCES convo.dim_user(user_id) ON DELETE SET NULL,
    remote                  TEXT,
    address_from            TEXT,
    address_to              TEXT,
    edge_id                 TEXT,
    flow_id                 TEXT,
    flow_name               TEXT,
    queue_id                UUID REFERENCES convo.dim_queue(queue_id) ON DELETE SET NULL,
    session_start_utc       TIMESTAMPTZ,
    session_end_utc         TIMESTAMPTZ,
    session_duration_ms     BIGINT,
    session_index           INTEGER,
    source_json             JSONB,
    created_utc             TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_utc             TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE (conversation_id, participant_pk, session_id)
);

CREATE INDEX IF NOT EXISTS ix_sessions_conversation
    ON convo.sessions (conversation_id);

CREATE INDEX IF NOT EXISTS ix_sessions_participant
    ON convo.sessions (participant_pk);

CREATE INDEX IF NOT EXISTS ix_sessions_selected_agent
    ON convo.sessions (selected_agent_id, conversation_id);

CREATE TABLE IF NOT EXISTS convo.session_requested_routings (
    session_pk              BIGINT NOT NULL REFERENCES convo.sessions(session_pk) ON DELETE CASCADE,
    routing_name            TEXT NOT NULL,
    routing_order           INTEGER NOT NULL,
    PRIMARY KEY (session_pk, routing_order)
);

CREATE TABLE IF NOT EXISTS convo.segments (
    segment_pk              BIGSERIAL PRIMARY KEY,
    segment_key             TEXT NOT NULL UNIQUE,
    session_pk              BIGINT NOT NULL REFERENCES convo.sessions(session_pk) ON DELETE CASCADE,
    segment_start_utc       TIMESTAMPTZ NOT NULL,
    segment_end_utc         TIMESTAMPTZ,
    segment_duration_ms     BIGINT GENERATED ALWAYS AS (
                                CASE
                                    WHEN segment_end_utc IS NULL THEN NULL
                                    ELSE (EXTRACT(EPOCH FROM (segment_end_utc - segment_start_utc)) * 1000)::BIGINT
                                END
                            ) STORED,
    segment_type            TEXT NOT NULL REFERENCES convo.dim_segment_type(segment_type) ON DELETE RESTRICT,
    conference              BOOLEAN NOT NULL DEFAULT FALSE,
    disconnect_type         TEXT,
    queue_id                UUID REFERENCES convo.dim_queue(queue_id) ON DELETE SET NULL,
    segment_index           INTEGER,
    source_json             JSONB,
    created_utc             TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_utc             TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE (session_pk, segment_start_utc, segment_end_utc, segment_type)
);

CREATE INDEX IF NOT EXISTS ix_segments_session
    ON convo.segments (session_pk, segment_start_utc);

CREATE INDEX IF NOT EXISTS ix_segments_queue_type
    ON convo.segments (queue_id, segment_type, segment_start_utc);

CREATE TABLE IF NOT EXISTS convo.metrics (
    metric_pk               BIGSERIAL PRIMARY KEY,
    metric_key              TEXT NOT NULL UNIQUE,
    session_pk              BIGINT NOT NULL REFERENCES convo.sessions(session_pk) ON DELETE CASCADE,
    metric_name             TEXT NOT NULL REFERENCES convo.dim_metric_name(metric_name) ON DELETE RESTRICT,
    metric_value            NUMERIC(20,6) NOT NULL,
    emit_utc                TIMESTAMPTZ NOT NULL,
    metric_index            INTEGER,
    source_json             JSONB,
    created_utc             TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_utc             TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE (session_pk, metric_name, emit_utc, metric_index)
);

CREATE INDEX IF NOT EXISTS ix_metrics_session
    ON convo.metrics (session_pk, emit_utc);

CREATE INDEX IF NOT EXISTS ix_metrics_name_time
    ON convo.metrics (metric_name, emit_utc DESC);

-- ---------------------------------------------------------------------------
-- Derived / reporting views
-- ---------------------------------------------------------------------------

CREATE OR REPLACE VIEW convo.v_conversation_timeline AS
SELECT
    c.conversation_id,
    c.incident_key,
    c.case_key,
    p.participant_id,
    p.participant_name,
    p.purpose,
    s.session_id,
    s.session_key,
    s.media_type,
    s.direction,
    s.provider,
    s.selected_agent_id,
    seg.segment_pk,
    seg.segment_type,
    seg.segment_start_utc,
    seg.segment_end_utc,
    seg.segment_duration_ms,
    seg.disconnect_type,
    seg.queue_id,
    seg.conference
FROM convo.conversations c
JOIN convo.participants p
  ON p.conversation_id = c.conversation_id
JOIN convo.sessions s
  ON s.participant_pk = p.participant_pk
JOIN convo.segments seg
  ON seg.session_pk = s.session_pk;

CREATE OR REPLACE VIEW convo.v_metric_timeline AS
SELECT
    c.conversation_id,
    c.incident_key,
    c.case_key,
    p.participant_id,
    p.purpose,
    s.session_id,
    s.session_key,
    s.media_type,
    m.metric_name,
    m.metric_value,
    m.emit_utc
FROM convo.conversations c
JOIN convo.participants p
  ON p.conversation_id = c.conversation_id
JOIN convo.sessions s
  ON s.participant_pk = p.participant_pk
JOIN convo.metrics m
  ON m.session_pk = s.session_pk;

CREATE OR REPLACE VIEW convo.v_conversation_summary AS
SELECT
    c.conversation_id,
    c.conversation_start_utc,
    c.conversation_end_utc,
    c.originating_direction,
    c.media_stats_min_conversation_mos,
    c.media_stats_min_conversation_rfactor,
    c.incident_key,
    c.case_key,
    c.participant_count,
    c.session_count,
    c.segment_count,
    c.metric_count,
    COALESCE(array_agg(DISTINCT cd.division_id) FILTER (WHERE cd.division_id IS NOT NULL), ARRAY[]::UUID[]) AS division_ids,
    COALESCE(array_agg(DISTINCT p.user_id) FILTER (WHERE p.user_id IS NOT NULL), ARRAY[]::UUID[]) AS user_ids,
    COALESCE(array_agg(DISTINCT seg.queue_id) FILTER (WHERE seg.queue_id IS NOT NULL), ARRAY[]::UUID[]) AS queue_ids
FROM convo.conversations c
LEFT JOIN convo.conversation_divisions cd
  ON cd.conversation_id = c.conversation_id
LEFT JOIN convo.participants p
  ON p.conversation_id = c.conversation_id
LEFT JOIN convo.sessions s
  ON s.participant_pk = p.participant_pk
LEFT JOIN convo.segments seg
  ON seg.session_pk = s.session_pk
GROUP BY
    c.conversation_id,
    c.conversation_start_utc,
    c.conversation_end_utc,
    c.originating_direction,
    c.media_stats_min_conversation_mos,
    c.media_stats_min_conversation_rfactor,
    c.incident_key,
    c.case_key,
    c.participant_count,
    c.session_count,
    c.segment_count,
    c.metric_count;

CREATE OR REPLACE VIEW convo.v_conversation_incident_candidates AS
SELECT
    c.conversation_id,
    c.conversation_start_utc,
    c.conversation_end_utc,
    c.media_stats_min_conversation_mos,
    c.media_stats_min_conversation_rfactor,
    MAX(CASE WHEN m.metric_name = 'nError' THEN m.metric_value ELSE 0 END) AS nerror_max,
    COUNT(*) FILTER (WHERE seg.disconnect_type IS NOT NULL) AS disconnect_events,
    COUNT(*) FILTER (WHERE seg.segment_type = 'hold') AS hold_segments
FROM convo.conversations c
LEFT JOIN convo.participants p
  ON p.conversation_id = c.conversation_id
LEFT JOIN convo.sessions s
  ON s.participant_pk = p.participant_pk
LEFT JOIN convo.segments seg
  ON seg.session_pk = s.session_pk
LEFT JOIN convo.metrics m
  ON m.session_pk = s.session_pk
GROUP BY
    c.conversation_id,
    c.conversation_start_utc,
    c.conversation_end_utc,
    c.media_stats_min_conversation_mos,
    c.media_stats_min_conversation_rfactor;

-- ---------------------------------------------------------------------------
-- Case management
-- ---------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS convo.cases (
    case_id         UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    case_key        TEXT NOT NULL UNIQUE,
    incident_key    TEXT NOT NULL DEFAULT '',
    name            TEXT NOT NULL,
    description     TEXT NOT NULL DEFAULT '',
    state           TEXT NOT NULL DEFAULT 'active',
    notes           TEXT NOT NULL DEFAULT '',
    retention_days  INTEGER NOT NULL DEFAULT 90,
    created_utc     TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_utc     TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    closed_utc      TIMESTAMPTZ,
    expires_utc     TIMESTAMPTZ,
    CONSTRAINT ck_cases_state CHECK (state IN ('active','closed','archived'))
);

-- ---------------------------------------------------------------------------
-- Denormalised grid table (fast column-filtered pagination at 100k+/day scale)
-- ---------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS convo.conversation_grid (
    conversation_id         UUID PRIMARY KEY,
    ingest_run_id           UUID REFERENCES convo.ingest_runs(ingest_run_id) ON DELETE SET NULL,
    case_key                TEXT NOT NULL DEFAULT '',
    incident_key            TEXT NOT NULL DEFAULT '',
    originating_direction   TEXT NOT NULL DEFAULT '',
    media_types             TEXT NOT NULL DEFAULT '',
    queue_names             TEXT NOT NULL DEFAULT '',
    agent_ids               TEXT NOT NULL DEFAULT '',
    division_ids            TEXT NOT NULL DEFAULT '',
    ani                     TEXT NOT NULL DEFAULT '',
    dnis                    TEXT NOT NULL DEFAULT '',
    disconnect_types        TEXT NOT NULL DEFAULT '',
    duration_ms             BIGINT NOT NULL DEFAULT 0,
    has_hold                BOOLEAN NOT NULL DEFAULT FALSE,
    has_mos                 BOOLEAN NOT NULL DEFAULT FALSE,
    segment_count           INTEGER NOT NULL DEFAULT 0,
    participant_count       INTEGER NOT NULL DEFAULT 0,
    conversation_start_utc  TIMESTAMPTZ,
    conversation_end_utc    TIMESTAMPTZ,
    tags                    TEXT[],
    retention_expires_utc   TIMESTAMPTZ,
    payload_json            JSONB,
    inserted_utc            TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_utc             TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS ix_grid_start
    ON convo.conversation_grid (conversation_start_utc DESC);

CREATE INDEX IF NOT EXISTS ix_grid_case_start
    ON convo.conversation_grid (case_key, conversation_start_utc DESC);

CREATE INDEX IF NOT EXISTS ix_grid_incident_start
    ON convo.conversation_grid (incident_key, conversation_start_utc DESC);

CREATE INDEX IF NOT EXISTS ix_grid_direction
    ON convo.conversation_grid (originating_direction, conversation_start_utc DESC);

CREATE INDEX IF NOT EXISTS ix_grid_retention
    ON convo.conversation_grid (retention_expires_utc)
    WHERE retention_expires_utc IS NOT NULL;

CREATE INDEX IF NOT EXISTS ix_grid_payload_gin
    ON convo.conversation_grid USING GIN (payload_json);

-- ---------------------------------------------------------------------------
-- Maintenance helpers
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION convo.set_updated_utc()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
    NEW.updated_utc := NOW();
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_ingest_runs_updated_utc ON convo.ingest_runs;
CREATE TRIGGER trg_ingest_runs_updated_utc
BEFORE UPDATE ON convo.ingest_runs
FOR EACH ROW EXECUTE FUNCTION convo.set_updated_utc();

DROP TRIGGER IF EXISTS trg_participants_updated_utc ON convo.participants;
CREATE TRIGGER trg_participants_updated_utc
BEFORE UPDATE ON convo.participants
FOR EACH ROW EXECUTE FUNCTION convo.set_updated_utc();

DROP TRIGGER IF EXISTS trg_sessions_updated_utc ON convo.sessions;
CREATE TRIGGER trg_sessions_updated_utc
BEFORE UPDATE ON convo.sessions
FOR EACH ROW EXECUTE FUNCTION convo.set_updated_utc();

DROP TRIGGER IF EXISTS trg_segments_updated_utc ON convo.segments;
CREATE TRIGGER trg_segments_updated_utc
BEFORE UPDATE ON convo.segments
FOR EACH ROW EXECUTE FUNCTION convo.set_updated_utc();

DROP TRIGGER IF EXISTS trg_metrics_updated_utc ON convo.metrics;
CREATE TRIGGER trg_metrics_updated_utc
BEFORE UPDATE ON convo.metrics
FOR EACH ROW EXECUTE FUNCTION convo.set_updated_utc();

DROP TRIGGER IF EXISTS trg_cases_updated_utc ON convo.cases;
CREATE TRIGGER trg_cases_updated_utc
BEFORE UPDATE ON convo.cases
FOR EACH ROW EXECUTE FUNCTION convo.set_updated_utc();

DROP TRIGGER IF EXISTS trg_conversation_grid_updated_utc ON convo.conversation_grid;
CREATE TRIGGER trg_conversation_grid_updated_utc
BEFORE UPDATE ON convo.conversation_grid
FOR EACH ROW EXECUTE FUNCTION convo.set_updated_utc();

-- ---------------------------------------------------------------------------
-- Retention purge helper
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION convo.purge_expired()
RETURNS INTEGER
LANGUAGE plpgsql
AS $$
DECLARE
    deleted_count INTEGER;
BEGIN
    DELETE FROM convo.conversation_grid
    WHERE retention_expires_utc IS NOT NULL
      AND retention_expires_utc < NOW();
    GET DIAGNOSTICS deleted_count = ROW_COUNT;
    RETURN deleted_count;
END;
$$;

COMMIT;
