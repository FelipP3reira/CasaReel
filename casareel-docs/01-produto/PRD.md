# PRD — Product Requirements Document

## 1. Problema

Plataformas de hospedagem permitem apenas fotos no anúncio. Anfitriões querem apresentar o imóvel em vídeo (redes sociais, site próprio, WhatsApp, reserva direta), mas editar vídeo é trabalhoso e a maioria não sabe fazê-lo.

## 2. Proposta de valor

Em poucos toques, o anfitrião transforma as fotos do próprio imóvel em um **vídeo profissional** (vertical e horizontal), depois em um **tour 3D navegável** e, no futuro, publica o imóvel num **marketplace** próprio.

> **Ponto crítico de validação:** o vídeo não entra no anúncio da plataforma de origem. O valor está em *outros canais* (Instagram/TikTok, site/landing próprios, WhatsApp, reserva direta, anúncios pagos). O produto deve ser posicionado como **ferramenta de marketing do anfitrião**, não como complemento do anúncio.

## 3. Personas

| Persona | Descrição | Necessidade |
|---|---|---|
| **Anfitrião individual** | 1–3 imóveis, usa só o celular | Vídeo rápido, sem editar |
| **Gestor de temporada** | 5–50 imóveis, equipe pequena | Padronização, marca própria, lote |
| **Visitante / hóspede** | Recebe link do vídeo/tour | Ver o imóvel com fidelidade, sem instalar nada |
| **Admin da plataforma** | Time interno | Moderação, suporte, antifraude, custos |

## 4. Escopo por fase

### Fase 1 — Vídeo (MVP)
- Cadastro/login (Sign in with Apple, e-mail com verificação)
- Cadastro de imóvel; seleção de 5–40 fotos da galeria
- Análise de fotos (qualidade, ambiente, ordem sugerida)
- Templates de vídeo (movimento de câmera, transições, trilha licenciada, textos, logo)
- Exportação 9:16 e 16:9; compartilhamento (share sheet, link público)
- Render **no aparelho** (AVFoundation); render no servidor como opção premium
- Assinatura (StoreKit 2) e créditos
- Exportar e excluir dados (LGPD)

### Fase 2 — Tour 3D navegável no navegador
- Captura guiada por ARKit **sem exigir LiDAR** (vídeo + poses de câmera)
- Reconstrução no servidor (Gaussian Splatting / fotogrametria) com GPU sob demanda
- Viewer web embutível (link e `<iframe>`), navegação por toque/mouse
- Fallback: tour 360 por panoramas e hotspots quando a reconstrução falhar na checagem de qualidade
- Para aparelhos com LiDAR: captura enriquecida (profundidade) como melhoria opcional

### Fase 3 — Marketplace
- Anúncios próprios, busca, favoritos, contato/reserva, pagamentos, avaliações, moderação, KYC leve do anunciante
- Tratado como produto à parte (confiança, pagamentos, disputas, regulação). Só iniciar com tração das Fases 1 e 2

## 5. Fora de escopo (por ora)

- Scraping ou integração não autorizada com plataformas de terceiros
- Geração de cômodos/móveis inexistentes por IA (ver política de fidelidade em `04-ia-ciencia-de-dados`)
- Chat entre usuários, pagamentos de reserva (Fase 3)

## 6. Princípios de produto

1. **Fidelidade:** o vídeo e o 3D não podem mostrar o que o imóvel não tem. Qualquer conteúdo sintético é rotulado.
2. **Privacidade por padrão:** metadados de localização das fotos são removidos; endereço exato nunca é público sem escolha do anfitrião.
3. **Custo previsível:** cada job tem custo medido e preço definido.
4. **Uma base, três fases:** o mesmo modelo de dados e fila atendem vídeo, 3D e marketplace.

## 7. Métricas de sucesso

| Métrica | Meta inicial (hipótese) |
|---|---|
| Tempo do upload ao vídeo exportado | < 3 min (render local) |
| Ativação (criou 1º vídeo em 24h após cadastro) | > 40% |
| Retenção D30 | > 20% |
| Conversão free → pago | > 4% |
| Custo de infraestrutura por vídeo (render local) | < R$ 0,10 |
| Custo por tour 3D | Medir; definir preço com margem ≥ 60% |
| Crash-free sessions | > 99,5% |

## 8. Monetização (hipótese a validar)

- **Free:** poucos vídeos/mês com marca d'água
- **Pro (assinatura):** vídeos ilimitados, sem marca, marca própria do anfitrião
- **Créditos avulsos:** tour 3D (custo de GPU), render de servidor
- **Gestor/Agência:** multi-imóvel, lote, equipe
- Assinaturas dentro do app passam pelo sistema de compras da Apple (comissão); considerar no preço

## 9. Riscos principais

| Risco | Impacto | Mitigação |
|---|---|---|
| Anfitrião não ter onde usar o vídeo | Alto | Entrevistas antes de construir; posicionar como marketing multi-canal |
| Termos da plataforma de origem | Médio | Upload manual do anfitrião; sem scraping |
| 3D com fotos esparsas fica ruim | Alto | Captura guiada dedicada; checagem automática de qualidade; fallback 360 |
| Custo de GPU | Alto | Jobs sob demanda, créditos, medição por job |
| Conteúdo enganoso / direitos de imagem | Alto | Rótulo de conteúdo sintético, declaração de titularidade, moderação |
| Vazamento de dados / endereço | Alto | Ver `05-seguranca` |
| Mercado Android maior no Brasil | Médio | Contratos de API neutros, fluxo web como ponte, port planejado |
