# P06 — Imóveis (CRUD) e persistência local

```
Leia CLAUDE.md, docs/03-dados/modelo-de-dados.md e docs/06-api/openapi.yaml (/properties).

Implemente FeatureProperties e Persistence.

Funcionalidade:
- Lista de imóveis (paginação por cursor, pull-to-refresh, estado vazio, erro com retry).
- Criar/editar imóvel: título (1–140), descrição (até 4000), cidade pública, endereço (campo privado, explicar na UI que não é exibido publicamente).
- Excluir imóvel com confirmação (soft delete no servidor).
- Detalhe do imóvel: fotos, vídeos gerados (placeholders por enquanto).
- Rascunhos locais (SwiftData) para criação offline; sincronizar ao reconectar usando Idempotency-Key estável por rascunho.

Persistência:
- Modelos SwiftData para PropertyDraft, PropertyCache (metadados mínimos). NÃO armazenar endereço exato em cache local em claro: se precisar cachear, cifrar com chave do Keychain (CryptoKit AES-GCM) ou simplesmente não cachear.
- Marcar o armazenamento com NSFileProtectionComplete e excluir do backup.
- Migração de schema versionada.
- Limpeza total no logout.

Validação:
- Validar localmente (comprimento, caracteres de controle) e refletir erros 422 do servidor por campo.

Segurança/privacidade:
- Campo de endereço com textContentType apropriado, sem sugestões que enviem dados a terceiros além do necessário; sem logs de conteúdo.
- IDs sempre UUID do servidor; nunca montar URLs com texto livre.

Testes:
- ViewModel: criar, editar, excluir, erro de validação do servidor, offline -> rascunho -> sincronização.
- Teste de que logout apaga cache/rascunhos.

Critérios de aceite:
- CRUD funcionando contra staging/mock.
- Nenhum endereço em claro em arquivos do app (verificar inspecionando o container do simulador).
- Testes verdes, sem warnings.
```
