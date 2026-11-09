# CasaReel — Pacote de Documentação do Projeto

> **CasaReel** é um codinome de trabalho. Troque pelo nome definitivo (e verifique disponibilidade de marca no INPI e na App Store) antes de publicar.

App mobile (iOS primeiro, Android depois) que transforma as fotos de um imóvel em **vídeo de apresentação** (Fase 1), depois em **tour 3D navegável pelo navegador** (Fase 2) e, por fim, evolui para um **marketplace de anúncios de imóveis** (Fase 3).

## Premissas fixadas

| # | Premissa | Consequência |
|---|---|---|
| 1 | Desenvolvimento e testes em **iOS** (iPhone 15 de teste), Android depois | App nativo Swift/SwiftUI; contratos de API neutros de plataforma para o port Android |
| 2 | **iPhone 15 (não Pro) não tem LiDAR** | RoomPlan e captura LiDAR não podem ser a base da Fase 2. A captura 3D usa câmera + poses do ARKit (funciona sem LiDAR), com reconstrução no servidor. Ver `04-ia-ciencia-de-dados` |
| 3 | Ordem: vídeo → 3D → marketplace | Modelo de dados e filas já nascem preparados para as três fases (`property → media_assets → jobs → outputs`) |
| 4 | Backend em Laravel + PostgreSQL + Redis; workers Python | Alinhado ao stack do time |
| 5 | Segurança e privacidade (LGPD) desde o dia 1 | Threat model, controles, checklist MASVS e prompts já carregam requisitos de segurança |
| 6 | Mac com 8 GB RAM | Build leve, testar em aparelho físico, CI na nuvem para builds pesados |

## Ordem de leitura

1. `01-produto/` — PRD e requisitos
2. `02-arquitetura/` — visão geral, sequências, ADRs
3. `03-dados/` — modelo de dados, `schema.sql`, guia DBA
4. `04-ia-ciencia-de-dados/` — pipeline de IA, métricas, custo, governança de dados
5. `05-seguranca/` — threat model, controles, MASVS, LGPD
6. `06-api/` — `openapi.yaml`
7. `07-app-ios/` — arquitetura do app Swift
8. `08-qualidade-devops/` — testes, CI/CD, observabilidade
9. `09-roadmap/` — fases, custos, riscos
10. `10-prompts-xcode/` — prompts sequenciais para o agente do Xcode
11. `11-prompts-backend/` — prompts equivalentes para o backend Laravel (Claude Code)

## Mapa de papéis (quem "assina" cada documento)

| Papel | Documentos principais |
|---|---|
| Engenharia de software / arquitetura | 02, 06, 07, 08 |
| DBA sênior | 03 |
| Cientista de dados / ML | 04 |
| Segurança (AppSec) | 05 e seções de segurança dos demais |
| Produto | 01, 09 |

## Diagramas

Todos os diagramas estão em **Mermaid** dentro dos `.md`. Renderizam direto no GitHub, GitLab, VS Code (extensão Markdown Preview Mermaid) e Obsidian.

## Antes de escrever código — decisões que dependem de você

1. **Confirmar demanda** com 10–15 anfitriões (onde usariam o vídeo, quanto pagariam). Ver `09-roadmap`.
2. **Termos de uso da plataforma de hospedagem** que os anfitriões usam: o app não deve depender de scraping nem violar termos; o anfitrião sobe as próprias fotos.
3. **Nome/marca**, **conta Apple Developer** (US$ 99/ano), **domínio** e **provedor de nuvem**.
4. **Revisão jurídica** da política de privacidade e dos termos (LGPD) antes do lançamento.

## Pasta `diagramas/`

Versões em SVG de todos os diagramas Mermaid dos documentos (numeradas na ordem de leitura; o nome indica o documento de origem). Úteis para apresentações; a fonte editável continua nos `.md`.
