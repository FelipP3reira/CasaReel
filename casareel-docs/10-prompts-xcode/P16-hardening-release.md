# P16 — Hardening e checklist de release (TestFlight)

```
Leia CLAUDE.md, docs/05-seguranca/checklist-masvs.md e docs/05-seguranca/lgpd-privacidade.md.

Prepare o app para beta público (TestFlight) e revisão da App Store.

1. Revisão de segurança do código: percorrer o checklist MASVS item a item e marcar o estado em docs/05-seguranca/checklist-masvs-status.md (OK / pendente / N/A com justificativa). Corrigir o que for simples e abrir lista do que depender de backend.
2. Release build: otimizações, remoção de símbolos de debug, Bitcode não aplicável, `ptrace` anti-debug em Release, strings sensíveis não presentes no binário (rodar `strings` e checar), sem `NSLog`/`print`.
3. Configuração: ATS sem exceções, Associated Domains, Background Modes mínimos (apenas o necessário: background URLSession/processing), entitlements mínimos (App Attest ambiente production no Release), permissões com textos claros.
4. Privacidade: conferir PrivacyInfo.xcprivacy, rótulos de privacidade, links de política e termos, classificação etária (17+ não necessário; avaliar conteúdo gerado por usuário), contato de suporte.
5. App Store: checklist das diretrizes (exclusão de conta in-app, restaurar compras, paywall com informações obrigatórias, Sign in with Apple, descrição fiel, capturas de tela, notas para revisão com conta de teste e instruções).
6. Fastlane ou Xcode Cloud: lane `beta` (test + archive + upload TestFlight) com versionamento automático; segredos via cofre do CI, nunca no repositório.
7. Observabilidade: dSYM enviados (Sentry/Crashlytics se aprovado), MetricKit habilitado, logs sem PII.
8. Plano de rollback e kill switches: validar configuração remota assinada (desligar recursos, pinning de emergência).
9. Documento docs/release-notes-beta.md com limitações conhecidas e como reportar bugs.

Critérios de aceite:
- Build Release instala e roda no iPhone 15 via TestFlight interno.
- Nenhuma ocorrência de segredo/URL de staging no binário de produção.
- Checklist MASVS sem itens "críticos" pendentes.
- Documentação de revisão da App Store pronta.
```
