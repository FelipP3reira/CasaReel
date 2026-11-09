# P01 — Bootstrap do projeto

```
Leia CLAUDE.md e docs/07-app-ios/arquitetura-ios.md.

Crie o projeto iOS "CasaReel" (SwiftUI, Swift 6, iOS 17.0+, bundle id br.com.casareel.app, apenas iPhone).

Tarefas:
1. Estruture o repositório conforme a seção 4 de arquitetura-ios.md: target App + pacotes SPM locais em Packages/ (DesignSystem, Domain, Networking, Security, MediaKit, VideoEngine, Persistence, FeatureAuth, FeatureProperties, FeaturePhotos, FeatureVideo, FeatureBilling, FeaturePrivacy). Cada pacote com Package.swift, alvo de código e alvo de testes. Respeite as regras de dependência (Features -> Domain/DesignSystem; Domain define protocolos; Infra implementa).
2. Crie Config/Debug.xcconfig, Staging.xcconfig e Release.xcconfig com API_BASE_URL e demais valores por ambiente (sem segredos) e ligue-os aos schemes. Exponha os valores via Info.plist e um tipo AppConfiguration tipado.
3. Habilite Swift 6 strict concurrency em todos os pacotes.
4. Adicione String Catalog (Localizable.xcstrings) com pt-BR como idioma base e en.
5. Adicione PrivacyInfo.xcprivacy inicial (sem tracking; declare as APIs de "required reason" que o projeto já usa, se houver).
6. Configure Info.plist: ATS estrito (sem exceções), textos de permissão necessários apenas quando a funcionalidade existir (não adicionar ainda os que não usamos).
7. Adicione .gitignore para Xcode/SPM, SwiftLint (.swiftlint.yml com regras: force_unwrapping, force_try, force_cast como erro; sem print) e um README curto de build.
8. Crie AppEnvironment (composição de dependências) com protocolos vazios para os serviços principais, e uma tela inicial placeholder.
9. Crie o primeiro teste em cada pacote (pode ser trivial) e garanta que `xcodebuild test` passa em simulador.
10. Fixe versões de qualquer dependência externa (deve haver zero por enquanto) e versione Package.resolved.

Antes de codar, liste os arquivos que criará e quaisquer dúvidas.

Critérios de aceite:
- O projeto compila nos 3 schemes sem warnings.
- Nenhuma dependência de terceiros.
- Dependências entre pacotes respeitam as regras (falha o build se uma Feature importar outra Feature).
- Testes passam.
- Nenhum segredo no repositório.
```
