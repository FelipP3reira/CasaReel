# P09 — Análise de fotos no aparelho

```
Leia CLAUDE.md e docs/04-ia-ciencia-de-dados/pipeline-ia-e-ciencia-de-dados.md (capacidades IA-01 a IA-05, IA-08).

Implemente o módulo PhotoAnalysis (dentro de MediaKit ou novo pacote PhotoAnalysis) rodando 100% no aparelho (privacidade e custo zero).

Capacidades:
1. Qualidade (QualityAnalyzer): blur (variância do Laplaciano em versão reduzida via Accelerate/vImage ou Core Image), exposição (histograma: sub/superexposto), inclinação do horizonte (opcional), ruído estimado. Retornar score 0–1 e avisos localizados (ex.: "Foto desfocada", "Muito escura").
2. Ambiente (RoomClassifier): protocolo RoomClassifying; implementação inicial por Vision `VNClassifyImageRequest` mapeando rótulos para {sala, quarto, cozinha, banheiro, fachada, varanda, piscina, outro} e deixar ponto de extensão para um modelo Core ML próprio (.mlpackage) carregado de forma assinada no futuro.
3. Saliency (FocusPlanner): `VNGenerateAttentionBasedSaliencyImageRequest` para sugerir a região de interesse usada no pan/zoom (retornar CGRect normalizado) e detectar rostos (`VNDetectFaceRectanglesRequest`) para evitar cortes sobre rostos e oferecer borrar.
4. Roteiro sugerido (ShotOrderPlanner): ordenar por regras (fachada -> sala -> cozinha -> quartos -> banheiros -> varanda/piscina -> outro), desempate por qualidade; devolver ordem e agrupamentos.
5. Duplicatas/quase-duplicatas: usar o hash perceptual do P07.
6. Borrar rostos (opcional, desligado por padrão): Core Image gaussian blur nas regiões detectadas, gerando nova versão sanitizada antes do upload.

Requisitos:
- Processar em fila com limite de concorrência e baixa resolução intermediária (<= 1024 px) para economizar memória.
- Resultado serializável (AnalysisResult) salvo no SwiftData e enviado ao backend como metadado (apenas scores/rótulos, nunca pixels).
- Sem rede, sem bibliotecas externas.
- Tudo cancelável; nenhuma análise bloqueia a main thread.

UI:
- Mostrar avisos por foto com sugestão ("tire outra foto com mais luz") e a ordem sugerida, permitindo ajuste manual.

Testes:
- Imagens de fixture: nítida vs borrada, clara vs escura, interior vs exterior; testes de faixa (score borrada < nítida).
- Teste do ShotOrderPlanner com listas variadas.
- Teste de performance: 40 fotos em tempo aceitável e memória estável.

Critérios de aceite:
- Todos os avisos e rótulos localizados.
- Cobertura >= 70% no módulo.
- Funciona em aparelho real (iPhone 15) com 40 fotos sem pressão de memória.
```
