# P11 — Editor e pré-visualização do vídeo

```
Leia CLAUDE.md e use o VideoEngine (P10) e a análise (P09).

Implemente FeatureVideo.

Fluxo em 4 passos:
1. Escolher template (cards com prévia animada leve; badge "Pro" nos premium; bloquear escolha premium sem entitlement e abrir paywall).
2. Roteiro: lista ordenável das fotos (sugestão do ShotOrderPlanner), remover/duplicar cena, ajustar duração por cena, rótulo do cômodo (editável, limite de 40 caracteres).
3. Personalização: trilha (biblioteca embutida, volume, sem música), texto de abertura/encerramento (limite de caracteres), logo opcional do anfitrião (imagem escolhida pelo PhotosPicker, sanitizada como as fotos), formato (9:16, 16:9 ou ambos).
4. Pré-visualização e exportação: player (AVPlayer) com render rápido de baixa resolução (proxy 540p) para prévia; botão "Gerar vídeo" executa o render final com progresso, cancelamento e estimativa de tempo; aviso de bateria/térmico.

Após exportar:
- Registrar o vídeo no backend (POST /properties/{id}/videos) com templateSlug/version, aspect, duração, tamanho, sha256; enviar o arquivo pela URL pré-assinada retornada usando o UploadManager (P08).
- Salvar no rolo da câmera apenas se o usuário escolher (NSPhotoLibraryAddUsageDescription só quando necessário).
- Mostrar o selo "Conteúdo gerado/editado" apenas se synthetic_content for true (por padrão false nesta fase).

Estado e robustez:
- Rascunho do projeto de vídeo salvo localmente (SwiftData) e restaurável.
- Tratar falta de espaço em disco (checar antes de renderizar), interrupções e cancelamento.
- Acessibilidade: controles do editor com labels, reordenação acessível (ações de VoiceOver).

Testes:
- ViewModel: seleção de template premium sem entitlement -> paywall; reordenação; limites de texto; rascunho salvo/restaurado.
- Teste de integração com VideoEngine usando fixtures.
- UI test do fluxo completo com fotos de fixture.

Critérios de aceite:
- Fluxo completo do template ao vídeo exportado e registrado, em aparelho real.
- Prévia fluida (>= 24 fps percebidos) no iPhone 15.
- Sem warnings; testes verdes.
```
