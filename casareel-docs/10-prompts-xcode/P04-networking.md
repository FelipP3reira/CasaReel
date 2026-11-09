# P04 — Camada de rede

```
Leia CLAUDE.md e docs/06-api/openapi.yaml.

Implemente o pacote Networking e os modelos da API em Domain.

1) Modelos
- Gere/escreva tipos Codable para os schemas do OpenAPI usados na Fase 1 (User, TokenPair, Property*, MediaAsset, UploadIntent*, Job*, Output, Entitlements, Problem, ConsentUpdate...). Datas ISO 8601. Decoding estrito (falha com campo obrigatório ausente), tolerante a campos novos desconhecidos.

2) APIClient
- Protocolo APIClient em Domain; implementação em Networking com URLSession (configuração efêmera, sem cache de respostas autenticadas, timeouts explícitos, waitsForConnectivity quando apropriado).
- Endpoints tipados (enum ou structs) por recurso; construção segura de URL (sem concatenar strings com entrada do usuário).
- Interceptores: Authorization (via TokenManager), Idempotency-Key (UUID por operação de criação), App Attest (quando a rota marcar requiresAttest), X-Device-Risk, Accept-Language, User-Agent com versão do app.
- Mapeamento de erros: problem+json -> AppError (com code estável, ex.: session_revoked, payment_required, rate_limited).
- Retry com backoff exponencial e jitter apenas para erros transitórios e métodos idempotentes; respeitar Retry-After em 429.
- 401: tentar refresh uma vez; se falhar, sinalizar sessão revogada.
- Limite máximo de tamanho de resposta e validação de Content-Type.
- Use o PinningDelegate do módulo Security.
- Nunca logar corpo de requisição/resposta nem cabeçalhos sensíveis.

3) Testes
- URLProtocol mock: sucesso, 401->refresh->sucesso, 401->refresh falha, 429 com Retry-After, 5xx com retry, problem+json, resposta gigante, content-type inesperado.
- Teste de que Idempotency-Key é reutilizada em retry da mesma operação.

Critérios de aceite:
- Nenhum acesso à rede fora do APIClient.
- Cobertura >= 80% em Networking.
- Sem warnings; concurrency strict ok.
- Documente em Packages/Networking/README.md como adicionar um endpoint.
```
