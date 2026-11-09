-- =============================================================================
-- CasaReel — schema PostgreSQL 16
-- Fases 1 e 2 completas; Fase 3 (listings/inquiries) incluída como extensão aditiva.
-- Convenções: snake_case, timestamptz (UTC), uuid v7 gerado pela aplicação,
-- soft delete via deleted_at, sem PII em colunas de log.
-- Em produção, aplique via migrations do Laravel; este arquivo é a referência.
-- =============================================================================

CREATE EXTENSION IF NOT EXISTS citext;
CREATE EXTENSION IF NOT EXISTS pgcrypto;

-- -----------------------------------------------------------------------------
-- Funções utilitárias
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION set_updated_at() RETURNS trigger AS $$
BEGIN
    NEW.updated_at = now();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- -----------------------------------------------------------------------------
-- Identidade
-- -----------------------------------------------------------------------------
CREATE TABLE users (
    id                      uuid PRIMARY KEY,
    apple_sub               text UNIQUE,
    email                   citext,
    email_verified_at       timestamptz,
    password_hash           text,                       -- Argon2id; NULL para login Apple
    mfa_secret_encrypted    bytea,                      -- TOTP cifrado na aplicação
    display_name            text,
    locale                  text NOT NULL DEFAULT 'pt-BR',
    status                  text NOT NULL DEFAULT 'active'
                            CHECK (status IN ('active','suspended','pending_deletion','deleted')),
    deletion_requested_at   timestamptz,
    created_at              timestamptz NOT NULL DEFAULT now(),
    updated_at              timestamptz NOT NULL DEFAULT now(),
    deleted_at              timestamptz,
    CONSTRAINT users_has_identity CHECK (apple_sub IS NOT NULL OR email IS NOT NULL)
);
CREATE UNIQUE INDEX users_email_uq ON users (email) WHERE deleted_at IS NULL AND email IS NOT NULL;
CREATE INDEX users_pending_deletion_idx ON users (deletion_requested_at) WHERE status = 'pending_deletion';
CREATE TRIGGER users_updated BEFORE UPDATE ON users FOR EACH ROW EXECUTE FUNCTION set_updated_at();

CREATE TABLE device_sessions (
    id                  uuid PRIMARY KEY,
    user_id             uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    family_id           uuid NOT NULL,                  -- família de rotação do refresh token
    device_id           text NOT NULL,                  -- identificador opaco do app (não é IDFA)
    refresh_token_hash  bytea NOT NULL UNIQUE,          -- SHA-256; nunca o token em claro
    app_attest_key_id   text,                           -- chave App Attest vinculada ao dispositivo
    last_ip_hash        bytea,                          -- hash com sal; sem IP em claro
    user_agent          text,
    created_at          timestamptz NOT NULL DEFAULT now(),
    used_at             timestamptz,
    expires_at          timestamptz NOT NULL,
    revoked_at          timestamptz
);
CREATE INDEX device_sessions_user_idx ON device_sessions (user_id) WHERE revoked_at IS NULL;
CREATE INDEX device_sessions_family_idx ON device_sessions (family_id);
CREATE INDEX device_sessions_expiry_idx ON device_sessions (expires_at);

-- -----------------------------------------------------------------------------
-- Consentimentos e auditoria
-- -----------------------------------------------------------------------------
CREATE TABLE consents (
    id              uuid PRIMARY KEY,
    user_id         uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    purpose         text NOT NULL CHECK (purpose IN ('terms','privacy_policy','marketing','analytics','ai_improvement')),
    version         text NOT NULL,                      -- versão do texto aceito
    granted_at      timestamptz NOT NULL DEFAULT now(),
    revoked_at      timestamptz
);
CREATE INDEX consents_user_purpose_idx ON consents (user_id, purpose);

CREATE TABLE audit_log (
    id          bigint GENERATED ALWAYS AS IDENTITY,
    at          timestamptz NOT NULL DEFAULT now(),
    actor_id    uuid,                                   -- usuário ou NULL (sistema)
    actor_type  text NOT NULL DEFAULT 'user' CHECK (actor_type IN ('user','admin','system')),
    action      text NOT NULL,                          -- ex.: auth.login, property.delete, share.revoke
    entity_type text,
    entity_id   uuid,
    ip_hash     bytea,
    metadata    jsonb NOT NULL DEFAULT '{}'::jsonb,     -- sem PII
    PRIMARY KEY (id, at)
) PARTITION BY RANGE (at);
CREATE TABLE audit_log_default PARTITION OF audit_log DEFAULT;
CREATE INDEX audit_log_actor_idx ON audit_log (actor_id, at DESC);
CREATE INDEX audit_log_entity_idx ON audit_log (entity_type, entity_id, at DESC);

-- -----------------------------------------------------------------------------
-- Imóveis e mídia
-- -----------------------------------------------------------------------------
CREATE TABLE properties (
    id                  uuid PRIMARY KEY,
    owner_id            uuid NOT NULL REFERENCES users(id) ON DELETE RESTRICT,
    title               text NOT NULL CHECK (char_length(title) BETWEEN 1 AND 140),
    description         text CHECK (char_length(description) <= 4000),
    city_public         text,                           -- exibível publicamente
    address_encrypted   bytea,                          -- endereço exato cifrado (app-level)
    visibility          text NOT NULL DEFAULT 'private' CHECK (visibility IN ('private','unlisted','public')),
    created_at          timestamptz NOT NULL DEFAULT now(),
    updated_at          timestamptz NOT NULL DEFAULT now(),
    deleted_at          timestamptz
);
CREATE INDEX properties_owner_idx ON properties (owner_id) WHERE deleted_at IS NULL;
CREATE TRIGGER properties_updated BEFORE UPDATE ON properties FOR EACH ROW EXECUTE FUNCTION set_updated_at();

CREATE TABLE media_assets (
    id              uuid PRIMARY KEY,
    property_id     uuid NOT NULL REFERENCES properties(id) ON DELETE CASCADE,
    owner_id        uuid NOT NULL REFERENCES users(id) ON DELETE RESTRICT,
    kind            text NOT NULL CHECK (kind IN ('photo','capture_frame','capture_meta','audio','logo','derivative')),
    status          text NOT NULL DEFAULT 'pending'
                    CHECK (status IN ('pending','uploaded','processing','ready','rejected','expired','deleted')),
    reject_reason   text,
    storage_key     text NOT NULL UNIQUE,               -- caminho opaco no bucket
    mime_type       text NOT NULL,
    size_bytes      bigint NOT NULL CHECK (size_bytes > 0 AND size_bytes <= 26214400),  -- 25 MB
    sha256          text NOT NULL CHECK (sha256 ~ '^[0-9a-f]{64}$'),
    width           int,
    height          int,
    room_type       text,                               -- sala, quarto, cozinha...
    position        int,                                -- ordem escolhida pelo usuário
    analysis        jsonb NOT NULL DEFAULT '{}'::jsonb, -- scores de qualidade, blur, exposição
    created_at      timestamptz NOT NULL DEFAULT now(),
    updated_at      timestamptz NOT NULL DEFAULT now(),
    deleted_at      timestamptz
);
CREATE INDEX media_assets_property_idx ON media_assets (property_id, kind, position) WHERE deleted_at IS NULL;
CREATE INDEX media_assets_status_idx ON media_assets (status) WHERE status IN ('pending','uploaded','processing');
CREATE UNIQUE INDEX media_assets_dedup_idx ON media_assets (property_id, sha256) WHERE deleted_at IS NULL AND kind = 'photo';
CREATE TRIGGER media_assets_updated BEFORE UPDATE ON media_assets FOR EACH ROW EXECUTE FUNCTION set_updated_at();

-- -----------------------------------------------------------------------------
-- Templates de vídeo (spec JSON versionado compartilhado por app e workers)
-- -----------------------------------------------------------------------------
CREATE TABLE templates (
    id          uuid PRIMARY KEY,
    slug        text NOT NULL,
    version     int NOT NULL,
    name        text NOT NULL,
    spec        jsonb NOT NULL,
    premium     boolean NOT NULL DEFAULT false,
    active      boolean NOT NULL DEFAULT true,
    created_at  timestamptz NOT NULL DEFAULT now(),
    UNIQUE (slug, version)
);

-- -----------------------------------------------------------------------------
-- Capturas 3D (Fase 2)
-- -----------------------------------------------------------------------------
CREATE TABLE captures (
    id              uuid PRIMARY KEY,
    property_id     uuid NOT NULL REFERENCES properties(id) ON DELETE CASCADE,
    owner_id        uuid NOT NULL REFERENCES users(id) ON DELETE RESTRICT,
    status          text NOT NULL DEFAULT 'created'
                    CHECK (status IN ('created','uploading','uploaded','validating','needs_recapture','accepted','rejected')),
    device_model    text,
    has_lidar       boolean NOT NULL DEFAULT false,
    frame_count     int,
    quality_report  jsonb NOT NULL DEFAULT '{}'::jsonb, -- cobertura, blur, sobreposição por cômodo
    created_at      timestamptz NOT NULL DEFAULT now(),
    updated_at      timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX captures_property_idx ON captures (property_id);
CREATE TRIGGER captures_updated BEFORE UPDATE ON captures FOR EACH ROW EXECUTE FUNCTION set_updated_at();

-- -----------------------------------------------------------------------------
-- Jobs (vídeo, análise, 360, 3D) e saídas
-- -----------------------------------------------------------------------------
CREATE TABLE jobs (
    id                  uuid PRIMARY KEY,
    owner_id            uuid NOT NULL REFERENCES users(id) ON DELETE RESTRICT,
    property_id         uuid NOT NULL REFERENCES properties(id) ON DELETE CASCADE,
    capture_id          uuid REFERENCES captures(id) ON DELETE SET NULL,
    template_id         uuid REFERENCES templates(id),
    type                text NOT NULL CHECK (type IN ('analyze_photos','render_video','build_tour_360','validate_capture','reconstruct_3d','moderate_media')),
    status              text NOT NULL DEFAULT 'queued'
                        CHECK (status IN ('queued','running','retrying','succeeded','failed','canceled')),
    queue               text NOT NULL DEFAULT 'default',
    payload             jsonb NOT NULL DEFAULT '{}'::jsonb,
    idempotency_key     text NOT NULL,
    attempts            int NOT NULL DEFAULT 0,
    max_attempts        int NOT NULL DEFAULT 3,
    error_code          text,
    error_message       text,                           -- sem PII
    cost_estimated_brl  numeric(10,4) NOT NULL DEFAULT 0,
    cost_actual_brl     numeric(10,4),
    gpu_seconds         numeric(10,2),
    worker_version      text,
    queued_at           timestamptz NOT NULL DEFAULT now(),
    started_at          timestamptz,
    finished_at         timestamptz,
    UNIQUE (owner_id, idempotency_key)
);
CREATE INDEX jobs_status_queue_idx ON jobs (queue, status, queued_at) WHERE status IN ('queued','retrying');
CREATE INDEX jobs_property_idx ON jobs (property_id, queued_at DESC);
CREATE INDEX jobs_owner_idx ON jobs (owner_id, queued_at DESC);

CREATE TABLE job_inputs (
    job_id          uuid NOT NULL REFERENCES jobs(id) ON DELETE CASCADE,
    media_asset_id  uuid NOT NULL REFERENCES media_assets(id) ON DELETE RESTRICT,
    position        int NOT NULL DEFAULT 0,
    PRIMARY KEY (job_id, media_asset_id)
);
CREATE INDEX job_inputs_asset_idx ON job_inputs (media_asset_id);

CREATE TABLE outputs (
    id                  uuid PRIMARY KEY,
    job_id              uuid NOT NULL REFERENCES jobs(id) ON DELETE CASCADE,
    property_id         uuid NOT NULL REFERENCES properties(id) ON DELETE CASCADE,
    owner_id            uuid NOT NULL REFERENCES users(id) ON DELETE RESTRICT,
    kind                text NOT NULL CHECK (kind IN ('video_vertical','video_horizontal','thumbnail','tour_360','tour_3d','manifest')),
    storage_key         text NOT NULL UNIQUE,
    mime_type           text NOT NULL,
    size_bytes          bigint,
    sha256              text CHECK (sha256 IS NULL OR sha256 ~ '^[0-9a-f]{64}$'),
    duration_ms         int,
    synthetic_content   boolean NOT NULL DEFAULT false, -- rotulagem (ADR-008)
    watermark           boolean NOT NULL DEFAULT false,
    metadata            jsonb NOT NULL DEFAULT '{}'::jsonb,
    created_at          timestamptz NOT NULL DEFAULT now(),
    deleted_at          timestamptz
);
CREATE INDEX outputs_property_idx ON outputs (property_id, kind) WHERE deleted_at IS NULL;
CREATE INDEX outputs_job_idx ON outputs (job_id);

CREATE TABLE share_links (
    id              uuid PRIMARY KEY,
    output_id       uuid NOT NULL REFERENCES outputs(id) ON DELETE CASCADE,
    owner_id        uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    token_hash      bytea NOT NULL UNIQUE,              -- SHA-256 do token de 256 bits
    expires_at      timestamptz,
    revoked_at      timestamptz,
    view_count      bigint NOT NULL DEFAULT 0,
    max_views       bigint,
    created_at      timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX share_links_output_idx ON share_links (output_id);

-- -----------------------------------------------------------------------------
-- Cobrança
-- -----------------------------------------------------------------------------
CREATE TABLE subscriptions (
    id                      uuid PRIMARY KEY,
    user_id                 uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    provider                text NOT NULL DEFAULT 'apple' CHECK (provider IN ('apple','google','stripe')),
    product_id              text NOT NULL,
    original_transaction_id text NOT NULL,
    status                  text NOT NULL CHECK (status IN ('active','grace','billing_retry','expired','revoked','refunded')),
    current_period_end      timestamptz,
    auto_renew              boolean,
    environment             text NOT NULL CHECK (environment IN ('production','sandbox')),
    updated_at              timestamptz NOT NULL DEFAULT now(),
    UNIQUE (provider, original_transaction_id)
);
CREATE INDEX subscriptions_user_idx ON subscriptions (user_id);

CREATE TABLE billing_events (
    id                  uuid PRIMARY KEY,
    provider            text NOT NULL,
    external_id         text NOT NULL,                  -- notificationUUID da Apple
    type                text NOT NULL,
    received_at         timestamptz NOT NULL DEFAULT now(),
    processed_at        timestamptz,
    UNIQUE (provider, external_id)                      -- idempotência de webhook
);

CREATE TABLE credit_ledger (
    id          bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    user_id     uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    delta       int NOT NULL CHECK (delta <> 0),
    reason      text NOT NULL CHECK (reason IN ('purchase','subscription_grant','job_debit','job_refund','admin_adjust','promo')),
    job_id      uuid REFERENCES jobs(id) ON DELETE SET NULL,
    external_ref text,
    created_at  timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX credit_ledger_user_idx ON credit_ledger (user_id, created_at DESC);
CREATE UNIQUE INDEX credit_ledger_job_debit_uq ON credit_ledger (job_id, reason) WHERE reason IN ('job_debit','job_refund');

CREATE VIEW v_credit_balance AS
    SELECT user_id, COALESCE(SUM(delta),0)::int AS balance
    FROM credit_ledger GROUP BY user_id;

-- -----------------------------------------------------------------------------
-- Fase 3 — Marketplace (aditivo; criar apenas quando a fase iniciar)
-- -----------------------------------------------------------------------------
CREATE TABLE listings (
    id              uuid PRIMARY KEY,
    property_id     uuid NOT NULL UNIQUE REFERENCES properties(id) ON DELETE CASCADE,
    status          text NOT NULL DEFAULT 'draft' CHECK (status IN ('draft','in_review','published','paused','rejected','archived')),
    price_cents     bigint CHECK (price_cents IS NULL OR price_cents >= 0),
    currency        char(3) NOT NULL DEFAULT 'BRL',
    price_unit      text CHECK (price_unit IN ('night','month','sale')),
    -- location geography(Point,4326) -> habilitar PostGIS na Fase 3 e adicionar coluna + GIST
    published_at    timestamptz,
    created_at      timestamptz NOT NULL DEFAULT now(),
    updated_at      timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX listings_status_idx ON listings (status, published_at DESC);
CREATE TRIGGER listings_updated BEFORE UPDATE ON listings FOR EACH ROW EXECUTE FUNCTION set_updated_at();

CREATE TABLE inquiries (
    id          uuid PRIMARY KEY,
    listing_id  uuid NOT NULL REFERENCES listings(id) ON DELETE CASCADE,
    sender_id   uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    status      text NOT NULL DEFAULT 'open' CHECK (status IN ('open','answered','closed','spam')),
    message     text NOT NULL CHECK (char_length(message) <= 2000),
    created_at  timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX inquiries_listing_idx ON inquiries (listing_id, created_at DESC);

CREATE TABLE reports (
    id              uuid PRIMARY KEY,
    reporter_id     uuid REFERENCES users(id) ON DELETE SET NULL,
    entity_type     text NOT NULL CHECK (entity_type IN ('listing','property','output','user')),
    entity_id       uuid NOT NULL,
    reason          text NOT NULL,
    status          text NOT NULL DEFAULT 'open' CHECK (status IN ('open','reviewing','actioned','dismissed')),
    created_at      timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX reports_open_idx ON reports (status, created_at) WHERE status IN ('open','reviewing');

-- -----------------------------------------------------------------------------
-- Papéis de banco (menor privilégio) — ajuste nomes/senhas via secrets
-- -----------------------------------------------------------------------------
-- CREATE ROLE app_rw LOGIN PASSWORD '***';       -- API Laravel
-- CREATE ROLE worker_rw LOGIN PASSWORD '***';    -- workers (somente jobs/media/outputs)
-- CREATE ROLE readonly_bi LOGIN PASSWORD '***';  -- BI sem acesso a colunas sensíveis
-- GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO app_rw;
-- GRANT SELECT, UPDATE ON jobs, media_assets, captures TO worker_rw;
-- GRANT INSERT ON outputs, job_inputs TO worker_rw;
-- REVOKE ALL ON users, device_sessions, subscriptions FROM worker_rw, readonly_bi;
-- REVOKE UPDATE, DELETE ON audit_log FROM app_rw;  -- audit_log é append-only
