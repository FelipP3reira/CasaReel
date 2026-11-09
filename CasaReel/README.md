# CasaReel — app iOS

Documentação do produto e da arquitetura: [`../casareel-docs`](../casareel-docs/README.md).

## Requisitos

- Xcode 27 (Swift 6), iOS 17.0+ (apenas iPhone)
- Nenhuma dependência de terceiros

## Estrutura

| Pasta | Conteúdo |
|---|---|
| `App/` | Target do app: composição de dependências (`AppEnvironment`), rotas e recursos |
| `Config/` | `.xcconfig` por ambiente e `Info.plist` (sem segredos) |
| `Packages/` | Pacotes SPM locais: `DesignSystem`, `Domain`, infra (`SecurityKit`, `Networking`, `MediaKit`, `VideoEngine`, `Persistence`) e `Feature*` |
| `scripts/` | Automação de build e testes |

Regras de dependência: `Feature*` dependem só de `Domain` e `DesignSystem`; a infra implementa os protocolos do `Domain`; só o `App` conhece os tipos concretos.

> O módulo de segurança se chama `SecurityKit` porque `Security` colide com o framework da Apple.

## Ambientes

| Configuração | Scheme | Bundle ID | API |
|---|---|---|---|
| Debug | `CasaReel` (Run) | `br.com.casareel.app.debug` | staging |
| Staging | `CasaReel-Staging` | `br.com.casareel.app.staging` | staging |
| Release | `CasaReel` (Archive) | `br.com.casareel.app` | produção |

Os valores ficam em `Config/*.xcconfig`, são expostos pelo `Info.plist` e lidos pelo tipo `AppConfiguration` (só aceita HTTPS).

## Build e testes

```sh
# App no simulador
xcodebuild build -project CasaReel.xcodeproj -scheme CasaReel \
  -destination 'platform=iOS Simulator,name=iPhone 17e'

# Testes de todos os pacotes, cada um isolado (falha se um módulo importar algo que não declarou)
./scripts/test-packages.sh
```

Para rodar no iPhone, selecione seu time em *Signing & Capabilities* do target `CasaReel`.
