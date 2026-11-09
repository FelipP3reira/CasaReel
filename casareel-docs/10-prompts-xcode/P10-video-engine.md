# P10 — VideoEngine (templates, composição e exportação)

```
Leia CLAUDE.md, docs/04-ia-ciencia-de-dados/pipeline-ia-e-ciencia-de-dados.md (seção 3: formato do template JSON) e docs/07-app-ios/arquitetura-ios.md (seção 5).

Implemente o pacote VideoEngine, testável e determinístico.

1) TemplateSpec
- Tipos Codable do JSON do template (slug, version, aspect, fps, scenes[], audio, watermark). Validação: limites (duração total <= 180 s, cena entre 1 e 8 s, número de cenas <= 60), enums conhecidos, easing válido. Rejeitar specs inválidos com erro descritivo.
- TemplatePackage com assinatura Ed25519 (CryptoKit) verificada com a chave pública embutida; templates embarcados no bundle são confiáveis, os baixados exigem assinatura válida.
- Incluir 3 templates embarcados: "classic-clean" (zoom suave + crossfade), "cinematic-soft" (pan lento + dip-to-black), "dynamic-social" (cortes rápidos sincronizados à batida, 9:16).

2) Planejamento (puro, sem I/O)
- MotionPlanner: dada a foto (tamanho), a região de saliency e o aspect de saída, calcula retângulo inicial/final do Ken Burns sem exceder os limites da imagem e sem cortar rostos; easing determinístico (mesmas funções do worker).
- SceneTimeline: converte spec + lista ordenada de fotos + duração alvo em linha do tempo (cenas, transições, textos).

3) Renderização
- VideoCompositor customizado (AVVideoCompositing) usando Core Image/Metal: desenha cada quadro aplicando transformação do movimento e transições (crossfade, dip-to-black, slide). Reutilizar CIContext e pools de buffer.
- Texto/legendas por cômodo e logo do anfitrião via Core Graphics/Core Image (texto sempre tratado como string, nunca interpretado).
- Marca d'água quando o plano exigir (flag vinda de Entitlements; verificada também no servidor ao registrar o vídeo).
- AudioMixer: trilha (arquivo local da biblioteca embutida/baixada com assinatura), fade in/out, volume.
- Exporter: AVAssetWriter com H.264 (HEVC opcional), 1080x1920 ou 1920x1080, 30 fps, bitrate controlado; progresso (AsyncStream), cancelamento, e escrita em arquivo temporário protegido.
- RenderQueue (actor): um render por vez; pausa/cancela em thermalState .serious/.critical e avisa; mantém tela acordada durante render (isIdleTimerDisabled) e retoma se possível.
- Pré-redução das fotos (CGImageSourceCreateThumbnailAtIndex) para o tamanho do render para limitar memória.

4) Qualidade
- Gerar também thumbnail (JPEG 1280x720) e calcular SHA-256 do vídeo final.

Segurança:
- Nenhuma execução de código vindo do spec; apenas dados validados.
- Limites duros de duração/dimensão para evitar DoS local.

Testes:
- Unit: validação de spec (válidos/inválidos), assinatura (válida/adulterada), MotionPlanner (nunca fora dos limites), SceneTimeline (soma de durações).
- Golden frames: renderizar quadros-chave de um template com fotos de fixture e comparar com imagens de referência (tolerância).
- Integração: renderizar vídeo de 10 s e verificar duração, resolução, trilhas (AVAsset).
- Performance: render de 30 s em <= 2 min no iPhone 15; memória de pico < 1,2 GB.

Critérios de aceite:
- Exporta 9:16 e 16:9 com os 3 templates.
- Cancelamento libera recursos e remove arquivos parciais.
- Template adulterado é rejeitado.
- Sem warnings; testes verdes.
```
