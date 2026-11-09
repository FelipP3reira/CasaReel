# P20 — ARCaptureKit: captura guiada sem LiDAR (Fase 2)

> Pré-requisito: Gate 1 aprovado e **spike de reconstrução** concluído (ver `09-roadmap`). Os parâmetros abaixo são pontos de partida a ajustar com os dados do spike.

```
Leia CLAUDE.md, docs/04-ia-ciencia-de-dados/pipeline-ia-e-ciencia-de-dados.md (seção 4) e docs/07-app-ios/arquitetura-ios.md (seção 8).

Implemente ARCaptureKit e FeatureCapture3D. O aparelho alvo é um iPhone 15 SEM LiDAR: não dependa de LiDAR, RoomPlan nem Object Capture. Se houver LiDAR (supportsFrameSemantics(.sceneDepth)), salve profundidade como bônus opcional.

Captura:
1. ARSession com ARWorldTrackingConfiguration; permissão de câmera com texto claro; tratar interrupções (ligação, background) pausando e retomando com aviso (se o tracking se perder, reiniciar o segmento do cômodo).
2. Uma CaptureSession por cômodo com nome (sala, quarto...). Instruções animadas antes de começar: caminhar devagar, manter o celular na altura do peito, fazer um arco de 360° em cada cômodo, iluminar o ambiente, evitar espelhos/janelas ao fundo se possível.
3. Seleção de frames: a cada ARFrame, salvar apenas se (a) trackingState == .normal, (b) deslocamento >= ~8 cm OU rotação >= ~7° desde o último frame salvo, (c) intervalo mínimo ~0,2 s, (d) blur aceitável (variância do Laplaciano em baixa resolução acima do limiar), (e) velocidade angular abaixo do limite. Exportar imagem (HEIC ou JPEG qualidade ~0.9) do capturedImage (CVPixelBuffer -> CGImage com orientação correta), camera.transform, camera.intrinsics, imageResolution, timestamp, exposureDuration/ISO se disponível.
4. Metadados em capture.json (schema versionado): deviceModel, iosVersion, hasLidar, rooms[] com frames[] {file, transform(16 floats), intrinsics(9 floats), width, height, timestamp, blurScore}. Documente o schema em docs/ e valide-o por JSON Schema nos testes.
5. Guia em tempo real (overlay SwiftUI sobre ARSCNView/RealityKit): indicador de velocidade (verde/amarelo/vermelho), cobertura angular do cômodo (anel/heatmap em 36 setores de 10°), contador de frames, aviso de pouca luz (lightEstimate.ambientIntensity) e de tracking limitado, botão de finalizar cômodo (habilitado só com cobertura mínima).
6. Limites de segurança/recursos: gravar frames em disco em streaming (NSFileProtectionCompleteUnlessOpen), nunca acumular em memória; abortar com aviso se espaço livre < 2 GB; limite de 400 frames por cômodo e 4000 por captura; pausar sob estado térmico crítico.
7. Revisão antes de enviar: mostrar resumo por cômodo (frames, cobertura, avisos) e permitir refazer um cômodo.

Privacidade:
- Avisar que a captura registra o interior do imóvel e que pessoas e documentos visíveis devem ser evitados; botão "pausar para privacidade".
- Os frames passam pelo mesmo sanitizador de EXIF/GPS do P07.

Testes:
- Unit: seletor de frames (dado um fluxo simulado de poses, escolhe os esperados), cobertura angular, serialização/validação do capture.json.
- Modo simulado: injetar sequência gravada de poses/frames para testar sem câmera (protocolo FrameSource com implementação ARKit e implementação de reprodução).
- Teste manual em aparelho real documentado: capturar 3 cômodos e inspecionar o capture.json.

Critérios de aceite:
- Captura de um cômodo médio em 20–40 s gera 150–400 frames com cobertura >= 85% dos setores.
- Funciona no iPhone 15 sem LiDAR.
- Memória estável e sem frames corrompidos.
- Sem warnings; testes verdes.
```
