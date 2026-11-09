# P22 — Viewer do tour (WKWebView restrito) e compartilhamento

```
Leia CLAUDE.md, docs/05-seguranca/controles-de-seguranca.md (seção 5) e o manifest do tour (docs/04-ia-ciencia-de-dados, seção 4.4).

Implemente FeatureTour.

1. Tela do tour: WKWebView carregando o viewer web do domínio próprio (URL vinda de AppConfiguration) com token de acesso curto obtido da API. Configuração restrita: 
   - WKWebViewConfiguration com `limitsNavigationsToAppBoundDomains` e lista App-Bound Domains (WKAppBoundDomains no Info.plist) contendo apenas o domínio do viewer e o da mídia.
   - Bloquear navegação para fora do allowlist via WKNavigationDelegate (abrir links externos no Safari após confirmação).
   - JavaScript habilitado somente para o viewer; sem acesso a arquivos locais (allowFileAccessFromFileURLs/universal access desligados); sem WKUserScripts de terceiros; `isInspectable = false` em Release.
   - Sem passagem de tokens por URL de query; usar cabeçalho/postMessage controlado ou token de curta duração com escopo restrito.
   - Content mode mobile; giroscópio opcional (CoreMotion) com permissão e opção de desligar.
2. Controles nativos sobrepostos: fechar, alternar cômodo (lista vinda do manifest), reiniciar posição, modo de toque (arrastar para olhar/duplo toque para mover), ajuda de gestos.
3. Estados: carregando (progressivo), erro de rede, tour indisponível, versão do manifest incompatível (pedir atualizar app).
4. Compartilhamento: criar link público (reaproveita P12) para o output tour_3d/tour_360; copiar código `<iframe>` de incorporação (apenas se o anfitrião informar seu domínio, para a allowlist de frame-ancestors; enviar ao backend via endpoint de configuração do tour — se ainda não existir, registrar como pendência de backend).
5. Desempenho: desligar o tour ao entrar em background; limitar uso de memória e baixar LODs conforme térmico.

Testes:
- Delegate bloqueia navegação para domínios fora da allowlist (teste unitário do decisor de política).
- Manifest inválido/versão desconhecida tratado sem crash.
- UI test: abrir tour de fixture local servida por servidor de teste em domínio permitido.

Critérios de aceite:
- Tour abre e navega suavemente no iPhone 15 (>= 30 fps no tour de teste).
- Links externos nunca abrem dentro do WebView.
- Sem warnings; testes verdes.
```
