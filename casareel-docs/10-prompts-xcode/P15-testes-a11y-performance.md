# P15 — Testes, acessibilidade e performance

```
Leia CLAUDE.md e docs/08-qualidade-devops/testes-cicd-observabilidade.md.

Consolide a qualidade do app.

Tarefas:
1. Cobertura: medir cobertura por pacote (xccov). Preencher lacunas até >= 70% no Domain/VideoEngine/MediaKit e >= 80% em Security/Networking. Listar o que ficou abaixo e por quê.
2. UI tests (XCUITest) de ponta a ponta com servidor mock: login (Apple mockado via protocolo), criar imóvel, selecionar fotos de fixture, upload, gerar vídeo, compartilhar, comprar (StoreKit Testing), excluir conta. Usar launch arguments para injetar ambiente de teste (nunca habilitar em Release).
3. Acessibilidade: `performAccessibilityAudit()` nas telas principais; revisar VoiceOver (ordem, labels, ações de reordenação), Dynamic Type no maior tamanho, contraste AA, alvos de toque, "Reduzir Movimento".
4. Performance (XCTMetric + Instruments): tempo de inicialização, scroll das listas, render de vídeo (tempo e pico de memória), preparo de 40 fotos, upload. Registrar baselines.
5. Segurança automatizada: testes de que (a) nenhum token/URL assinada aparece em logs, (b) dados sensíveis não são salvos fora do Keychain, (c) pinning rejeita certificado errado, (d) EXIF/GPS removido, (e) Release não aceita launch arguments de teste, (f) ATS sem exceções (inspecionar Info.plist).
6. Configurar SwiftLint no build e um script `scripts/check.sh` que roda lint + testes.
7. Configurar o plano de testes no Xcode (TestPlan) com configurações: unit, UI, performance.

Entregáveis:
- Relatório curto em docs/qualidade-ios.md com cobertura, baselines de performance e pendências.

Critérios de aceite:
- Todos os testes verdes em simulador e UI tests ao menos uma vez em aparelho.
- Sem violações críticas de acessibilidade.
- Baselines de performance registrados.
```
