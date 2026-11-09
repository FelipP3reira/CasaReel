# ADRs — Registros de Decisão de Arquitetura

Formato: contexto → decisão → alternativas → consequências. Status: **Aceita** (proposta inicial, revisar após validação).

## ADR-001 — App nativo Swift/SwiftUI primeiro
- **Contexto:** a Fase 1 depende de AVFoundation; a Fase 2 depende de ARKit; StoreKit 2 e App Attest são nativos.
- **Decisão:** Swift 6 + SwiftUI, módulos SPM. Android depois em Kotlin/Compose, reaproveitando contratos de API e o JSON de templates.
- **Alternativas:** Flutter/React Native (código único, mas módulos nativos de vídeo/AR acabam em Swift de qualquer forma).
- **Consequências:** público inicial só iOS; mitigar com fluxo web de upload e port planejado.

## ADR-002 — Render de vídeo no aparelho na Fase 1
- **Decisão:** AVFoundation (`AVMutableComposition`, `AVVideoComposition`, Core Image/Metal). Servidor só para premium.
- **Consequências:** custo de servidor ~0; resultado depende do aparelho; template JSON versionado garante equivalência com o worker.

## ADR-003 — Tour 3D sem exigir LiDAR
- **Contexto:** o iPhone 15 de teste não tem LiDAR; a maioria dos usuários também não terá.
- **Decisão:** captura por ARKit (frames + poses + intrínsecos) e reconstrução em servidor por Gaussian Splatting; fallback em tour 360 por panoramas.
- **Alternativas:** RoomPlan/LiDAR apenas (exclui a maioria dos aparelhos); fotogrametria on-device (RAM/energia); gerar 3D a partir de fotos de anúncio (qualidade insuficiente).
- **Consequências:** custo de GPU por tour; precisa de captura guiada e checagem de qualidade; LiDAR vira melhoria opcional.

## ADR-004 — Laravel + PostgreSQL + Redis, workers Python
- **Decisão:** API Laravel (domínio do time); workers Python por causa do ecossistema de visão/ML; comunicação via fila Redis com contrato de job em JSON.
- **Consequências:** duas linguagens; contrato de job bem definido e versionado; testes de contrato.

## ADR-005 — Uploads diretos ao storage com URL pré-assinada
- **Decisão:** nenhum arquivo de usuário passa pelo PHP. URL com expiração curta, limite de tamanho, tipo e checksum.
- **Consequências:** menos carga e superfície no backend; exige pipeline de sanitização pós-upload.

## ADR-006 — Identidade: Sign in with Apple + e-mail com MFA opcional
- **Decisão:** Sign in com Apple (obrigatório quando há login social) e e-mail/senha com Argon2id; tokens curtos com refresh rotativo e detecção de reuso.
- **Consequências:** processo de exclusão de conta obrigatório (regra da App Store); revogação de token Apple ao excluir.

## ADR-007 — Assinaturas por StoreKit 2 com validação server-side
- **Decisão:** `appAccountToken` vincula transação ao usuário; servidor valida JWS e consome Notifications V2.
- **Consequências:** nunca confiar no estado do cliente para liberar recurso pago.

## ADR-008 — Fidelidade do conteúdo (IA não inventa o imóvel)
- **Decisão:** templates determinísticos por padrão; recursos generativos só com rótulo, desligados por padrão e nunca para criar cômodos, móveis ou vistas que não existam.
- **Consequências:** protege usuários e a marca; limita alguns efeitos "wow".

## ADR-009 — Custo como requisito de primeira classe
- **Decisão:** cada job grava custo estimado e real; limites diários por usuário e global; alerta de orçamento.
- **Consequências:** instrumentação desde a Fase 1.

## ADR-010 — Modelo de dados único para três fases
- **Decisão:** `property → media_assets → jobs → outputs`, com `listings` adicionados na Fase 3 sem alterar o core.
- **Consequências:** migrações aditivas; tabelas de job genéricas com `type` e `payload` JSONB validado por schema.

## ADR-011 — Observabilidade sem PII
- **Decisão:** logs estruturados com IDs opacos; nunca registrar endereço, e-mail, tokens ou URLs assinadas.
- **Consequências:** depuração por correlação de IDs; redactors obrigatórios no logger.
