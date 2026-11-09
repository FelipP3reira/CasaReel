# Prompts do Backend (Laravel) e Workers (Python) — para Claude Code

Use na raiz do repositório do backend, com a pasta `casareel-docs/` em `docs/`. Mesmo método dos prompts do Xcode: contexto global primeiro, depois um prompt por vez, revisando o diff e rodando os testes.

## Contexto global (CLAUDE.md do backend)

```
Projeto: API CasaReel (Laravel 13, PHP 8.4, PostgreSQL 16, Redis 7, Horizon, Pest) + workers Python 3.12.
Fonte da verdade: docs/06-api/openapi.yaml (API), docs/03-dados/schema.sql (banco), docs/05-seguranca/* (segurança), docs/02-arquitetura/* (fluxos).

Regras inegociáveis:
- Autorização em TODA rota via Policy com checagem de dono; falha fechada; 404 (não 403) para recurso de outro usuário.
- Validação por FormRequest estrito; nunca mass assignment; nunca SQL concatenado; sem DB::raw com entrada do usuário.
- Segredos só por variáveis de ambiente/secrets manager; nada em código/log.
- Logs estruturados sem PII (sem e-mail, endereço, tokens, URLs assinadas).
- Tokens (refresh, share) guardados apenas como hash; refresh rotativo com detecção de reuso.
- Uploads nunca passam pelo PHP: URL pré-assinada; arquivo novo vai para quarentena até a sanitização.
- Billing: validar JWS Apple no servidor; idempotência por notificationUUID; ledger de créditos imutável.
- Rate limit por IP, usuário e dispositivo; Idempotency-Key em POST de criação.
- Migrations aditivas e retrocompatíveis; toda tabela com chaves e constraints do schema.sql.
- Testes Pest obrigatórios por feature, incluindo teste de autorização (dono × outro × anônimo).
- Se algo for ambíguo, perguntar antes de assumir.
```

## Índice

| Prompt | Tema |
|---|---|
| B01 | Bootstrap Laravel + Docker Compose + CI |
| B02 | Banco: migrations do schema.sql, models, factories, policies base |
| B03 | Autenticação: Sign in with Apple, tokens, refresh rotativo, App Attest |
| B04 | Imóveis e autorização (BOLA-proof) |
| B05 | Upload: intents pré-assinadas, quarentena, complete |
| B06 | Workers Python: validação/sanitização de mídia (sandbox) |
| B07 | Jobs e filas: modelo, estados, idempotência, custos |
| B08 | Análise de fotos e render no servidor (FFmpeg) |
| B09 | Templates (assinados) e vídeos locais registrados |
| B10 | Share links e endpoint público |
| B11 | Billing: Apple JWS, Notifications V2, ledger de créditos |
| B12 | LGPD: consentimentos, exportação, exclusão (purge) |
| B13 | Segurança transversal: cabeçalhos, rate limit, auditoria, antifraude |
| B14 | Observabilidade e FinOps |
| B20 | Fase 2: capturas, validação e job de reconstrução 3D |
| B21 | Fase 2: manifest do tour, viewer tokens, CSP |

## Prompts

### B01 — Bootstrap
```
Crie o projeto Laravel 13 (PHP 8.4) com Docker Compose (app, nginx, postgres:16, redis:7, minio, mailpit, worker Horizon). Configure: Pest, Larastan nível 8, Pint, Rector (opcional), GitHub Actions (lint, testes, composer audit, gitleaks, CodeQL), .env.example sem segredos, healthcheck /up, logging JSON com redator de PII, timezone UTC, config de CORS restrito e cabeçalhos de segurança (nosniff, HSTS, Referrer-Policy, Permissions-Policy, Cache-Control no-store em rotas autenticadas), trust proxies, e versionamento de rotas /v1. Critérios: `make test` e CI verdes; nenhum segredo no repo; README com setup.
```

### B02 — Banco
```
Traduza docs/03-dados/schema.sql em migrations Laravel (uma por grupo lógico), models com $fillable explícito, casts, factories, e global scope por owner_id onde aplicável. Use UUID v7 gerado na aplicação. Implemente os papéis de banco (app_rw, worker_rw) como script de infra. Adicione squawk ao CI. Escreva testes que provam as constraints (CHECK, UNIQUE parcial, FK) e a unicidade (owner_id, idempotency_key). Critérios: migrate:fresh e rollback funcionam; testes de constraints verdes.
```

### B03 — Autenticação
```
Implemente /auth/apple, /auth/refresh, /auth/logout, /attest/challenge e /attest/register conforme docs/02-arquitetura/fluxos-sequencia.md e openapi.yaml. Validação do identityToken Apple (JWKS com cache, iss, aud, exp, nonce); access token de 15 min; refresh opaco de 256 bits armazenado como SHA-256, rotativo por família com detecção de reuso (revoga a família); App Attest (validar attestation/assertion, contador, vincular keyId à sessão); rate limit e atraso progressivo; auditoria (audit_log). Respostas em problem+json com código estável (session_revoked). Testes: sucesso, token adulterado, nonce errado, reuso de refresh, rate limit, attest inválido.
```

### B04 — Imóveis
```
Implemente CRUD de /properties com Policy de dono, endereço cifrado em nível de coluna (envelope encryption com chave do KMS/ambiente), city_public, paginação por cursor, soft delete. Crie teste automatizado que percorre TODAS as rotas do OpenAPI e verifica: anônimo -> 401; outro usuário -> 404; dono -> 2xx. Critérios: suíte BOLA verde; endereço nunca em claro no banco nem nos logs.
```

### B05 — Upload
```
Implemente POST /properties/{id}/photos/upload-intents e POST /media/{id}/complete: validar cota/plano, tamanho (<=25 MB), mime allowlist, sha256; gerar chaves aleatórias; URL pré-assinada PUT (<=10 min) com content-length, content-type e checksum fixados; objeto cai em quarantine/; deduplicação por (property_id, sha256); ao completar, enfileirar validate_and_sanitize. Rotina de expiração de pending e órfãos. Testes: limites, mime inválido, dedup, expiração, tentativa de completar mídia de outro usuário.
```

### B06 — Worker de sanitização
```
Crie o worker Python (container não-root, read-only rootfs, sem egress, seccomp padrão, limites de CPU/RAM/tempo) que consome validate_and_sanitize: baixa de quarantine/, valida magic bytes, decodifica com limite de pixels (<=50 MP) e memória, re-encoda sem metadados (JPEG/HEIC->JPEG), gera derivados (thumb, web, análise), ClamAV opcional, calcula sha256, promove ou rejeita (motivo). Fuzz de parsers em CI. Contrato do job em JSON Schema versionado. Testes: polyglot, EXIF/GPS (deve sair limpo), bomba de pixels, arquivo truncado.
```

### B07 — Jobs e filas
```
Implemente o modelo de jobs (docs/03-dados/modelo-de-dados.md): máquina de estados, idempotência por (owner_id, idempotency_key), tentativas com backoff, DLQ, filas separadas (default, media-cpu, gpu, billing), custo estimado/real, cancelamento, ETag no GET /jobs/{id}, créditos debitados de forma atômica (transação + unique em credit_ledger). Contrato de payload validado por JSON Schema por tipo. Testes: transições inválidas, retry idempotente, débito único, cancelamento com estorno.
```

### B08 — Análise e render no servidor
```
Implemente no worker: analyze_photos (qualidade, ambiente, ordem sugerida) e render_video via FFmpeg a partir do TemplateSpec (mesmo contrato do app; mesmas funções de easing). Sem shell com entrada de usuário (argumentos como lista), tempo máximo, sandbox. Saída: vídeo 9:16/16:9, thumbnail, sha256, custo real. Testes: golden frames contra render do app (tolerância), spec inválido rejeitado.
```

### B09 — Templates e vídeos locais
```
Implemente GET /templates e /templates/{slug} (pacote assinado Ed25519, chave privada no KMS/secret), seed dos 3 templates, e POST /properties/{id}/videos para registrar vídeo renderizado no aparelho (valida template/versão, limites, entitlements: marca d'água obrigatória no plano free) retornando URL pré-assinada. Testes: assinatura, entitlements, limites.
```

### B10 — Share links
```
Implemente POST /outputs/{id}/share-links (token de 256 bits retornado uma única vez, guardado como SHA-256), DELETE /share-links/{id}, GET /public/s/{token} com respostas idênticas para inexistente/expirado/revogado, URLs assinadas curtas, X-Robots-Tag: noindex, rate limit agressivo, contador de views. Testes: enumeração, expiração, revogação, max_views.
```

### B11 — Billing
```
Implemente POST /billing/apple/transactions (validação da cadeia de certificados do JWS até a raiz Apple, bundleId, environment, appAccountToken = user id) e POST /webhooks/apple (Notifications V2, idempotência por notificationUUID via billing_events), subscriptions, entitlements e créditos (ledger imutável, saldo por view). Reembolso/revogação revertem entitlements. Testes com fixtures de JWS válidos/inválidos/duplicados e fluxo de renovação/expiração.
```

### B12 — LGPD
```
Implemente /me/consents, /me/export (job que gera ZIP com JSON + links temporários), DELETE /me (carência 7 dias, revogação de sessões e do token Apple), cancelamento da exclusão por novo login, job purge_user (storage, banco, anonimização do que precisar ser retido) e relatório de evidência sem PII. Retenções automáticas conforme docs/03-dados/guia-dba.md. Testes ponta a ponta: após purge, nenhum dado pessoal restante.
```

### B13 — Segurança transversal
```
Revise e complete: rate limiters nomeados, bloqueio progressivo, detecção de anomalias (picos de 401/403/429), audit_log append-only, política de CORS/CSP/headers, desligar debug, mensagens de erro genéricas, proteção contra enumeração (tempo e resposta), validação de Content-Type, limite de corpo, SSRF (nenhuma busca de URL do usuário). Gere um relatório docs/seguranca-backend-status.md mapeando cada item de docs/05-seguranca/checklist-masvs.md (parte API Top 10) a testes existentes.
```

### B14 — Observabilidade e FinOps
```
Adicione OpenTelemetry (trace_id propagado no payload dos jobs), métricas RED, métricas de fila e de custo por job/usuário/tipo, dashboards (JSON de Grafana), alertas descritos em docs/08-qualidade-devops/testes-cicd-observabilidade.md e teto diário de gasto de GPU com kill switch. Sentry com scrubbing de PII. Testes: logs sem PII (fixtures com e-mail/token devem ser redigidos).
```

### B20 — Fase 2: capturas e reconstrução
```
Implemente /properties/{id}/captures, /captures/{id}/complete, /captures/{id}; validate_capture (cobertura, blur, sobreposição, consistência de poses; relatório por cômodo com dicas de recaptura); job reconstruct_3d em worker GPU sob demanda (scale-to-zero, spot com checkpoint, teto de gasto) com pipeline do doc 04 (seleção de frames, refino de poses, treino de Gaussian Splatting, limpeza, compressão, avaliação em views retidas, fallback para tour 360). Registrar custo real, métricas de qualidade e versão do modelo. Testes: capture.json inválido (fuzz), recaptura, falha de GPU com retry, estouro de orçamento.
```

### B21 — Fase 2: manifest e viewer
```
Gere manifest.json do tour (cômodos, pontos iniciais, limites navegáveis, versão), endpoint GET /tours/{id}/manifest com token assinado de curta duração, entrega via CDN com URLs assinadas, e configuração de embed por domínio do anfitrião (frame-ancestors dinâmico por allowlist validada). Viewer web: CSP estrita com nonce, Trusted Types, sem innerHTML, validação do manifest por JSON Schema. Testes: manifest adulterado, domínio não permitido, token expirado.
```
