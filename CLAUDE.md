# CLAUDE.md — Contexto global do projeto CasaReel (iOS)

> Gerado a partir de `casareel-docs/10-prompts-xcode/00-contexto-global.md`. O projeto Xcode fica em `CasaReel/`.

## Produto
CasaReel é um app iOS (depois Android) para anfitriões de hospedagem. Fase 1: transforma as fotos do imóvel em vídeo de apresentação (render no aparelho). Fase 2: tour 3D navegável no navegador, capturado com ARKit **sem exigir LiDAR** (o aparelho de teste é um iPhone 15 comum). Fase 3: marketplace. Código e contratos devem ser organizados para as três fases.

## Documentos de referência (pasta `casareel-docs/`)
- `06-api/openapi.yaml` — contrato da API (fonte da verdade para modelos e endpoints)
- `07-app-ios/arquitetura-ios.md` — módulos, padrões, estrutura de pastas
- `05-seguranca/` — threat model, controles, MASVS, LGPD
- `04-ia-ciencia-de-dados/` — formato do template JSON e pipeline
- Leia o documento relevante **antes** de implementar cada tarefa.

## Stack e padrões
- Swift 6 (strict concurrency), SwiftUI, iOS 17+, Observation (`@Observable`), `async/await`, `actor` para estado compartilhado
- MVVM; módulos SPM locais em `Packages/`; `Features` não dependem entre si; `Domain` define protocolos, `Infra` implementa
- Persistência: SwiftData (rascunhos, fila de upload, cache); segredos somente no Keychain
- Rede: `URLSession` + `Codable` estrito; erros mapeados do formato `application/problem+json`
- Localização: String Catalog (pt-BR padrão); sem texto fixo em Views
- Acessibilidade: Dynamic Type, labels do VoiceOver, contraste, respeitar "Reduzir Movimento"
- Logs com `os.Logger`; nada de `print`

## Regras de segurança (inegociáveis)
1. Nunca colocar segredos, chaves privadas, tokens ou URLs assinadas no código, em logs, em `UserDefaults` ou em arquivos. Tokens só no Keychain (`ThisDeviceOnly`).
2. ATS sem exceções. Nenhum `NSAllowsArbitraryLoads`. Nunca desativar validação de certificado, nem em debug.
3. Pinning de chave pública (SPKI) com pin de backup; sem quebrar o app por rotação (kill switch assinado).
4. Todo arquivo do usuário é hostil: validar tipo, tamanho, dimensões; remover EXIF/GPS antes de enviar.
5. Nunca confiar no cliente para liberar recursos pagos: o servidor decide (entitlements).
6. Nada de `fatalError`, `try!` ou force-unwrap em caminhos com dados externos.
7. Sem SDKs de analytics/ads/terceiros sem aprovação explícita. Preferir APIs da Apple.
8. Dados sensíveis fora de screenshots do app switcher e fora do backup.
9. Mensagens de erro ao usuário genéricas; detalhes técnicos só em log privado.
10. Universal Links (não esquemas custom) e validação de parâmetros; nenhuma ação sensível disparada só por link.

## Regras de privacidade
- Minimizar coleta; `PhotosPicker`/`PHPicker` (sem acesso total à biblioteca)
- Consentimentos granulares e revogáveis; telemetria opt-in e sem PII
- Manter `PrivacyInfo.xcprivacy` atualizado a cada API/uso novo

## Qualidade
- Cada tarefa entrega: código + testes (Swift Testing/XCTest) + atualização de docs quando mudar contrato
- Não adicionar dependências sem perguntar; se necessário, justificar e fixar versão
- Funções pequenas, nomes claros, sem código morto, sem comentários óbvios
- Build deve passar sem warnings novos; rodar SwiftLint se configurado
- Se a especificação for ambígua, **perguntar antes** de assumir
- Mac de desenvolvimento tem 8 GB de RAM: evitar Previews pesados; priorizar testes unitários rápidos

## Formato de trabalho esperado
1. Resumir o entendimento em 3–5 linhas
2. Listar arquivos a criar/alterar e decisões de segurança
3. Implementar em passos pequenos
4. Rodar build e testes; reportar resultado e pendências
5. Sugerir a mensagem de commit

## Convenções
- Bundle ID: `br.com.casareel.app` (placeholder)
- Nomes de módulos: `DesignSystem`, `Domain`, `Networking`, `SecurityKit`, `MediaKit`, `VideoEngine`, `Persistence`, `Feature*`, `ARCaptureKit` (`SecurityKit`, não `Security`: o nome colide com o framework da Apple)
- Ambientes: `Debug` (local/staging), `Staging`, `Release` via `.xcconfig`
- URLs base por ambiente em `Config/*.xcconfig` (sem segredos)
