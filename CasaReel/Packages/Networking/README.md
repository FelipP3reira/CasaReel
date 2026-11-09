# Networking

Cliente HTTP tipado da API do CasaReel. É o **único** ponto do app que fala com a API; os modelos, os endpoints (`API`) e o protocolo `APIClient` ficam no `Domain`.

## O que o `URLSessionAPIClient` faz em toda requisição

| Item | Comportamento |
|---|---|
| Sessão | `URLSessionConfiguration.casaReelAPI`: efêmera, sem cache nem cookies, timeouts de 30 s/90 s, TLS 1.2+ |
| Pinning | `PinningDelegate` do `SecurityKit` com a `PinningPolicy` do app |
| Cabeçalhos | `Authorization` (via `TokenManager`), `Idempotency-Key` (criações), `X-App-Attest-Assertion` ou `X-App-Attest-Status` (rotas sensíveis), `X-Device-Risk`, `Accept-Language`, `User-Agent` |
| 401 | Uma renovação de token por chamada e nova tentativa; se a renovação falhar, `AppError(.sessionRevoked)` e o app volta ao login |
| Novas tentativas | Só para erros transitórios (429, 500/502/503/504, sem conexão, timeout) **e** requisições repetíveis (GET/PUT/DELETE ou POST com `Idempotency-Key`). Backoff exponencial com jitter (até 3 tentativas); `Retry-After` tem prioridade |
| Limites | Corpo acima de 5 MB é abortado durante o download; `Content-Type` precisa ser JSON |
| Erros | `problem+json` vira `AppError` com `code` estável (`session_revoked`, `payment_required`, `rate_limited`…); códigos desconhecidos ficam em `problemCode` |
| Logs | Só nome do endpoint, código e status, via `SecureLogger`. Nunca corpo nem cabeçalhos |
| Decodificação | Estrita para campos obrigatórios, tolerante a campos novos; enums de status viram `.unknown` para valores novos; datas ISO 8601 com ou sem frações de segundo |

## Como adicionar um endpoint

1. **Modelos** — em `Domain/API/Models.swift`, crie os tipos do schema do `openapi.yaml`: `Decodable` para respostas, `Encodable` para corpos. Campo obrigatório no contrato = propriedade não opcional; `null` permitido = opcional. Para enums de status use `ForwardCompatibleEnum` com um caso `unknown`.
2. **Endpoint** — em `Domain/API/API.swift`, adicione uma função estática:

   ```swift
   public static func archiveProperty(_ id: UUID) -> Endpoint<Property> {
       Endpoint(
           name: "properties.archive",          // aparece nos logs; nunca coloque dados do usuário aqui
           method: .post,
           path: ["properties", .id(id), "archive"],   // só literais, UUIDs ou TemplateSlug
           body: nil,
           requiresAuth: true,                  // padrão
           requiresAttest: false,               // true para rotas sensíveis (pagamento, exclusão…)
           idempotent: true                     // true para criações: gera Idempotency-Key e permite retry
       )
   }
   ```

   Texto livre nunca entra no caminho: vai no corpo JSON ou em `URLQueryItem` (o cliente codifica).
   Respostas `202`/`204` sem corpo usam `EmptyResponse`.
3. **Uso** — `try await environment.apiClient.send(API.archiveProperty(id))`. Trate `AppError` pelo `code` e mostre mensagens genéricas ao usuário.
4. **Teste** — em `Tests/NetworkingTests`, registre as respostas num `MockURLProtocol.Server` e verifique caminho, método, corpo e cabeçalhos da requisição gravada.

## Pendência no contrato da API

`/auth/apple` exige asserção App Attest, mas no `openapi.yaml` `/attest/register` exige sessão, então o primeiro login nunca teria uma chave registrada. O cliente envia `/attest/register` **sem** sessão (`API.attestRegister`); o backend precisa aceitar isso (o desafio de uso único e a validação da atestação protegem a rota) ou o contrato precisa mudar.

## Testes

```sh
cd Packages/Networking
xcodebuild test -scheme Networking -destination 'platform=iOS Simulator,name=iPhone 17e' -enableCodeCoverage YES
```
