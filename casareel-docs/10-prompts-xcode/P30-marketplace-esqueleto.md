# P30 — Esqueleto do marketplace (Fase 3)

> **Não implemente antes** de Gate 1 e Gate 2 aprovados. Este prompt só prepara o terreno sem expor funcionalidades.

```
Leia CLAUDE.md, docs/01-produto/PRD.md (Fase 3) e docs/03-dados/schema.sql (listings, inquiries, reports).

Objetivo: preparar o app para a Fase 3 sem lançar nenhuma funcionalidade pública.

Tarefas:
1. Crie os módulos vazios FeatureMarketplace, FeatureSearch e FeatureInbox com Package.swift, protocolos em Domain (ListingRepository, SearchService, InquiryService) e modelos Codable alinhados ao schema (Listing, Inquiry, Report). Tudo atrás de feature flag remota assinada `marketplace_enabled` (desligada).
2. Documente em docs/fase3-marketplace.md: fluxos (publicar, buscar, contatar, reportar), requisitos de confiança e segurança (verificação do anunciante, antifraude de anúncio, moderação, denúncia/bloqueio de usuário exigidos pela App Store para conteúdo gerado por usuário), pagamentos via gateway (sem tocar dados de cartão no app) e lista de decisões em aberto.
3. Estenda o Router com rotas reservadas (listing, search, inbox) inacessíveis enquanto a flag estiver desligada.
4. Teste que, com a flag desligada, nenhuma tela/rota do marketplace é alcançável (incluindo deep links).

Critérios de aceite:
- Nenhuma mudança visível ao usuário final.
- Build verde; testes verdes.
- Documento de decisões em aberto revisado.
```
