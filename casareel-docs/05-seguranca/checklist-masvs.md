# Checklist OWASP MASVS (adaptado) + API Security Top 10

Marque durante o desenvolvimento e na revisão pré-lançamento. Execução recomendada: MASTG (testes manuais) + ferramentas (MobSF, Frida/objection em dispositivo de teste, Burp/mitmproxy).

## MASVS-STORAGE
- [ ] Nenhum token, senha ou dado sensível em `UserDefaults`, plist, arquivos ou logs
- [ ] Tokens no Keychain `ThisDeviceOnly`
- [ ] Arquivos sensíveis com `NSFileProtection` adequada e fora do backup
- [ ] Sem dados sensíveis em screenshots do app switcher
- [ ] Sem dados sensíveis na área de transferência

## MASVS-CRYPTO
- [ ] Apenas APIs criptográficas da plataforma (CryptoKit/Security); sem criptografia caseira
- [ ] Chaves geradas no Secure Enclave/Keychain quando aplicável
- [ ] Nenhuma chave simétrica fixa no binário
- [ ] Aleatoriedade com `SecRandomCopyBytes`/`SystemRandomNumberGenerator`

## MASVS-AUTH
- [ ] Sign in with Apple com nonce validado no servidor
- [ ] Refresh token rotativo; reuso revoga sessão
- [ ] Reautenticação (biometria/senha) para exportar dados e excluir conta
- [ ] Logout apaga Keychain e caches locais
- [ ] Bloqueio/atraso progressivo contra força bruta (servidor)

## MASVS-NETWORK
- [ ] ATS sem exceções
- [ ] Pinning de chave pública com pin de backup e plano de rotação
- [ ] Nenhuma requisição HTTP em claro
- [ ] Validação de certificado jamais desativada (nem em debug compartilhado)
- [ ] Tráfego sensível nunca em URL/query string

## MASVS-PLATFORM
- [ ] Universal Links validados; sem ações sensíveis por link
- [ ] `WKWebView` restrito: sem acesso a arquivos locais, JS limitado, origens permitidas
- [ ] Permissões mínimas com justificativa clara
- [ ] Extensões/URL schemes não expõem funções sensíveis
- [ ] Sem `UIPasteboard` com dados sensíveis

## MASVS-CODE
- [ ] Dependências atualizadas e auditadas (SCA); `Package.resolved` versionado
- [ ] Validação de todas as entradas (arquivos, deep links, respostas da API)
- [ ] Sem `fatalError`/force-unwrap em caminhos com dados externos
- [ ] Compilação com otimizações, símbolos removidos em release
- [ ] Warnings tratados; análise estática (SwiftLint, Xcode Analyzer) sem alertas críticos
- [ ] Memória: sem vazamentos em fluxos de mídia/AR (Instruments)

## MASVS-RESILIENCE
- [ ] Sinais de jailbreak/instrumentação coletados e enviados como risco
- [ ] App Attest/DeviceCheck integrados e verificados no servidor
- [ ] Anti-debug básico em release
- [ ] Verificação de integridade de pacotes de template/modelo

## MASVS-PRIVACY
- [ ] `PrivacyInfo.xcprivacy` correto
- [ ] Rótulos de privacidade da App Store coerentes
- [ ] Consentimentos registrados e revogáveis
- [ ] EXIF/GPS removidos antes do upload
- [ ] Exportação e exclusão de dados funcionando de ponta a ponta

## OWASP API Security Top 10 (2023) — backend
- [ ] **API1 BOLA:** checagem de propriedade em todo recurso; testes automatizados
- [ ] **API2 Autenticação quebrada:** tokens curtos, rotação, rate limit, MFA
- [ ] **API3 BOPLA:** respostas sem campos internos; `$hidden`/Resources; sem mass assignment
- [ ] **API4 Consumo irrestrito de recursos:** limites de tamanho, taxa, cotas, custo de GPU
- [ ] **API5 BFLA:** funções administrativas isoladas e protegidas
- [ ] **API6 Fluxos de negócio sensíveis:** antifraude em créditos/assinatura/trials
- [ ] **API7 SSRF:** sem busca de URLs do usuário
- [ ] **API8 Má configuração:** CORS, cabeçalhos, debug desligado, mensagens de erro genéricas
- [ ] **API9 Inventário:** OpenAPI atualizado, versões antigas desativadas
- [ ] **API10 Consumo inseguro de APIs:** validar respostas de Apple/provedores; timeouts e circuit breaker

## Upload e processamento
- [ ] Allowlist de tipos, magic bytes, limites de pixels/tamanho
- [ ] Quarentena e promoção após validação
- [ ] Re-encode sem metadados
- [ ] Workers sem rede, sem root, com limites
- [ ] Fuzz dos parsers

## Pré-lançamento
- [ ] Pentest de app + API + upload + billing concluído; achados críticos/altos corrigidos
- [ ] Revisão do jurídico (termos, privacidade, LGPD, direitos de imagem)
- [ ] Plano de resposta a incidentes testado em exercício de mesa
- [ ] `security.txt` e canal de contato publicados
- [ ] Backups restaurados com sucesso em teste
- [ ] Chaves/segredos rotacionados antes do go-live
