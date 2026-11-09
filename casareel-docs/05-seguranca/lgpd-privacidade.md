# Privacidade e LGPD

> Documento técnico-operacional, **não é parecer jurídico**. Revisar com advogado especializado em proteção de dados antes do lançamento.

## 1. Papéis

| Papel | Quem |
|---|---|
| Controlador | A empresa operadora do CasaReel |
| Operadores | Provedores de nuvem, e-mail, GPU, analytics (com contrato de tratamento de dados) |
| Titulares | Anfitriões (usuários), visitantes dos links, pessoas eventualmente presentes nas fotos |
| Encarregado (DPO) | Pessoa/canal designado e publicado no aviso de privacidade |

## 2. Inventário de dados

| Dado | Finalidade | Base legal (a confirmar) | Retenção | Sensível? |
|---|---|---|---|---|
| E-mail, nome, `apple_sub` | Conta e autenticação | Execução de contrato | Enquanto a conta existir | Não |
| Endereço do imóvel | Gestão do imóvel (privado) | Execução de contrato | Até exclusão do imóvel/conta | Não, mas de alto risco |
| Fotos e capturas do imóvel | Gerar vídeo/tour | Execução de contrato | Até exclusão pelo usuário (+ backups) | Pode conter pessoas |
| Vídeos/tours gerados | Entrega do serviço | Execução de contrato | Idem | — |
| Dados de assinatura | Cobrança e entitlements | Execução de contrato; obrigação legal (fiscal) | Conforme prazo legal | Não |
| IP (hash), user agent, device id | Segurança e antifraude | Legítimo interesse | 90 dias (sessões), 13 meses (auditoria) | Não |
| Telemetria de uso (opcional) | Melhoria do produto | Consentimento ou legítimo interesse (avaliar) | 13 meses | Não |
| Fotos para treinar IA | Melhoria de modelos | **Consentimento específico** (`ai_improvement`) | Até revogação | Pode conter pessoas |
| Reports de moderação | Segurança da plataforma | Legítimo interesse / obrigação legal | Conforme necessidade legal | Possível |

Evitar na Fase 1: CPF, documentos, localização precisa do dispositivo, dados de crianças, dados sensíveis (saúde, biometria, etc.).

## 3. Direitos dos titulares (art. 18) — implementação

| Direito | Como atender |
|---|---|
| Confirmação e acesso | Tela "Meus dados" + endpoint de exportação (JSON + links temporários dos arquivos) |
| Correção | Edição do perfil/imóvel no app |
| Anonimização, bloqueio ou eliminação | Exclusão de conta com carência de 7 dias e pipeline `purge_user` |
| Portabilidade | Exportação em formato aberto (JSON/ZIP) |
| Informação sobre compartilhamento | Lista de operadores no aviso de privacidade |
| Revogação de consentimento | Toggle por finalidade; efeito imediato; registro em `consents` |
| Oposição/revisão | Canal do DPO; resposta em prazo legal |

SLA interno: responder a solicitações em até **15 dias** (referência da LGPD para acesso/confirmação).

## 4. Privacidade por design — regras de engenharia

1. **Minimização:** só coletar o que a funcionalidade exige.
2. **Remoção de EXIF/GPS** no cliente e no servidor.
3. **Endereço exato cifrado**; exibir publicamente apenas cidade/bairro escolhido.
4. **Share links** com expiração e revogação; padrão "não listado", nunca indexável (`X-Robots-Tag: noindex`).
5. **Pessoas nas fotos:** aviso ao usuário e opção de borrar rostos (IA-05); termos exigem que o anfitrião tenha direito de uso das imagens e autorização das pessoas retratadas.
6. **Sem venda de dados**; sem SDKs de publicidade; sem tracking entre apps (ATT não necessário).
7. **IA:** treinar apenas com consentimento explícito e revogável; separar dados de treino dos de produção; permitir retirada.
8. **Logs sem PII** e retenção limitada.
9. **Transferência internacional:** se usar nuvem fora do Brasil, documentar salvaguardas (cláusulas contratuais, país adequado) e informar no aviso.
10. **Menores:** o app é destinado a maiores de 18 anos; classificação etária apropriada na App Store; bloquear cadastro de menores quando identificado.

## 5. Documentos a produzir (jurídico + produto)

| Documento | Conteúdo mínimo |
|---|---|
| Aviso de Privacidade | Quem somos, dados, finalidades, bases legais, compartilhamentos, retenção, direitos, DPO, transferências |
| Termos de Uso | Titularidade das imagens, conduta, conteúdo proibido, limitação de responsabilidade, assinatura e reembolso |
| Política de Conteúdo/Moderação | O que é proibido, denúncia, remoção, contestação |
| RIPD (relatório de impacto) | Fotos de interiores, endereço, IA, Fase 3 (marketplace) |
| Registro das operações de tratamento (ROPA) | Inventário da seção 2 |
| Contratos com operadores (DPA) | Nuvem, e-mail, GPU, analytics |
| Plano de resposta a incidentes | Ver `controles-de-seguranca.md` |
| Política de retenção e descarte | Tabelas de retenção do `guia-dba.md` |

## 6. Requisitos da App Store relacionados

- Opção de **excluir a conta dentro do app** (obrigatória)
- Revogar token do Sign in with Apple ao excluir a conta
- Rótulos de privacidade corretos e `PrivacyInfo.xcprivacy`
- Link para política de privacidade no app e na ficha
- Divulgação clara de assinaturas (preço, renovação, como cancelar), restaurar compras
- Conteúdo gerado pelo usuário: mecanismos de denúncia, bloqueio e moderação (relevante a partir da Fase 3 e para links públicos)

## 7. Retenção — resumo

| Dado | Prazo |
|---|---|
| Conta ativa | Enquanto ativa |
| Conta excluída | Purga em até 30 dias após a carência; backups expiram em até 35 dias |
| Sessões | 30 dias após expirar |
| Auditoria | 13 meses |
| Cobrança | 5 anos (verificar com contabilidade) |
| Uploads rejeitados | 30 dias |
| Dados de treino com consentimento | Até revogação |

## 8. Checklist de conformidade

- [ ] DPO/canal definido e publicado
- [ ] Inventário (ROPA) e RIPD concluídos
- [ ] Avisos e termos revisados pelo jurídico
- [ ] Consentimentos granulares com versão e registro
- [ ] Exportação e exclusão testadas de ponta a ponta
- [ ] Contratos com operadores assinados
- [ ] Retenção automatizada e auditada
- [ ] Plano de incidentes com fluxo de comunicação à ANPD
