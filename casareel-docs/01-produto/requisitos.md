# Requisitos

Legenda de prioridade: **M** = Must, **S** = Should, **C** = Could.

## Requisitos funcionais

### Conta e identidade
| ID | Requisito | Fase | Pri |
|---|---|---|---|
| RF-001 | Login com Sign in with Apple | 1 | M |
| RF-002 | Login com e-mail + senha com verificação de e-mail e MFA opcional (TOTP) | 1 | S |
| RF-003 | Sessão com access token curto e refresh token rotativo | 1 | M |
| RF-004 | Encerrar sessão em todos os dispositivos | 1 | S |
| RF-005 | Exportar todos os meus dados (LGPD) | 1 | M |
| RF-006 | Excluir conta e dados, com período de carência de 7 dias | 1 | M |

### Imóveis e mídia
| ID | Requisito | Fase | Pri |
|---|---|---|---|
| RF-010 | CRUD de imóvel (título, descrição, endereço privado, cidade pública) | 1 | M |
| RF-011 | Selecionar fotos da galeria (PHPicker, sem permissão total da biblioteca) | 1 | M |
| RF-012 | Validar fotos: formato, resolução mínima, tamanho, hash, duplicatas | 1 | M |
| RF-013 | Remover metadados EXIF/GPS antes do upload | 1 | M |
| RF-014 | Upload seguro e retomável (URL pré-assinada, background session) | 1 | M |
| RF-015 | Análise automática: qualidade, ambiente (sala, quarto…), ordem sugerida | 1 | S |
| RF-016 | Ocultar rostos/placas/documentos visíveis (borrar) opcional | 1 | C |

### Vídeo (Fase 1)
| ID | Requisito | Fase | Pri |
|---|---|---|---|
| RF-020 | Catálogo de templates (movimento, transição, duração, estilo) | 1 | M |
| RF-021 | Render local 9:16 e 16:9, 1080p, H.264/HEVC | 1 | M |
| RF-022 | Trilhas musicais licenciadas, volume, sem música | 1 | M |
| RF-023 | Textos/legendas por cômodo, logo/marca do anfitrião | 1 | S |
| RF-024 | Pré-visualização antes do render final | 1 | M |
| RF-025 | Render no servidor (premium) com fila e status | 1 | C |
| RF-026 | Link público com expiração/revogação e página de reprodução | 1 | M |
| RF-027 | Marca d'água no plano gratuito | 1 | M |

### Assinatura
| ID | Requisito | Fase | Pri |
|---|---|---|---|
| RF-030 | Assinatura e créditos via StoreKit 2 | 1 | M |
| RF-031 | Validação server-side (App Store Server API + Notifications V2) | 1 | M |
| RF-032 | Restaurar compras | 1 | M |

### Tour 3D (Fase 2)
| ID | Requisito | Fase | Pri |
|---|---|---|---|
| RF-040 | Captura guiada ARKit: cobertura por cômodo, feedback de movimento/luz/foco | 2 | M |
| RF-041 | Upload de frames + poses + intrínsecos da câmera | 2 | M |
| RF-042 | Checagem de qualidade pré-reconstrução (cobertura, blur, sobreposição) | 2 | M |
| RF-043 | Reconstrução 3D em GPU sob demanda com status e estimativa de tempo | 2 | M |
| RF-044 | Viewer web (navegação por toque/mouse/teclado), embutível | 2 | M |
| RF-045 | Fallback para tour 360 com hotspots | 2 | S |
| RF-046 | Edição do tour (cortar, recorte de área, ponto inicial, tags por cômodo) | 2 | S |
| RF-047 | Captura aprimorada com LiDAR quando disponível | 2 | C |

### Marketplace (Fase 3)
| ID | Requisito | Fase | Pri |
|---|---|---|---|
| RF-050 | Publicar anúncio com vídeo e tour | 3 | M |
| RF-051 | Busca com filtros e mapa; favoritos | 3 | M |
| RF-052 | Contato/solicitação de visita/reserva | 3 | M |
| RF-053 | Pagamentos e repasse | 3 | M |
| RF-054 | Moderação, denúncias, verificação do anunciante | 3 | M |
| RF-055 | Avaliações verificadas | 3 | S |

## Requisitos não funcionais

| ID | Categoria | Requisito |
|---|---|---|
| RNF-001 | Desempenho | Render local de vídeo de 30 s em ≤ 2 min num iPhone 15 |
| RNF-002 | Desempenho | API p95 < 300 ms para leituras; upload suporta arquivos de até 25 MB por foto |
| RNF-003 | Disponibilidade | API 99,5% (Fase 1); processamento assíncrono tolera falha de worker (retry idempotente) |
| RNF-004 | Escalabilidade | Workers escalam horizontalmente por fila; GPU sob demanda |
| RNF-005 | Segurança | Atender OWASP MASVS L1 + partes de L2 (armazenamento, rede, resiliência) e OWASP ASVS L2 no backend |
| RNF-006 | Privacidade | Conformidade LGPD: minimização, finalidade, retenção, direitos do titular |
| RNF-007 | Acessibilidade | VoiceOver, Dynamic Type, contraste AA |
| RNF-008 | Localização | pt-BR primeiro; strings externalizadas para en e es |
| RNF-009 | Observabilidade | Logs estruturados sem PII, métricas, tracing, alertas de custo |
| RNF-010 | Portabilidade | API versionada e neutra para app Android; viewer 3D em web |
| RNF-011 | Compatibilidade | iOS 17+ (cobre iPhone 15 de teste); revisar após medir base de usuários |
| RNF-012 | Custo | Custo por job medido e exposto em dashboard |
| RNF-013 | Manutenibilidade | Cobertura de testes ≥ 70% em lógica de domínio; CI obrigatório para merge |
| RNF-014 | Conteúdo | Rotular conteúdo sintético; não gerar elementos inexistentes no imóvel por padrão |
