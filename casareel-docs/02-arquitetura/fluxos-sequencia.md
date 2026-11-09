# Fluxos principais (diagramas de sequência)

## 1. Login com Sign in with Apple + token do app

```mermaid
sequenceDiagram
    autonumber
    participant App as App iOS
    participant Apple as Apple ID
    participant API as API Laravel
    participant DB as PostgreSQL

    App->>App: Gera nonce aleatório e guarda o hash
    App->>Apple: ASAuthorizationController (nonce = SHA256)
    Apple-->>App: identityToken (JWT) + authorizationCode
    App->>API: POST /v1/auth/apple {identityToken, nonce, deviceId}
    API->>Apple: Baixa JWKS (cache) e valida assinatura, iss, aud, exp, nonce
    API->>DB: Upsert user por apple_sub
    API->>DB: Cria device_session (refresh token hasheado)
    API-->>App: accessToken (15 min) + refreshToken (rotativo)
    App->>App: Guarda tokens no Keychain (ThisDeviceOnly)
```

## 2. Renovação de token com rotação e detecção de reuso

```mermaid
sequenceDiagram
    autonumber
    participant App
    participant API
    participant DB

    App->>API: POST /v1/auth/refresh {refreshToken}
    API->>DB: Busca sessão pelo hash do refreshToken
    alt token válido e não usado
        API->>DB: Marca token como usado, emite novo par na mesma família
        API-->>App: novo accessToken + novo refreshToken
    else token já usado (reuso)
        API->>DB: Revoga toda a família de tokens do dispositivo
        API-->>App: 401 session_revoked
        App->>App: Apaga Keychain e volta ao login
    end
```

## 3. Upload seguro de fotos

```mermaid
sequenceDiagram
    autonumber
    participant App as App iOS
    participant API as API
    participant S3 as Object Storage
    participant Q as Fila (Redis)
    participant W as Worker CPU
    participant DB

    App->>App: PHPicker, remove EXIF/GPS, redimensiona, calcula SHA-256
    App->>API: POST /v1/properties/{id}/photos/upload-intents [{size, mime, sha256}]
    API->>API: Valida cota, tamanho, mime permitido, limite de taxa
    API->>DB: Cria media_assets (status=pending)
    API-->>App: URLs pré-assinadas PUT (expiração 10 min, content-length e checksum fixados)
    App->>S3: PUT objeto (URLSession em background)
    App->>API: POST /v1/media/{id}/complete
    API->>Q: Enfileira validate_and_sanitize(media_id)
    Q->>W: Job
    W->>S3: Baixa objeto para sandbox
    W->>W: Verifica magic bytes, decodifica, re-encoda sem metadados, antivírus, hash
    alt arquivo válido
        W->>S3: Grava derivados (thumb, web, analysis)
        W->>DB: status=ready
    else inválido
        W->>S3: Move original para quarentena
        W->>DB: status=rejected + motivo
    end
    API-->>App: Estado via push silencioso ou polling
```

## 4. Geração de vídeo — render local (padrão da Fase 1)

```mermaid
sequenceDiagram
    autonumber
    participant App as App iOS
    participant API
    participant W as Worker (análise)

    App->>API: POST /v1/properties/{id}/jobs {type: analyze_photos}
    API->>W: Enfileira análise (qualidade, ambiente, ordem)
    W-->>API: Resultado (scores, ordem sugerida, avisos)
    App->>API: GET /v1/jobs/{id}
    API-->>App: Sugestões
    App->>App: Usuário escolhe template e ajusta ordem/textos
    App->>App: Render local (AVFoundation) a partir do JSON do template
    App->>API: POST /v1/properties/{id}/videos {template, duração, hash do arquivo}
    API-->>App: URL pré-assinada para guardar o vídeo (backup/compartilhar)
    App->>API: POST /v1/videos/{id}/share-links {expiresIn}
    API-->>App: URL pública assinada
```

## 5. Geração de vídeo — render no servidor (premium)

```mermaid
sequenceDiagram
    autonumber
    participant App
    participant API
    participant Q as Fila
    participant W as Worker FFmpeg/GPU
    participant S3
    participant DB

    App->>API: POST /v1/properties/{id}/jobs {type: render_video, template, params}
    API->>DB: Cria job (queued) com idempotency_key e custo estimado
    API->>Q: Enfileira
    API-->>App: 202 {jobId}
    Q->>W: Job
    W->>S3: Baixa derivados
    W->>W: Renderiza conforme JSON do template
    W->>S3: Grava vídeo + thumbnail
    W->>DB: Job succeeded + outputs + custo real
    API-->>App: Push silencioso, depois GET /v1/jobs/{id}
```

## 6. Tour 3D (Fase 2) — captura sem LiDAR

```mermaid
sequenceDiagram
    autonumber
    participant App as App iOS (ARKit)
    participant API
    participant S3
    participant Q as Fila
    participant WC as Worker CPU
    participant WG as Worker GPU
    participant Web as Viewer Web

    App->>App: Captura guiada por cômodo (ARKit): frames, poses, intrínsecos
    App->>App: Feedback em tempo real: cobertura, blur, luz, velocidade
    App->>API: POST /v1/properties/{id}/captures {rooms, frameCount}
    API-->>App: URLs pré-assinadas (lote de frames + capture.json)
    App->>S3: Upload dos frames e metadados
    App->>API: POST /v1/captures/{id}/complete
    API->>Q: validate_capture
    Q->>WC: Checagem (cobertura, blur, sobreposição, poses)
    alt qualidade suficiente
        WC->>Q: reconstruct_3d
        Q->>WG: Sobe GPU, treina splats com poses do ARKit
        WG->>WG: Limpeza (floaters), recorte, compressão, thumbnails
        WG->>S3: tour.splat + manifest.json
        WG->>API: job succeeded (custo, métricas de qualidade)
    else insuficiente
        WC->>API: needs_recapture com orientações (qual cômodo, o que falta)
    end
    API-->>App: Notificação
    Web->>API: GET /v1/tours/{id}/manifest (token assinado)
    API-->>Web: URLs de assets + configurações
    Web->>S3: Baixa assets via CDN
```

## 7. Assinatura (StoreKit 2 + validação no servidor)

```mermaid
sequenceDiagram
    autonumber
    participant App
    participant Store as App Store
    participant API
    participant DB

    App->>Store: Product.purchase() com appAccountToken (UUID do usuário)
    Store-->>App: Transaction (JWS assinado)
    App->>API: POST /v1/billing/apple/transactions {signedTransaction}
    API->>API: Valida cadeia de certificados do JWS (raiz Apple), bundleId, environment
    API->>DB: Atualiza entitlements
    Store->>API: Webhook Notifications V2 (renovação, expiração, reembolso)
    API->>API: Valida JWS e processa de forma idempotente (notificationUUID)
    API->>DB: Atualiza entitlements
    App->>API: GET /v1/me/entitlements
```

## 8. Exclusão de conta (LGPD)

```mermaid
sequenceDiagram
    autonumber
    participant App
    participant API
    participant Q as Fila
    participant W as Worker
    participant DB
    participant S3

    App->>API: DELETE /v1/me {reauth}
    API->>DB: Marca deletion_requested_at e revoga sessões
    API-->>App: 202 (carência de 7 dias, pode cancelar)
    Note over API,DB: Após a carência, job agendado
    Q->>W: purge_user(user_id)
    W->>S3: Apaga objetos e derivados
    W->>DB: Anonimiza/exclui registros e mantém apenas o que a lei exigir (ex. fiscal)
    W->>DB: Registra evidência de exclusão (sem PII)
```
