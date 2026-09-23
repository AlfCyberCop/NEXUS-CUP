# NEXUS-CUP V1.0 — PRODUCT_SPEC.md

## Produto
Aplicação para gerir e demonstrar uma competição/liga de futsal: clubes/plantéis, competição, jogo, arbitragem, segurança/policiamento, homologação, autenticação/RBAC, auditoria e Super Auditoria.

## V1.0 já existente — NÃO REIMPLEMENTAR
Clubes/equipas/pessoas/plantéis; época/jornadas/recintos/jogos; convocatórias e eventos; regras já implementadas; arbitragem; segurança/policiamento; homologação/readiness; retificações suportadas; autenticação/RBAC; auditoria/forense/Super Auditor; relatórios operacionais; GUI.

## Liga completa e formalmente encerrada
Fluxo:
criação -> jornadas/jogos -> finalização -> segurança finalizada -> homologação -> classificação final -> campeão -> FINALIZADA

Requisitos:
- Só finalizar quando todos os jogos aplicáveis estiverem homologados.
- Guardar/apresentar classificação final e campeão de forma coerente com a modelação existente.
- FINALIZADA bloqueia operação normal.
- Mecanismos extraordinários controlados/auditáveis continuam possíveis.
- Fazer a menor extensão possível; NÃO redesenhar competição.

## Super Auditoria obrigatória sobre Liga FINALIZADA
### Manipulação de cartão vermelho
Criar um incidente REAL através dos mecanismos normais/controlados da aplicação/BD, não por INSERT falso nas tabelas de auditoria. O Super Auditor deve conseguir reconstruir jogo, autor/contexto disponível, instante, valor/estado anterior, alteração e cadeia/eventos de auditoria.

### Tentativa de manipulação do resultado
Executar uma tentativa REAL de alterar o resultado oficial de jogo fechado/homologado. Deve ser BLOQUEADA pela integridade/autorização e a tentativa deve ficar auditável/drilldown. Não fabricar incidente manualmente.

Apresentação pretendida: Liga FINALIZADA, jogos 100% homologados, classificação final/campeão, dois incidentes críticos, cartão vermelho DETETADO/reconstruível, tentativa de resultado BLOQUEADA, cadeia ÍNTEGRA.

## Segurança/policiamento
Fluxo V1.0 já considerado funcional:
preparar -> responsável/efetivos -> iniciar -> ocorrências -> finalizar + avaliação -> homologação.
Não transformar em sistema policial completo.

## Backup completo — SUPER
Adicionar Administração -> Base de Dados -> Backup completo.
- Exclusivo a SUPER (usar autoridade coerente com RBAC existente).
- Backup PostgreSQL REAL com pg_dump, preferencialmente formato custom -Fc.
- Nome sugerido: NEXUSCUP_FULL_YYYY-MM-DD_HHMMSS.dump.
- Registar/auditar quem, quando e qual BD.
- Nunca registar password nem conteúdo do dump.
- Não criar GUI Restore automaticamente na V1.0.
- Documentar posteriormente restore com pg_restore.
- SUPER é autoridade extraordinária auditável, não bypass silencioso.

## INSTALADOR GUI V1.0 — SUBSTITUI A EXPERIÊNCIA ATUAL
O instalador final TEM DE TER GUI/wizard. Reutilizar a lógica segura já existente em installer/ (install.mjs, PowerShell/DPAPI, validações) sempre que possível; NÃO reconstruir a BD nem duplicar SQL.

Duplo clique em INSTALAR.cmd deve abrir a GUI, não um fluxo de perguntas em consola.

### Ecrã 1 — Bem-vindo
NEXUS-CUP V1.0.

### Ecrã 2 — Tipo
A) Instalação Completa — Aplicação + BD completa + componentes necessários + relatório.
B) Apenas Base de Dados — BD NEXUS-CUP COMPLETA + relatório.
C) Apenas Aplicação — aplicação configurada para uma BD NEXUS-CUP existente + relatório.

### Ecrã 3 — destino/configuração
Destino predefinido: C:\temp\NEXUSCUP, alterável por Procurar.

Configuração PostgreSQL com defaults alteráveis:
- servidor/host (localhost por defeito)
- porta (5432)
- nome BD (nexuscup)
- utilizador
- password mascarada

A password é pedida quando necessária; nunca aparece em logs, relatório ou linha de comando visível.

Em Apenas Aplicação:
- permitir host/IP remoto;
- botão Testar ligação;
- só avançar depois de validar ligação e compatibilidade com uma BD NEXUS-CUP.

Em Apenas BD:
- instalar a BD COMPLETA, não versão reduzida;
- incluir schemas, tabelas, constraints, funções/procedures, triggers, views, auditoria/forense, roles/permissões, estrutura de utilizadores e seed essencial;
- ficar pronta para uma aplicação local ou remota posterior.

Instalação Completa combina os dois fluxos de forma coerente.

### Ecrã 4 — confirmação
Resumo do que será instalado/configurado + disclaimer curto sobre credenciais e uso autorizado. Nunca mostrar password.

### Ecrã 5 — progresso
GUI com barra/estado e mensagens simples; não despejar SQL/segredos no ecrã.

### Ecrã 6 — concluído
- Abrir NEXUS-CUP (quando houver aplicação).
- Abrir Relatório Técnico.
- Em Apenas BD, apenas relatório/fechar conforme aplicável.

### Relatório obrigatório
Nos TRÊS modos instalar:
NEXUS-CUP V1.0 - Relatório Técnico.pdf
diretamente acessível no diretório de instalação.

### Fonte única da BD
Usar os SQL oficiais do projeto em database/. O instalador não deve criar uma segunda arquitetura/modelo paralelo.

### Remoto
Arquitetura deve aceitar PostgreSQL remoto. Não é obrigatório automatizar configuração do servidor remoto (listen_addresses/pg_hba/firewall) para fechar V1.0.

## Relatório final
Um único relatório académico/técnico:
NEXUS-CUP V1.0 - Relatório Técnico.pdf
Nexus produzirá o documento final após freeze usando a BD/código finais. Não gastar contexto Codex a escrever prosa extensa agora.

## Fora do âmbito automático
Não implementar sem autorização: ERP/federação completa, disciplina avançada entre jogos, transferências avançadas, sistema policial/forense documental completo, cadeia de custódia binária, recuperação/admin universal, auditoria universal PostgreSQL, novas regras raras que impliquem redesenho transversal, GUI Restore.
