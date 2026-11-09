# P12 — Compartilhamento e links públicos

```
Leia CLAUDE.md, docs/06-api/openapi.yaml (/outputs/{id}/share-links, /share-links/{id}, /public/s/{token}) e docs/05-seguranca/controles-de-seguranca.md (seção 3).

Implemente o compartilhamento em FeatureVideo (ou FeatureSharing).

Funcionalidades:
1. Compartilhar arquivo: ShareLink/UIActivityViewController com o vídeo local (Instagram, WhatsApp etc.). Usar arquivo temporário e removê-lo ao final.
2. Link público: criar via POST /outputs/{id}/share-links (expiração padrão 30 dias, opções 7/30/90/sem expirar, limite de visualizações opcional). O token completo só aparece na resposta de criação; exibir e permitir copiar/compartilhar. Não persistir o token em log; se guardado localmente, apenas no Keychain e apagar no logout.
3. Gerenciar links: listar, revogar (DELETE) com confirmação, mostrar expiração e visualizações.
4. Universal Links: configurar Associated Domains (applinks:...) e apple-app-site-association de exemplo em docs; abrir links CasaReel dentro do app apenas para rotas permitidas; validar tokens por formato (comprimento/charset) antes de qualquer chamada.
5. Texto de compartilhamento padrão (localizado) com aviso quando o vídeo possuir marca d'água.

Privacidade:
- Avisar o usuário: "Qualquer pessoa com o link poderá ver este vídeo até ele expirar ou ser revogado."
- Nunca incluir endereço exato no texto compartilhado.
- Links marcados como não indexáveis (responsabilidade do servidor/viewer; documentar a expectativa).

Testes:
- ViewModel: criar, revogar, expirar, erro de rede.
- Teste de validação de formato do token em deep link (inválido -> ignorado).
- Teste de limpeza do arquivo temporário após compartilhar.

Critérios de aceite:
- Compartilhamento do arquivo e do link funciona em aparelho real.
- Revogar link o invalida (verificar no servidor de staging).
- Deep link inválido não causa crash nem ação.
- Sem warnings; testes verdes.
```
