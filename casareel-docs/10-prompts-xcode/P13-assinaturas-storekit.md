# P13 — Assinaturas com StoreKit 2

```
Leia CLAUDE.md, docs/02-arquitetura/fluxos-sequencia.md (fluxo 7) e docs/06-api/openapi.yaml (/billing/apple/transactions, /me/entitlements).

Implemente FeatureBilling.

Produtos (IDs em AppConfiguration; criar também um arquivo Products.storekit para testes locais):
- Assinatura "Pro" mensal e anual (grupo de assinaturas único)
- Pacotes de créditos consumíveis (3 tamanhos) para recursos pagos por uso

Funcionalidades:
1. Carregar produtos (Product.products(for:)) e exibir paywall claro: preço localizado, período, renovação automática, como cancelar, links de Termos e Privacidade, botão "Restaurar compras". Não esconder informações obrigatórias.
2. Compra com `product.purchase(options: [.appAccountToken(uuid)])` onde uuid = id do usuário no servidor (parse do UUID do backend). Tratar resultados: success (verificar), pending, userCancelled.
3. Verificação: aceitar apenas transações .verified; enviar o JWS (signedTransaction) a POST /billing/apple/transactions; só chamar transaction.finish() depois que o servidor confirmar.
4. Observar Transaction.updates em um Task de vida longa iniciado no launch (renovações, reembolsos, compras de outro dispositivo) e sincronizar com o servidor.
5. Restaurar compras: AppStore.sync() e reenviar transações atuais ao servidor.
6. Entitlements: a fonte da verdade é GET /me/entitlements; o app NUNCA libera recurso pago apenas com o estado local do StoreKit. Cachear entitlements com validade curta.
7. Gerenciar assinatura: link para `showManageSubscriptions` e mostrar status (ativa, em carência, expirada).
8. Créditos: exibir saldo (do servidor); consumo ocorre no servidor ao criar o job.

Segurança:
- Não confiar em flags locais; não armazenar nada sensível; JWS nunca em log.
- Tratar falha de rede ao enviar a transação: manter na fila e reenviar (idempotente no servidor).

Testes:
- Com StoreKitTest (SKTestSession): compra, cancelamento, pendente, renovação, reembolso, restauração, reenvio após falha.
- ViewModel do paywall com entitlements mockados.
- Teste garantindo que recurso premium continua bloqueado quando o servidor diz "free", mesmo com StoreKit local ativo.

Critérios de aceite:
- Fluxo de compra e restauração funcionando em Sandbox no aparelho.
- Paywall em conformidade com as diretrizes da App Store (preço, período, renovação, cancelamento).
- Sem warnings; testes verdes.
```
