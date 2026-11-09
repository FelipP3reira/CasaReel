# P21 — Upload de captura e acompanhamento do job 3D

```
Leia CLAUDE.md, docs/02-arquitetura/fluxos-sequencia.md (fluxo 6) e docs/06-api/openapi.yaml (/properties/{id}/captures, /captures/{id}/complete, /captures/{id}, /properties/{id}/jobs).

Estenda o UploadManager (P08) e implemente o acompanhamento em FeatureCapture3D.

Fluxo:
1. POST /properties/{id}/captures com deviceModel, hasLidar, frameCount e rooms (incluir App Attest assertion e Idempotency-Key).
2. Receber URLs pré-assinadas (lotes) e enviar frames + capture.json via URLSession background, com concorrência limitada, retomada após reinício do app e priorização do capture.json por último (só após todos os frames).
3. POST /captures/{id}/complete e acompanhar status (validating -> needs_recapture | accepted).
4. needs_recapture: exibir o relatório (cômodos a refazer + dicas) e permitir recapturar apenas aqueles cômodos, reaproveitando o restante.
5. accepted: criar o job reconstruct_3d (POST /properties/{id}/jobs com captureId), mostrando custo estimado em créditos e confirmando antes de gastar; tratar 402 (sem créditos) abrindo a compra.
6. Acompanhar o job (progress, etaSeconds) com polling + ETag e push silencioso; permitir sair do app e notificar ao concluir (notificação local/push, com permissão pedida no contexto certo).
7. Em falha do 3D com fallback, informar claramente que um tour 360 foi gerado no lugar (quando aplicável).

Segurança e custo:
- Nunca iniciar job que gaste créditos sem confirmação explícita do usuário.
- Cancelamento libera créditos conforme resposta do servidor (exibir o que o servidor informar; não calcular localmente).
- Limpeza dos frames locais após upload confirmado e aceito (opção de manter até o tour ficar pronto; padrão: apagar após accepted).
- Nada de URLs assinadas em log.

Testes:
- Fluxos: sucesso, falta de rede durante upload, app reiniciado, needs_recapture, 402, cancelamento, falha do job.
- Teste de que os frames locais são apagados conforme a política.

Critérios de aceite:
- Upload de ~600 frames retoma após desconectar a rede e completar.
- Fluxo de recaptura seletiva funciona.
- Sem warnings; testes verdes.
```
