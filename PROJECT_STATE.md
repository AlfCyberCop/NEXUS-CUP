# NEXUS-CUP — PROJECT_STATE.md

## Release candidate atual
- Build atual: `NX15-20260920`.
- Objetivo: árvore única e coerente de frontend + PostgreSQL + instalador, substituindo os patches V6–V13.
- Aplicação: Node.js + HTML/CSS/JS + PostgreSQL.
- Produção prevista: PostgreSQL `localhost:5432`, BD `nexuscup`.

## Funcionalidade consolidada
- Agendamento com emparelhamento Casa/Visitante imutável pela jornada; data/hora e recinto editáveis.
- Recinto pode ser escolhido da lista ou criado na hora; mudança face ao previsto exige motivo auditável.
- Convocatórias Casa/Visitante separadas, com um único guarda-redes titular por equipa e 3–5 titulares validados na BD.
- Gestão de plantéis em `Clube -> Equipa -> Plantel`.
- Segurança/PSP só pode finalizar depois do jogo `FINALIZADO`, aplicado em UI, API e trigger PostgreSQL.
- Jogos/jornadas por cartões e cockpit NEXUS azul/navy com semáforos.
- Centro de Relatórios: resumo, classificação, resultados, jornadas, marcadores, disciplina, faltas, arbitragem, segurança, plantéis e integridade/auditoria para SUPER.
- Liga histórica formalmente `FINALIZADA`, classificação/campeão persistidos, operação normal bloqueada depois do fecho.
- Super Auditoria com revisão real de vermelho executada e tentativa real de alteração de resultado rejeitada/auditada.

## Contas do seed NX14
- AlfCyberCop: ADMIN + SUPER_AUDITOR; `mudar_password=true`.
- Paulo Ricardo Costa Ramalho: ADMIN + SUPER_AUDITOR; `mudar_password=true`.
- José Silva: OPERADOR; credencial permanente de demonstração; `mudar_password=false`.
- Adalberto Costa: OPERADOR + LEITOR; mesma credencial permanente; `mudar_password=false`.
- `app.super_autorizado`: exatamente Alf e Paulo.

## Instalador NX14
- Wizard GUI + fallback texto.
- Completa / Apenas BD / Apenas Aplicação.
- BD existente só é eliminada quando `REPOR BD` é confirmado explicitamente.
- Reinstalação reconhecida refresca os ficheiros do produto; não deixa frontend antigo no destino.
- Identificação de build por `BUILD.txt` e `/api/health` evita reutilizar processo de uma versão anterior.
- Relatório PDF continua não bloqueante se ainda não existir.

## Validação nesta sessão
- `node --check` nos módulos JS críticos: PASS.
- `tests/release-static.mjs`: 12/12 PASS.
- Não foi possível executar PostgreSQL nem PowerShell/WinForms neste contentor Linux; a aceitação real é feita no Windows com `INSTALAR.cmd -> Instalação Completa -> REPOR BD`.

## Depois da aceitação NX14
- Freeze funcional.
- Produção do relatório técnico/PDF final a partir da BD/código efetivamente aceites.
- GitHub e deployment/servidor ficam para a fase de publicação/deploy.


## NX15 — revisão de usabilidade e fecho histórico
- Plantéis por época; época FINALIZADA é só leitura no frontend e na API.
- Segurança com hub/atalho e semáforos clicáveis.
- Ocorrências com validação amigável e referência curta suportada.
- Super Auditoria redesenhada para leitura funcional, preservando detalhe técnico opcional.
