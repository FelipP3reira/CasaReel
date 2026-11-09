# P03 — Módulo Security

```
Leia CLAUDE.md, docs/05-seguranca/controles-de-seguranca.md (seção 1) e docs/05-seguranca/checklist-masvs.md.

Implemente o pacote Security (sem dependências externas). Protocolos ficam em Domain; implementações aqui.

1) KeychainStore
- API tipada genérica (set/get/delete para Data e Codable) com kSecAttrAccessibleWhenUnlockedThisDeviceOnly, sem sincronização iCloud.
- Opção de controle de acesso com biometria (SecAccessControl .biometryCurrentSet) para itens que pedirmos.
- Erros mapeados em enum; nenhum valor sensível em mensagens de erro.
- Testes com Keychain real no simulador (limpando após cada teste).

2) TokenManager (actor)
- Guarda access/refresh no Keychain; expõe accessToken válido; renova com lock (apenas uma renovação concorrente; demais aguardam).
- Em "session_revoked": apaga Keychain e emite evento para o estado global.
- Interface para o cliente de rede (será ligado no P04).
- Testes de concorrência (várias chamadas simultâneas = 1 refresh).

3) PinningDelegate
- Valida a chave pública (SPKI SHA-256) do certificado do servidor contra um conjunto de pins (atual + backup) vindos de AppConfiguration.
- Falha fechada: se não bater, cancela o desafio.
- SignedConfigVerifier (Ed25519 via CryptoKit) para verificar uma configuração remota que possa desativar o pinning em emergência (kill switch) e atualizar pins; a chave pública de verificação fica embutida no app.
- Testes com certificados de teste (bom, ruim, expirado).

4) AppAttestClient
- Usa DCAppAttestService: gerar chave, solicitar challenge ao servidor (/attest/challenge), atestar (/attest/register), gerar asserções para requests sensíveis (hash do corpo + challenge).
- Persistir keyId no Keychain. Tratar isSupported == false com fallback explícito (marcar requisições como "sem attest" para o servidor tratar como risco maior).
- Protocolo AttestProviding para permitir mock em testes.

5) IntegritySignals
- Coletar sinais de jailbreak/instrumentação/depurador (arquivos conhecidos, escrita fora do sandbox, bibliotecas injetadas, sysctl P_TRACED). Retorna lista de sinais; NUNCA bloqueia sozinho; é enviada como header X-Device-Risk com valor resumido.
- Documentar limitações no código (bypassável).

6) SecureLogger
- Wrapper de os.Logger com privacy: .private por padrão e redator para padrões de token/e-mail.
- Teste que garante que strings contendo "Bearer ..." ou e-mails são redigidas.

7) ScreenPrivacy
- Utilitário para overlay no app switcher (se não feito no P02, completar aqui).

Critérios de aceite:
- Cobertura de testes >= 80% no pacote.
- Nenhum uso de UserDefaults para dados sensíveis.
- Pinning falha com certificado errado (teste).
- Nenhuma chave privada no código; apenas chave pública de verificação.
- Documentação curta em Packages/Security/README.md com decisões e limites.
```
