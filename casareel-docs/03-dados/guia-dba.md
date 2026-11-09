# Guia do DBA

## 1. Topologia e configuração

| Item | Recomendação |
|---|---|
| Versão | PostgreSQL 16 gerenciado (RDS/Cloud SQL/Neon/Supabase) com Multi-AZ em produção |
| Ambientes | `dev` (Docker), `staging` (espelho reduzido), `prod`. Dados reais **nunca** em dev/staging |
| Réplicas | 1 réplica de leitura quando a leitura de relatórios pesar. Painel/BI apontam para a réplica |
| Pool de conexões | PgBouncer (modo transaction) na frente do Postgres; Laravel com `persistent` desativado |
| Timezone | UTC no banco; conversão no cliente |
| Encoding/collation | UTF-8; `citext` para e-mail |
| Parâmetros iniciais | `shared_buffers` 25% da RAM, `effective_cache_size` 50–75%, `work_mem` conservador (4–16 MB), `idle_in_transaction_session_timeout` 60 s, `statement_timeout` 15 s para a API (maior para workers) |
| TLS | Obrigatório (`sslmode=verify-full`) |

## 2. Papéis e privilégios (menor privilégio)

| Papel | Acesso |
|---|---|
| `app_rw` | API: CRUD nas tabelas de negócio; sem DDL; `audit_log` somente `INSERT` |
| `worker_rw` | Workers: `jobs`, `media_assets`, `captures` (SELECT/UPDATE), `outputs`/`job_inputs` (INSERT). Sem acesso a `users`, `device_sessions`, `subscriptions` |
| `migrator` | Somente CI/CD; DDL; credencial temporária |
| `readonly_bi` | Views agregadas sem colunas sensíveis |
| Admin humano | Acesso break-glass via bastion/SSO, com auditoria e expiração |

Regras: senhas e rotação no gerenciador de segredos; nenhum acesso público ao banco (VPC privada); IP allowlist para bastion.

## 3. Segurança de dados no banco

- **Criptografia em repouso** no volume gerenciado (KMS)
- **Criptografia em nível de coluna (aplicação)** para `properties.address_encrypted` e `users.mfa_secret_encrypted`, com chave no KMS (envelope encryption), rotação anual e re-encriptação em lote
- **Hashes de token:** `device_sessions.refresh_token_hash` e `share_links.token_hash` (SHA-256 de 256 bits aleatórios)
- **Senha:** Argon2id (parâmetros calibrados em ≥ 250 ms no hardware de produção)
- **Row-Level Security (RLS):** opcional como segunda barreira. Se ativada: `ALTER TABLE properties ENABLE ROW LEVEL SECURITY;` com política por `owner_id = current_setting('app.user_id')::uuid`, definindo `SET LOCAL app.user_id` por requisição. Mantém defesa em profundidade contra IDOR por bug de consulta
- **Prevenção de SQL injection:** apenas queries parametrizadas/Eloquent; proibido concatenar SQL; revisão de `DB::raw` no code review
- **Auditoria:** `audit_log` append-only, particionado por mês, retenção de 13 meses (ver LGPD)

## 4. Índices e desempenho

Índices-chave já estão no `schema.sql`. Diretrizes:

1. **Índices parciais** para filas e estados ativos (`jobs_status_queue_idx`), mantendo-os pequenos.
2. **Dedup de foto** por `(property_id, sha256)` evita upload duplicado.
3. **Evite índice em JSONB inteiro**; crie índice de expressão só para chaves consultadas (ex.: `(analysis->>'quality_score')::numeric`).
4. **Paginação por cursor** (`created_at, id`) em listagens; sem `OFFSET` grande.
5. **Observe**: `pg_stat_statements`, `auto_explain` (>200 ms), `pg_stat_user_indexes` para remover índices sem uso.
6. **Fila no Redis**, não no Postgres. A tabela `jobs` é registro de estado, não mecanismo de fila. `SELECT … FOR UPDATE SKIP LOCKED` só como contingência.
7. **N+1:** `with()` no Eloquent e teste que falha acima de N queries por endpoint.

### Orçamento de consultas (alvo)

| Operação | Alvo p95 |
|---|---|
| Listar imóveis do usuário | < 30 ms |
| Listar mídias de um imóvel (≤ 60) | < 40 ms |
| Consultar status de job | < 10 ms |
| Resolver share link | < 15 ms |

## 5. Particionamento e retenção

| Tabela | Estratégia | Retenção |
|---|---|---|
| `audit_log` | Partição mensal (`pg_partman`) | 13 meses online; depois arquivo frio |
| `jobs` | Sem partição até ~50 M linhas; depois por `queued_at` mensal | 24 meses de detalhe; agregados depois |
| `billing_events` | Sem partição | 5 anos (fiscal) |
| `media_assets` rejeitados | — | Purga em 30 dias (objeto + linha) |
| `device_sessions` expiradas | — | Purga diária após 30 dias de expiradas |
| `share_links` expirados | — | Mantém 90 dias para suporte; depois purga |
| Objetos órfãos no storage | Job de reconciliação semanal | `pending` > 24 h removido |

## 6. Backup, DR e continuidade

| Item | Meta |
|---|---|
| RPO | ≤ 5 min (PITR com WAL) |
| RTO | ≤ 1 h na Fase 1; ≤ 30 min depois |
| Backup completo | Diário, retenção 14 dias; mensal retenção 12 meses |
| Cópia fora da região | Sim (criptografada, chave separada) |
| **Teste de restauração** | Mensal, automatizado, com checagem de contagens e integridade; registrar evidência |
| Object storage | Versionamento + bloqueio de exclusão por 7 dias para pastas de saída; ciclo de vida para derivados |
| Runbook | Procedimento de failover, promoção de réplica e rollback de migração documentado |

## 7. Migrações

- Via migrations do Laravel, **aditivas** e retrocompatíveis (expand → migrate → contract)
- Proibido em horário de pico: `ALTER TABLE` com lock longo. Use `CREATE INDEX CONCURRENTLY`, `ADD COLUMN` nullable e preenchimento em lotes
- Toda migration precisa de `down()` testado ou plano de rollback explícito
- Revisão do DBA para qualquer mudança em tabelas > 1 M linhas
- Ferramentas de checagem no CI: `squawk` (lint de migração Postgres) e `sqlfluff`

## 8. Qualidade e integridade

- `CHECK` para domínios fechados (status, kind, tamanhos) e `FOREIGN KEY` em todas as relações
- `UNIQUE (owner_id, idempotency_key)` em jobs
- Ledger de créditos **imutável**: correção por lançamento compensatório, nunca `UPDATE`/`DELETE`
- Reconciliação diária: saldo do ledger × consumo de jobs × cobrança; alerta em divergência
- Testes de dados: constraints violadas devem falhar (testes de integração Pest com Postgres real em CI)

## 9. Monitoramento e alertas

| Sinal | Alerta |
|---|---|
| Conexões > 80% do limite | Aviso |
| Replication lag > 30 s | Crítico |
| Disco > 80% | Aviso; > 90% crítico |
| Queries > 1 s (p99) | Aviso |
| Deadlocks | Crítico se > 0 em 5 min |
| Tabela `jobs` com `queued` > 10 min | Crítico (fila parada) |
| Falha de backup/restauração | Crítico |
| Crescimento anormal de `audit_log` | Aviso (possível abuso) |

## 10. LGPD no banco

- **Mapeamento de dados pessoais:** `users` (e-mail, nome), `properties` (endereço), `device_sessions` (IP hash/UA), `audit_log`, mídia (fotos podem conter pessoas)
- **Exportação:** consulta consolidada por `user_id` gerando JSON + links temporários dos arquivos
- **Exclusão:** pipeline `purge_user` remove/anonimiza em ordem de dependência; mantém só dados exigidos por lei (ex.: registros fiscais) sem identificação direta quando possível
- **Backups:** exclusão efetiva ocorre na expiração do ciclo de retenção dos backups; documentar no aviso de privacidade
- **Minimização:** não coletar CPF/documentos na Fase 1; na Fase 3, KYC por provedor especializado, sem guardar documentos no banco

## 11. Checklist de entrada em produção

- [ ] TLS `verify-full`, VPC privada, sem IP público
- [ ] Papéis separados e testados (negar acesso indevido)
- [ ] KMS e rotação de chaves configurados
- [ ] PITR ativo + restauração testada
- [ ] `pg_stat_statements` e alertas ativos
- [ ] Migrations rodando via CI com `squawk`
- [ ] Rotina de purga e reconciliação agendadas
- [ ] Runbooks revisados
