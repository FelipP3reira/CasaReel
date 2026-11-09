# Modelo de Dados (visão DBA)

SGBD: **PostgreSQL 16**. DDL completo em [`schema.sql`](schema.sql). Guia operacional em [`guia-dba.md`](guia-dba.md).

## 1. Diagrama ER (Fases 1 e 2 + extensão da Fase 3)

```mermaid
erDiagram
    users ||--o{ device_sessions : "tem"
    users ||--o{ properties : "possui"
    users ||--o{ subscriptions : "assina"
    users ||--o{ credit_ledger : "movimenta"
    users ||--o{ consents : "concede"
    properties ||--o{ media_assets : "contém"
    properties ||--o{ jobs : "gera"
    properties ||--o{ captures : "tem"
    media_assets ||--o{ job_inputs : "alimenta"
    jobs ||--o{ job_inputs : "usa"
    jobs ||--o{ outputs : "produz"
    captures ||--o{ jobs : "dispara"
    outputs ||--o{ share_links : "compartilhado por"
    templates ||--o{ jobs : "aplicado em"
    users ||--o{ audit_log : "gera"
    properties ||--o| listings : "publica (Fase 3)"
    listings ||--o{ inquiries : "recebe (Fase 3)"
    users ||--o{ inquiries : "envia (Fase 3)"

    users {
        uuid id PK
        text apple_sub UK
        citext email UK
        text password_hash
        text status
        timestamptz deletion_requested_at
        timestamptz created_at
    }
    device_sessions {
        uuid id PK
        uuid user_id FK
        uuid family_id
        bytea refresh_token_hash UK
        timestamptz used_at
        timestamptz expires_at
        timestamptz revoked_at
    }
    properties {
        uuid id PK
        uuid owner_id FK
        text title
        text city_public
        bytea address_encrypted
        text visibility
        timestamptz deleted_at
    }
    media_assets {
        uuid id PK
        uuid property_id FK
        text kind
        text status
        text storage_key
        text sha256
        bigint size_bytes
        int width
        int height
        jsonb analysis
    }
    jobs {
        uuid id PK
        uuid property_id FK
        text type
        text status
        jsonb payload
        text idempotency_key
        int attempts
        numeric cost_estimated_brl
        numeric cost_actual_brl
        timestamptz queued_at
        timestamptz finished_at
    }
    outputs {
        uuid id PK
        uuid job_id FK
        text kind
        text storage_key
        text sha256
        jsonb metadata
        boolean synthetic_content
    }
    share_links {
        uuid id PK
        uuid output_id FK
        bytea token_hash UK
        timestamptz expires_at
        timestamptz revoked_at
    }
    captures {
        uuid id PK
        uuid property_id FK
        text status
        jsonb quality_report
    }
    templates {
        uuid id PK
        text slug UK
        int version
        jsonb spec
        boolean active
    }
    subscriptions {
        uuid id PK
        uuid user_id FK
        text product_id
        text status
        timestamptz current_period_end
    }
    credit_ledger {
        bigint id PK
        uuid user_id FK
        int delta
        text reason
        uuid job_id
    }
    consents {
        uuid id PK
        uuid user_id FK
        text purpose
        timestamptz granted_at
        timestamptz revoked_at
    }
    audit_log {
        bigint id PK
        uuid actor_id
        text action
        timestamptz at
    }
    listings {
        uuid id PK
        uuid property_id FK
        text status
        numeric price
        geography location
    }
    inquiries {
        uuid id PK
        uuid listing_id FK
        uuid sender_id FK
        text status
    }
```

## 2. Decisões de modelagem

| Tema | Decisão | Motivo |
|---|---|---|
| Chaves | `uuid` v7 (ordenável no tempo) gerado pela aplicação | Sem enumeração, bom índice B-tree, sem expor contagem |
| E-mail | `citext` com índice único parcial (`WHERE deleted_at IS NULL`) | Unicidade sem diferenciar maiúsculas |
| Endereço do imóvel | Criptografado em nível de aplicação (`bytea`), com `city_public` separada | Minimiza exposição mesmo em dump do banco |
| Tokens | Apenas **hash** (SHA-256) de refresh token e de share token | Vazamento de banco não revela tokens |
| Jobs | Tabela única com `type` + `payload` JSONB validado por JSON Schema na aplicação | Cobre vídeo, 3D e futuros tipos |
| Idempotência | `UNIQUE (owner_id, idempotency_key)` em `jobs` | Evita cobrança dupla em retry |
| Status | `CHECK` com conjunto fechado + máquina de estados na aplicação | Evita estados inválidos |
| Créditos | **Ledger** imutável (`credit_ledger`) com saldo derivado | Auditoria e anti-fraude |
| Exclusão | Soft delete + purge agendado (`deletion_requested_at`) | Carência de 7 dias e LGPD |
| Mídia | Banco guarda só metadados e `storage_key`; binário no object storage | Banco leve |
| Fase 3 | `listings`/`inquiries` aditivos; PostGIS apenas quando necessário | Migração sem quebra |
| Conteúdo sintético | `outputs.synthetic_content` obrigatório | Rotulagem (ADR-008) |

## 3. Máquina de estados dos jobs

```mermaid
stateDiagram-v2
    [*] --> queued
    queued --> running: worker pega
    running --> succeeded
    running --> failed: erro não recuperável
    running --> retrying: erro transitório
    retrying --> queued: backoff
    queued --> canceled
    running --> canceled
    failed --> [*]
    succeeded --> [*]
    canceled --> [*]
```

## 4. Máquina de estados de `media_assets`

```mermaid
stateDiagram-v2
    [*] --> pending: intent criada
    pending --> uploaded: cliente confirma
    uploaded --> processing: worker valida
    processing --> ready: ok
    processing --> rejected: inválido/malicioso
    pending --> expired: URL expirou sem upload
    ready --> deleted
    rejected --> deleted
```

## 5. Dados que NÃO ficam no banco

- Binários (fotos, vídeos, splats) → object storage
- Segredos e chaves → gerenciador de segredos/KMS
- Logs de aplicação → plataforma de logs (sem PII)
