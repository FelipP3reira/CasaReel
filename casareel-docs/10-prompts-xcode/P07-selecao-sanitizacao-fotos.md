# P07 — Seleção de fotos, validação e sanitização

```
Leia CLAUDE.md, docs/05-seguranca/controles-de-seguranca.md (seções 1.4 e 3) e docs/01-produto/requisitos.md (RF-011 a RF-016).

Implemente MediaKit (parte de preparo) e FeaturePhotos.

Seleção:
- PhotosPicker (SwiftUI) com seleção múltipla (até 40) e filtro de imagens. Não solicitar acesso total à biblioteca.
- Carregar via Transferable/PhotosPickerItem com streaming para arquivo temporário (NSFileProtectionCompleteUnlessOpen), evitando manter muitas imagens em memória.

Validação local (PhotoValidator):
- Tipos permitidos: JPEG, HEIC, PNG (verificar pelos primeiros bytes/UTI, não só extensão).
- Tamanho máximo 25 MB; dimensões mínimas 1280 px no lado maior; máximo 50 megapixels (evitar bomba de descompressão); decodificar com CGImageSource usando limites (kCGImageSourceShouldCache = false, thumbnail com tamanho máximo).
- Rejeitar com motivo claro e localizado.

Sanitização (PhotoSanitizer):
- Re-encodar com CGImageDestination (JPEG qualidade ~0.9 ou HEIC) removendo TODOS os metadados (EXIF, GPS, TIFF, IPTC, MakerApple), preservando apenas orientação aplicada aos pixels e perfil de cor.
- Redimensionar para o lado maior máximo de 4096 px.
- Calcular SHA-256 do arquivo final (CryptoKit, em streaming).
- Detectar duplicatas locais por hash e por hash perceptual simples (aHash/dHash) e avisar o usuário.
- Retornar PreparedPhoto { fileURL, sha256, size, width, height, mimeType }.

UI:
- Grade de miniaturas com estado (preparando, ok, rejeitada + motivo), reordenação por arrastar, remoção, contador (mín. 5, máx. 40).
- Aviso de privacidade: "Removemos localização e metadados das fotos antes de enviar."
- Opção (desligada por padrão, preparar gancho para P09) de borrar rostos.

Testes:
- Fixtures: JPEG com GPS (deve sair sem GPS; verificar via CGImageSourceCopyPropertiesAtIndex), arquivo com extensão .jpg mas conteúdo PNG, arquivo corrompido, imagem gigante, HEIC, duplicata.
- Teste de que nenhum arquivo temporário sobra após cancelar.

Critérios de aceite:
- Nenhuma foto enviada sem passar pelo sanitizer.
- Testes comprovam remoção de GPS/EXIF.
- Memória estável ao preparar 40 fotos (verificar no Instruments).
- Sem warnings; testes verdes.
```
