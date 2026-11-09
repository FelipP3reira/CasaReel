# P02 — Design System e shell de navegação

```
Leia CLAUDE.md. Implemente o módulo DesignSystem e o shell de navegação do App.

DesignSystem:
- Tokens: cores (suporte a modo claro/escuro), tipografia (Dynamic Type via estilos de texto), espaçamentos, raios, sombras.
- Componentes: PrimaryButton, SecondaryButton, LoadingButton, TextFieldRow com validação, Card, EmptyState, ErrorBanner, ProgressRing, Tag, Toast, SkeletonView.
- Todos com labels de acessibilidade, suporte a Dynamic Type até accessibility sizes, alvo mínimo de toque 44pt e respeito a "Reduzir Movimento".
- Sem strings fixas: use String Catalog.

Navegação:
- Enum tipado AppRoute (auth, propertyList, propertyDetail(id), photoPicker, videoEditor, subscription, privacy, settings).
- RootView com TabView (Imóveis, Criar, Conta) após login; fluxo de auth antes.
- Router (@Observable, @MainActor) com NavigationStack e path tipado; suporte a deep links via Universal Links mapeados a AppRoute (somente rotas não sensíveis; exigir sessão válida).
- Estado global de sessão (signedOut/signedIn/revoked) no AppEnvironment.

Segurança/privacidade:
- Crie um ScreenPrivacyModifier que exibe overlay opaco quando o app vai para background (cena inativa) nas telas marcadas como sensíveis.
- Nenhum dado de usuário em logs.

Testes:
- Snapshot ou testes de estado dos componentes principais.
- Teste do Router (push/pop/deep link inválido é ignorado).
- Auditoria de acessibilidade básica nas telas placeholder.

Critérios de aceite:
- Telas placeholder navegáveis em simulador e aparelho.
- Dynamic Type grande não corta texto.
- Deep link para rota sensível sem sessão é rejeitado.
- Build sem warnings e testes verdes.
```
