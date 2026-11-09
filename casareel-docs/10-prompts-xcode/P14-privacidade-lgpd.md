# P14 — Privacidade e LGPD no app

```
Leia CLAUDE.md e docs/05-seguranca/lgpd-privacidade.md.

Implemente FeaturePrivacy.

Telas e fluxos:
1. Central de Privacidade (Conta > Privacidade): links para Aviso de Privacidade e Termos; lista de consentimentos por finalidade (analytics, marketing, melhoria de IA com fotos) com toggles; cada alteração chama PUT /me/consents (com versão do texto) e persiste o resultado do servidor.
2. Primeira execução: pedido de consentimento granular (analytics e melhoria de IA DESLIGADOS por padrão; sem "dark patterns"; recusar não bloqueia o uso).
3. Exportar meus dados: botão que exige reautenticação (biometria/Apple), chama POST /me/export, informa que será notificado e permite baixar o arquivo quando disponível (URL assinada curta) e compartilhá-lo com a folha de compartilhamento.
4. Excluir conta: explicação clara do que será apagado e da carência de 7 dias; reautenticação; confirmação digitando uma palavra; chama DELETE /me; após sucesso, encerra a sessão, apaga Keychain e todos os dados locais, e revoga a autorização do Sign in with Apple conforme orientação do backend (o backend revoga o token com a Apple; o app apenas apaga estado local e exibe mensagem). Permitir cancelar a exclusão dentro da carência fazendo login novamente (tela informativa).
5. Denunciar conteúdo / contato de privacidade (DPO) acessível.

Requisitos:
- Telemetria só inicializa se o consentimento estiver ativo; se revogar, parar imediatamente e apagar identificadores locais.
- Ao revogar "melhoria de IA", sinalizar ao servidor (efeito imediato no treino futuro).
- PrivacyInfo.xcprivacy e rótulos: revisar se refletem exatamente o que o app coleta; documentar em docs/05-seguranca/app-store-privacy.md.
- Textos claros, acessíveis e localizados (pt-BR, en).

Testes:
- ViewModel: toggles chamam API e revertem em erro; exportação exige reautenticação; exclusão limpa dados locais (Keychain, SwiftData, arquivos).
- Teste que a telemetria não inicia sem consentimento.
- UI test do fluxo de exclusão até o estado deslogado.

Critérios de aceite:
- Exclusão de conta disponível dentro do app (requisito da App Store).
- Nenhum dado local permanece após exclusão/logout (verificar container).
- Sem warnings; testes verdes.
```
