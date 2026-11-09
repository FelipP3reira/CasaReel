# P05 — Autenticação (Sign in with Apple)

```
Leia CLAUDE.md, docs/02-arquitetura/fluxos-sequencia.md (fluxos 1 e 2) e docs/06-api/openapi.yaml (/auth/*).

Implemente FeatureAuth + casos de uso em Domain.

Fluxo:
1. Tela de boas-vindas com botão "Continuar com Apple" (SignInWithAppleButton), link para Termos e Política de Privacidade (URLs em AppConfiguration) e aceite explícito dos termos antes do login (registrar consentimento via PUT /me/consents após autenticar).
2. Gerar nonce criptograficamente seguro (SecRandomCopyBytes), enviar SHA-256 ao pedido da Apple e o nonce original ao servidor.
3. POST /auth/apple com identityToken, nonce e deviceId (UUID gerado no primeiro uso e guardado no Keychain; não usar IDFA/IDFV como identidade).
4. Antes do login, garantir attest registrado (AppAttestClient); se não houver suporte, seguir com marca de risco.
5. Guardar TokenPair via TokenManager. Atualizar estado global de sessão.
6. Observar credential state da Apple (ASAuthorizationAppleIDProvider.getCredentialState) ao abrir o app; se revogado, encerrar sessão local.
7. Logout: POST /auth/logout, apagar Keychain e caches locais (SwiftData de rascunhos do usuário, arquivos temporários).
8. Tratar session_revoked globalmente: voltar ao fluxo de login com mensagem neutra.

Segurança:
- Nenhum dado do token em logs. Nenhum fallback silencioso que permita pular autenticação.
- Reautenticação (Face ID/Touch ID via LAContext) exposta como serviço para ações sensíveis (usado em P14).
- Erros de login genéricos; sem revelar se a conta existe.

Testes:
- ViewModel com APIClient mockado: sucesso, falha da Apple (cancelamento), falha do servidor, 429.
- Teste de que o nonce enviado ao servidor corresponde ao hash enviado à Apple.
- Teste de logout limpando Keychain e dados locais.

Critérios de aceite:
- Login funciona em aparelho real (iPhone 15) contra o backend de staging (ou servidor mock, se o backend ainda não existir).
- Revogação remota derruba a sessão local.
- Sem warnings; testes verdes.
```
