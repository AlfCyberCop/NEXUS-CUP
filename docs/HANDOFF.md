# Handoff técnico — NEXUS-CUP V1.0

## Instrução vigente e estado de entrega

O utilizador mandou parar imediatamente pesquisas, testes e alterações funcionais, manter o código/testes atuais e gastar o restante trabalho apenas no relatório/handoff. **Não retomar implementação nem repetir testes sem nova instrução do utilizador.** Este documento não constitui autorização para continuar.

Relatório completo: [RELATORIO_FINAL.md](RELATORIO_FINAL.md). A execução terminou com 67 verificações aprovadas nas três últimas suites, mas com limitações explícitas; não foi declarada prontidão global.

## Autoridade permanente

- Única working tree: `E:\SW-CYBER\NEXUSCUP`.
- Árvores VFINAL, NEXUS-CUP, NEXUS-CUP-1UPLOAD e outras variantes: apenas leitura; não arrancar produtos/clusters a partir delas.
- Porta 6666 absolutamente excluída: nenhuma conexão, discovery, configuração, arranque ou paragem.
- PostgreSQL da aplicação: 5432. PostgreSQL de testes: 55432.
- Não deploy/push/merge/release/publicação nem alteração de infraestrutura externa.
- Não copiar pgdata, logs, dependências ou segredos anteriores.

## Implementação existente

1. `database/01_schema.sql`: 35 tabelas, nove schemas, constraints/FK.
2. `database/02_integrity.sql`: auditoria, cifra/cadeia, temporalidade, guards, views, readiness.
3. `database/03_engine.sql`: trigger de evento, efeitos desportivos, homologação e simulação.
4. `database/04_api.sql`: comando de negócio, RPC autenticado, login e health.
5. `database/05_seed.sql`: quatro equipas, histórico completo de 12 jogos, operacional de 12 jogos; exatamente um agendado no baseline.
6. `backend/server.js`: HTTP local; role PG runtime sem acesso direto às tabelas; cookie de sessão; comandos via funções DB.
7. `frontend/`: HTML/CSS/JS sem framework; sidebar clara, cockpit de cinco separadores, formulários por contexto.
8. `installer/`: aplicação transacional do baseline, criação de role runtime, validação interna e wrappers PowerShell/DPAPI.

Não houve cópia integral de código legado. Foram reaproveitados conceitos e direção visual. `docs/reference-inventory.json` contém hashes/timestamps de 22 fontes antigas. Último SQL antigo modificado observado: `08_liga_placard_2025_26.sql`, UTC 2026-09-20 14:11:36.570; não foi recuperado log da sessão antiga que prove o último comando.

## Estado operacional no momento da paragem

- Cluster novo foi iniciado em `E:\SW-CYBER\NEXUSCUP\.test_pgdata`, exclusivamente em 55432, log `.test_pg.log` da mesma pasta.
- **Último estado conhecido: cluster ainda iniciado.** Não foi feito novo status nem comando de paragem depois do STOP.
- Servidores HTTP e browsers abertos pelas suites finais foram encerrados nos blocos `finally`; os respetivos comandos terminaram com exit code 0.
- Não foi instalada nem iniciada a aplicação de produção em 5432.
- Há várias BDs temporárias criadas nas tentativas. Não foram eliminadas. As mais recentes BDs de E2E/regras e UI contêm mutações de teste e não representam uma instalação virgem.
- `.runtime/test.json`: configuração do cluster/BD para suites principal e regras. `.runtime/ui.json`: configuração da última instalação isolada usada pela UI. **Contêm passwords de roles PG e chaves forenses temporárias. Não imprimir, anexar, commitar ou distribuir.** Foram geradas nesta execução, não copiadas das árvores antigas.
- `.runtime/config.dpapi` é o destino previsto para produção, não deve ser presumido existente/validado.
- As passwords dos administradores nas BDs de teste foram alteradas pelo E2E/UI; não reutilizar essas BDs como entrega inicial. O seed mantém hashes das credenciais temporárias requeridas e mudança obrigatória.
- PostgreSQL de testes foi criado com autenticação trust local para o ensaio. Não converter esta configuração em produção.

## Evidência já existente — não repetir agora

| Artefacto | Resultado |
|---|---|
| `test-results/results.json` | 44 PASS, 0 FAIL; BD `nexuscup_test_1789915911889`; UTC 2026-09-20 14:51:58.201Z |
| `test-results/rules.json` | 9 PASS, 0 FAIL; executado depois da suite principal na mesma configuração |
| `test-results/ui.json` | 14 PASS, 0 FAIL; instalação nova separada e browser real |
| `test-results/ui/dashboard.png` | Captura do dashboard |
| `test-results/ui/cockpit.png` | Captura do cockpit |
| `test-results/ui/super-auditoria.png` | Captura do drilldown |

Pode haver `failure.png` de execução anterior, entretanto corrigida. Não tomar esse ficheiro como estado final. Leitura PowerShell sem `-Encoding UTF8` pode apresentar mojibake no terminal; os fontes/documentos foram gravados em UTF-8. Não concluir corrupção do ficheiro apenas pela renderização do terminal.

As suites cobrem um E2E real completo pela API, testes DB positivos/negativos, concorrência, 4×4/5×3/4×3/3×3, expulsão de suplente, golo em inferioridade, dois minutos efetivos, menos de três jogadores, autenticação/RBAC, acesso negado, retificações, histórico e integridade forense. A UI percorreu o fluxo visível até retificação/drilldown sem erros JS.

## Comandos existentes, apenas para referência futura

Não executar enquanto a ordem de STOP estiver vigente.

```text
node tests/bootstrap.mjs
node tests/run.mjs
node tests/rules.mjs
node tests/ui.mjs
```

`bootstrap.mjs` exige o cluster novo em 55432, verifica `data_directory`, cria uma BD com nome temporal e substitui `.runtime/test.json`; não apaga BDs anteriores. `run.mjs` e `rules.mjs` não são idempotentes na mesma BD já alterada: dependem dos estados iniciais/contas e mudam passwords. `ui.mjs` cria outra instalação isolada chamando `installer/install.mjs`.

As suites de login esperam `NEXUS_BOOTSTRAP_PASSWORD` no ambiente do processo. Não gravar a password num ficheiro nem acrescentá-la ao relatório. A credencial inicial foi fornecida pelo utilizador na conversa; o SQL guarda apenas hash bcrypt. `npm test` atual executa só `tests/run.mjs`, não prepara cluster nem corre todas as suites.

O arranque do cluster exigiu uma autorização sandbox e foi permitido apenas para o pgdata canónico. Se houver autorização futura para limpeza/paragem, usar o binário PostgreSQL e `-D` desta árvore; nunca reutilizar caminhos das outras cópias. O binário de plataforma disponível nesta execução foi `E:\SW-CYBER\Postgres\bin\pg_ctl.exe`; o produto não depende de outra árvore NEXUS-CUP.

Dependências: Node 22+ previsto pelo instalador; execução observada em Node 24.18.0; `pg` 8.16.3; dev dependency `playwright-core` 1.58.2 no lockfile. Browser do ensaio: Microsoft Edge instalado no sistema, headless. O plugin Browser não encontrou browsers disponíveis; foi consultada a skill e o troubleshooting antes de usar o runner local.

## Pontos técnicos importantes para continuação autorizada

- `app.rpc` trata erros sem propagar exceção ao backend; o backend confirma a transação do resultado de erro, conservando evidência. Não adicionar rollback indiscriminado para resultados HTTP 409/403.
- `app.command` usa `#variable_conflict use_column`. Já houve falha por ambiguidade da variável record `x` e aliases; considerar renomeação futura com testes dirigidos.
- Eventos são imutáveis. Golo corrigido usa `jogo.revisao`; resultado oficial usa nova linha/versão. Não apagar ou renumerar eventos.
- `jogo.emitir` é comum à operação manual e simulação. O segundo amarelo gera evento distinto de expulsão; redução pertence à equipa. Reposição é evento explícito com suplente e autorização de cronometrista/terceiro árbitro.
- Auditoria forense tem lock global; evitar preparar duas transações que aguardem mutuamente esse lock antes de poderem fazer commit. O teste de concorrência foi corrigido preparando pessoas/vínculos antes da disputa temporal.
- `app.has_role(...,'SUPER_AUDITOR')` exige role e presença em `app.super_autorizado`; admin normal não passa. A role runtime só recebe EXECUTE de `rpc`, `login` e `health` e USAGE de app.
- O instalador recusa BD existente e não a apaga. O wrapper PowerShell não foi ensaiado integralmente; o instalador Node foi executado várias vezes com BD nova em 55432.
- UI: o helper `select` passou a usar `label for`/id para rótulos acessíveis. O teste de transição entre intenção e diálogo de retificação espera o novo heading, não um intervalo escondido do modal.
- Não há ancoragem externa da cadeia; não prometer resistência absoluta a superuser/proprietário/administrador SO.

## Pendências prioritárias, sem autorização para as executar agora

1. Confirmar edição FIFA/FPF aplicável à época operacional. Só FIFA 2025/26 ficou efetivamente consultada; consequências disciplinares FPF entre jogos e regulamentação 2026/27 estão PENDENTES.
2. Processos/sanções/suspensões entre jogos; sexta falta e execução dos livres; fim de período com remates pendentes; timeout/prolongamento/desempate; casos de guarda-redes e expulsão pré-início não estão completos.
3. Retificação de eventos além de golos, replay/coerência desportiva e UI de correção de recinto/arbitragem pós-fecho.
4. Vínculo para pessoa existente/recontratação/transferência; gestão de treinadores; edição UI de contactos atualmente começa com campos vazios e pode apagar valores existentes.
5. Reagendamento bloqueado por nomeações/convocatórias: completar fluxo de revisão e remoção de nomeações.
6. Administração de roles/desativação/recuperação; normalização mais rica de envolvidos/evidências e avaliação da força; relatórios dedicados de arbitragem.
7. Formulário de retificação rejeitada pode ficar aberto com intenção já encerrada. Coloração de algumas pendências/estado homologado ainda merece revisão.
8. Documentação académica extensa, catálogo extraído da BD, censo final e auditoria exaustiva de paths/permissões.
9. Ensaiar duplo clique/DPAPI/arranque em 5432, apenas quando existirem credenciais e autorização para continuação. Não declarar esses passos executados por causa do PASS do instalador Node isolado.
10. Higiene/empacotamento: parar e tratar cluster de testes, excluir `.runtime`, logs, node_modules e pgdata da distribuição. Não apagar as árvores antigas.

Nenhuma destas pendências foi corrigida após o STOP. O código e os testes foram conservados como solicitado.

## Reconfirmação do fecho — 20 de setembro de 2026

- STOP reiterado pelo utilizador: não pesquisar, testar ou alterar funcionalidades. Nesta passagem apenas se consultou a documentação de arranque/estado e se acrescentaram notas ao relatório e a este handoff.
- Relatório de fecho: `docs/RELATORIO_FINAL.md`, incluindo a secção 25. Os 67 PASS são resultados históricos documentados; não houve nova execução nem leitura dos artefactos de teste nesta passagem.
- `PRODUCT_SPEC.md` define o âmbito funcional atual. `PROJECT_STATE.md` regista como pendentes Liga FINALIZADA/classificação/campeão, os dois incidentes reais de Super Auditoria sobre essa Liga, backup completo SUPER, instalador GUI de três modos e PDF técnico. Não assumir que a evidência histórica de jogos homologados/retificações demonstra o cumprimento desses requisitos posteriores.
- FIFA/FPF: edição aplicável e regras sem validação documentada continuam PENDENTES, incluindo disciplina entre jogos e casos especiais enumerados acima. Nenhuma fonte foi novamente consultada.
- Estado operacional não revalidado: cluster de testes apenas conhecido historicamente como iniciado em 55432. Não houve arranque, paragem, limpeza ou consulta de processos/BD neste fecho.
- Nenhuma alteração a código, testes, dependências ou configuração; nenhuma publicação externa. PROJECT_STATE.md foi preservado, porque não houve mudança funcional.
- Noutra sessão, ler AGENTS.md, PRODUCT_SPEC.md e PROJECT_STATE.md; usar este handoff para contexto técnico. Aguardar nova instrução antes de retomar trabalho funcional ou testes; respeitar STOP para mudanças transversais significativas.
