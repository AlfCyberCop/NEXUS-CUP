# NEXUS-CUP V1.0

Projeto de gestão de competições de futsal: clubes e plantéis, jogos e eventos, arbitragem, segurança, classificação, autenticação e Super Auditoria.

Aplicação Node.js com interface HTML/CSS/JavaScript e base de dados PostgreSQL.

## Instalação Windows

1. Disponibilizar Node.js e PostgreSQL.
2. Instalar as dependências: `npm ci --omit=dev`.
3. Executar `INSTALAR.cmd` e seguir o assistente: instalação completa, apenas BD ou apenas aplicação.
4. Na pasta instalada, executar `INICIAR.cmd`.

O assistente configura a ligação e protege as credenciais locais com DPAPI. Os scripts SQL oficiais estão em `database/`.

## Estrutura

| Pasta | Conteúdo |
| --- | --- |
| `backend/` | Servidor HTTP e configuração |
| `frontend/` | Interface da aplicação |
| `database/` | Schema, integridade, motor, API e dados de demonstração |
| `installer/` | Assistente Windows e instalação da base de dados |
| `tests/` | Verificações estáticas, testes de regras, integração e interface |
| `docs/` | Relatório técnico entregue e histórico técnico |

[Relatório técnico entregue](<docs/NEXUS-CUP V1.0 - Relatório Técnico.pdf>)

Especificação funcional: [PRODUCT_SPEC.md](PRODUCT_SPEC.md). Orientações de manutenção: [AGENTS.md](AGENTS.md).

## Verificações

`npm run test:static` executa as verificações estáticas existentes. Os testes de integração e interface requerem o ambiente PostgreSQL de testes configurado.

## Histórico

A versão entregue está preservada no commit `6fcb180`. As instruções antigas de aplicação de patches e os documentos provisórios foram retirados da árvore atual; continuam disponíveis no histórico Git.

Esta limpeza organiza os ficheiros versionados. Não publica alterações funcionais locais nem altera a instalação em produção.
