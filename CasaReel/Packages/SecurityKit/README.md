# SecurityKit

Implementações de segurança do app (sem dependências externas). Os contratos (`SecureStore`, `AccessTokenProviding`, `TokenRefreshing`) ficam em `Domain/Security`.

> O módulo se chama `SecurityKit` porque `Security` colide com o framework da Apple.

## Componentes

| Tipo | O que faz | Decisões |
|---|---|---|
| `KeychainStore` | CRUD tipado (`Data` e `Codable`) no Keychain | `WhenUnlockedThisDeviceOnly`, sem sincronização iCloud; biometria opcional com `.biometryCurrentSet` (novo rosto/digital invalida o item); erros sem valores sensíveis |
| `TokenManager` (actor) | Guarda access/refresh e entrega um access token válido | Uma única renovação por vez (as demais aguardam); renova 60 s antes de expirar; em `session_revoked` apaga o Keychain e emite `SessionEvent.revoked`; sair durante uma renovação não ressuscita a sessão |
| `PinningDelegate` + `PinningPolicy` | Pinning SPKI SHA-256 do host da API | Falha fechada; validação do sistema (cadeia + hostname) **sempre** roda antes dos pins; exige pin atual + backup; outros hosts (ex.: URLs de upload) usam a validação padrão |
| `SignedConfigVerifier` | Verifica configuração remota assinada (Ed25519/CryptoKit) | Só a chave **pública** fica no app; payload com `version` monotônica e `expiresAt`; pode desligar o pinning (kill switch) ou trocar pins, nunca a validação do sistema |
| `AppAttestClient` | App Attest: gera chave, atesta e assina requests sensíveis | Asserção sobre `SHA-256(corpo ‖ challenge)`; `keyId` no Keychain só após o servidor aceitar; sem suporte ou com falha envia `X-App-Attest-Status` para o servidor tratar como risco maior |
| `IntegritySignals` | Sinais de jailbreak, bibliotecas injetadas e depurador | Vai no header `X-Device-Risk` (ex.: `v1;debugger,dylib`); **nunca bloqueia** o app sozinho |
| `SecureLogger` | Wrapper do `os.Logger` | Redige Bearer, JWT, pares `token=`/`password=` e e-mails, e ainda registra como `.private` |

A capa do app switcher (`ScreenPrivacy`) está no `DesignSystem` (P02).

## Limites conhecidos

- **Sinais de integridade são contornáveis.** Rodam num processo que o atacante controla (Frida, jailbreaks rootless escondem arquivos). Servem só como indício para o servidor; o App Attest é o sinal forte.
- **Replay da configuração remota após reiniciar.** A `version` aplicada fica só em memória; uma configuração antiga ainda dentro do `expiresAt` poderia ser reaplicada depois de reabrir o app. Mitigação: o servidor emite configurações com validade curta. Persistir a versão é uma melhoria futura.
- **Pins e chave de assinatura nos `.xcconfig` são placeholders.** Antes de publicar, gere os pins reais (atual + backup) do host da API e um par Ed25519 cuja chave privada fique fora do repositório (cofre/HSM). Com os placeholders, nenhuma configuração remota pode ser assinada, e o pinning fica ativo com os pins do bundle.
- **App Attest não funciona no simulador** e exige conta paga do Apple Developer Program e o entitlement correspondente no aparelho.
- **Testes do Keychain real são pulados nos testes de pacote**: o processo de teste SPM não tem o entitlement de Keychain (`-34018`). Eles rodam quando houver um target de testes hospedado no app.

## Ligações pendentes (P04)

`TokenManager` precisa de um `TokenRefreshing` e `AppAttestClient` de um `AttestServerAPI`; ambos serão implementados pelo `Networking`, que também instala o `PinningDelegate` na `URLSession` e envia `X-Device-Risk`.

## Testes

```sh
cd Packages/SecurityKit
xcodebuild test -scheme SecurityKit -destination 'platform=iOS Simulator,name=iPhone 17e' -enableCodeCoverage YES
```

Os testes de pinning usam uma PKI descartável (`TestCertificates.swift`): certificado bom, com chave diferente e expirado.
