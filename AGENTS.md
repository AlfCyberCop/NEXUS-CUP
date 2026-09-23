# NEXUS-CUP V1.0 — AGENTS.md

## Missão
Fechar a NEXUS-CUP V1.0 com alterações localizadas, baixo consumo de contexto e prioridade à estabilidade/entrega. Não expandir indefinidamente o produto.

## Arranque de sessão
1. Ler AGENTS.md.
2. Ler PRODUCT_SPEC.md.
3. Ler PROJECT_STATE.md.
4. Consultar docs/HANDOFF.md apenas se faltar detalhe técnico.
5. Ler apenas os ficheiros diretamente necessários à tarefa.
6. NÃO fazer scan global do repositório.

## STOP antes de mudanças grandes
Antes de uma alteração transversal significativa em BD + backend + frontend + testes, indicar brevemente impacto, componentes, complexidade e risco e aguardar autorização.

## Regras
- Uma tarefa de cada vez; menor alteração suficiente.
- Não refatorar código não relacionado.
- Confirmar primeiro se algo já existe.
- Não instalar/atualizar dependências sem necessidade.
- Não apagar dados/funcionalidade sem autorização.
- Preservar imutabilidade, histórico, auditoria e forense existentes.
- Máximo 1–2 testes diretamente relacionados por alteração.
- NÃO repetir as suites completas já PASS sem autorização explícita.
- Baseline aceite: 44 core/E2E + 9 regras + 14 UI = 67 PASS.
- André + Nexus + Zé fazem aceitação funcional; suite completa só por decisão explícita no freeze.
- Respostas curtas: alterações, testes, bloqueios.

## Autoridade
- André, conhecido como AlfCyberCop, supervisiona todo o projeto NEXUS-CUP e tem a decisão final sobre o trabalho.
- Em caso de conflito entre orientações de projeto do NEXUS e instruções explícitas de André / AlfCyberCop, prevalecem as de André / AlfCyberCop.
- Working tree única: E:\SW-CYBER\NEXUSCUP
- PostgreSQL aplicação: 5432.
- PostgreSQL testes: 55432.
- Porta 6666 excluída.
- Push/merge/release/publicação/distribuição externa só com autorização explícita.
- Operações destrutivas/difíceis de reverter exigem confirmação.

## Segurança
- Nunca expor passwords/chaves/segredos de .runtime ou testes.
- Password do instalador nunca em logs, relatório ou linha de comando visível.
- Não reutilizar BDs de teste como instalação inicial.
- Não prometer resistência absoluta da auditoria contra superuser/proprietário/admin SO.

## Prioridade V1.0
1. Liga formalmente FINALIZADA + cenário Super Auditor.
2. Bugs pequenos que prejudiquem fluxo principal.
3. Backup completo exclusivo SUPER.
4. Instalador GUI final / entrega / higiene.
5. Documentação/PDF.
6. Só depois melhorias não essenciais.

## Documentação
- PRODUCT_SPEC.md = especificação funcional.
- PROJECT_STATE.md = checkpoint atual.
- docs/HANDOFF.md = detalhe histórico/técnico.
- Atualizar PROJECT_STATE apenas após mudanças relevantes, não como diário.
