# P08 — Upload seguro em background

```
Leia CLAUDE.md, docs/02-arquitetura/fluxos-sequencia.md (fluxo 3) e docs/06-api/openapi.yaml (upload-intents, /media/{id}/complete).

Implemente o UploadManager em MediaKit com fila persistida em Persistence.

Fluxo por arquivo:
1. Criar UploadItem (SwiftData): id local, propertyId, fileURL, sha256, size, mimeType, estado (queued, requestingIntent, uploading, completing, processing, ready, rejected, failed), tentativas, mediaId, expiresAt da URL.
2. Solicitar upload-intents em lote (máx. 40) com Idempotency-Key estável por lote.
3. Enviar via URLSession com configuração background (identifier único), PUT no URL pré-assinado com EXATAMENTE os headers retornados (Content-Type, checksum, content-length); usar upload task a partir de arquivo.
4. Ao concluir, POST /media/{id}/complete. Em seguida, acompanhar status (polling com backoff + ETag; preparar suporte a push silencioso).
5. Se a URL expirou ou o servidor devolver 403 do storage, pedir nova intent para o mesmo item (sem duplicar mídia).
6. Retomar ao reabrir o app (reconstruir o estado a partir da fila e das tasks pendentes do URLSession).
7. Respeitar rede: opção "somente Wi‑Fi" (padrão ligado para vídeos grandes), Low Data Mode, estado térmico/bateria.
8. Reportar progresso agregado por imóvel.

Segurança:
- Nunca logar URLs assinadas nem query strings. Não persistir a URL assinada além do necessário (guardar apenas o expiresAt e solicitar nova quando preciso).
- Arquivos temporários com NSFileProtectionCompleteUnlessOpen; apagar após sucesso, rejeição definitiva ou logout.
- Verificar que o SHA-256 do arquivo no momento do upload ainda corresponde ao declarado; se mudou, abortar.
- Limites: no máximo N uploads simultâneos (ex.: 3); backoff exponencial com jitter; teto de tentativas.

UI:
- Tela de progresso por foto (enviando, processando, aprovada, rejeitada com motivo), ação de tentar novamente, cancelar.

Testes:
- Com servidor/storage mock: fluxo feliz, expiração de URL, falha de rede no meio, app reiniciado (reconstrução da fila), rejeição pelo servidor (reject_reason), alteração do arquivo local.
- Teste de que logs não contêm URL assinada.

Critérios de aceite:
- Upload de 20 fotos continua após enviar o app para background e finaliza.
- Nenhuma duplicação de mídia em retry.
- Arquivos temporários removidos ao final.
- Sem warnings; testes verdes.
```
