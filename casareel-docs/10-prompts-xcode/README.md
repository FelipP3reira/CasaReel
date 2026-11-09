# Prompts para o Xcode (Claude Agent)

Como usar:

1. **Uma vez:** copie `00-contexto-global.md` para um arquivo `CLAUDE.md` na raiz do projeto Xcode (o agente lê o contexto em toda sessão) ou cole no início da primeira conversa. Coloque também a pasta `casareel-docs/` dentro do repositório (ex.: `docs/`) para o agente consultar `openapi.yaml`, `arquitetura-ios.md` e `threat-model.md`.
2. **Em ordem:** rode os prompts `P01`, `P02`… um por vez. Cada prompt termina com critérios de aceite. Só avance quando o build estiver verde, os testes passarem e você tiver revisado o diff.
3. **Commits pequenos:** peça (ou faça) um commit por prompt. Revise todo código de segurança manualmente.
4. **Teste em aparelho físico** (iPhone 15). Previews do SwiftUI consomem muita RAM no seu Mac de 8 GB; prefira rodar no aparelho.
5. **Se o agente desviar** do contexto (ex.: adicionar biblioteca de terceiros sem pedir), responda: *"Reverta e siga as regras do CLAUDE.md."*

## Índice

### Fase 0 e 1 — Vídeo
| Prompt | Tema |
|---|---|
| P01 | Bootstrap do projeto, módulos SPM, configs por ambiente |
| P02 | Design System e shell de navegação |
| P03 | Módulo Security (Keychain, Pinning, App Attest, sinais de integridade, SecureLogger) |
| P04 | Camada de rede tipada e TokenManager |
| P05 | Autenticação (Sign in with Apple) |
| P06 | Imóveis (CRUD) e persistência local |
| P07 | Seleção de fotos, validação e sanitização (EXIF/GPS) |
| P08 | Upload seguro em background |
| P09 | Análise de fotos no aparelho (qualidade, ambiente, saliency, ordem) |
| P10 | VideoEngine: templates, composição e exportação |
| P11 | Editor/Pré-visualização do vídeo |
| P12 | Compartilhamento e links públicos |
| P13 | Assinaturas com StoreKit 2 |
| P14 | Privacidade/LGPD in-app (consentimentos, exportar, excluir conta) |
| P15 | Testes, acessibilidade e performance |
| P16 | Hardening e checklist de release (TestFlight) |

### Fase 2 — Tour 3D
| Prompt | Tema |
|---|---|
| P20 | ARCaptureKit: captura guiada sem LiDAR |
| P21 | Upload de captura e acompanhamento do job |
| P22 | Viewer do tour (WKWebView restrito) e compartilhamento |

### Fase 3
| Prompt | Tema |
|---|---|
| P30 | Esqueleto do marketplace (apenas planejamento e modelos) |

## Dica de uso com o agente
- Peça sempre: *"Antes de codar, liste os arquivos que vai criar/alterar e as decisões de segurança relevantes. Depois implemente."*
- Peça: *"Ao final, rode os testes e liste o que ficou pendente."*
- Para trabalho de backend (Laravel), use `../11-prompts-backend/`.
