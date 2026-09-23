BEGIN;
CREATE EXTENSION IF NOT EXISTS pgcrypto;
CREATE SCHEMA app;
CREATE SCHEMA nucleo;
CREATE SCHEMA clubes;
CREATE SCHEMA competicao;
CREATE SCHEMA jogo;
CREATE SCHEMA seguranca;
CREATE SCHEMA arbitragem;
CREATE SCHEMA auditoria;
CREATE SCHEMA forense;
CREATE TABLE app.versao (versao text PRIMARY KEY, produto text NOT NULL, instalado_em timestamptz NOT NULL DEFAULT now());
INSERT INTO app.versao VALUES ('V1.0','NEXUS-CUP',now());
CREATE TABLE nucleo.pessoa (id integer GENERATED ALWAYS AS IDENTITY PRIMARY KEY,nome text NOT NULL CHECK(length(trim(nome))>=5),nif text UNIQUE CHECK(nif ~ '^[0-9]{9}$'),email text,telefone text);
CREATE UNIQUE INDEX pessoa_email ON nucleo.pessoa(lower(email)) WHERE email IS NOT NULL;
CREATE TABLE competicao.recinto (id integer GENERATED ALWAYS AS IDENTITY PRIMARY KEY,nome text NOT NULL UNIQUE,cidade text NOT NULL,capacidade integer NOT NULL CHECK(capacidade>0));
CREATE TABLE clubes.clube (id integer GENERATED ALWAYS AS IDENTITY PRIMARY KEY,nome text NOT NULL UNIQUE);
CREATE TABLE clubes.equipa (id integer GENERATED ALWAYS AS IDENTITY PRIMARY KEY,clube_id integer NOT NULL REFERENCES clubes.clube,nome text NOT NULL UNIQUE,categoria text NOT NULL DEFAULT 'SENIOR',recinto_id integer NOT NULL REFERENCES competicao.recinto);
CREATE TABLE clubes.vinculo (id integer GENERATED ALWAYS AS IDENTITY PRIMARY KEY,equipa_id integer NOT NULL REFERENCES clubes.equipa,pessoa_id integer NOT NULL REFERENCES nucleo.pessoa,funcao text NOT NULL CHECK(funcao IN ('JOGADOR','TREINADOR')),inicio date NOT NULL,fim date,CHECK(fim IS NULL OR fim>=inicio),UNIQUE(id,equipa_id,pessoa_id));
CREATE TABLE clubes.camisola (id integer GENERATED ALWAYS AS IDENTITY PRIMARY KEY,vinculo_id integer NOT NULL REFERENCES clubes.vinculo,equipa_id integer NOT NULL REFERENCES clubes.equipa,numero smallint NOT NULL CHECK(numero BETWEEN 1 AND 99),inicio date NOT NULL,fim date,CHECK(fim IS NULL OR fim>=inicio));
CREATE TABLE competicao.epoca (id integer GENERATED ALWAYS AS IDENTITY PRIMARY KEY,nome text NOT NULL UNIQUE,designacao text NOT NULL,inicio date NOT NULL,fim date NOT NULL,CHECK(fim>inicio),regulamento text NOT NULL DEFAULT 'NEXUS V1.0: liga sénior, ida/volta; 3/1/0 pontos; FIFA 2025/26');
CREATE TABLE competicao.inscricao (epoca_id integer REFERENCES competicao.epoca,equipa_id integer REFERENCES clubes.equipa,PRIMARY KEY(epoca_id,equipa_id));
CREATE TABLE competicao.jornada (id integer GENERATED ALWAYS AS IDENTITY PRIMARY KEY,epoca_id integer NOT NULL REFERENCES competicao.epoca,numero integer NOT NULL CHECK(numero>0),UNIQUE(epoca_id,numero),UNIQUE(id,epoca_id));
CREATE TABLE competicao.jogo (
 id integer GENERATED ALWAYS AS IDENTITY PRIMARY KEY,epoca_id integer NOT NULL REFERENCES competicao.epoca,jornada_id integer NOT NULL,casa_id integer NOT NULL,fora_id integer NOT NULL,
 inicio timestamptz,recinto_esperado integer NOT NULL REFERENCES competicao.recinto,recinto_id integer REFERENCES competicao.recinto,motivo_recinto text,
 estado text NOT NULL DEFAULT 'NAO_AGENDADO' CHECK(estado IN ('NAO_AGENDADO','AGENDADO','ADIADO','EM_CURSO','INTERROMPIDO','FINALIZADO','HOMOLOGADO','CANCELADO')),
 periodo smallint NOT NULL DEFAULT 1 CHECK(periodo IN (1,2)),segundos integer NOT NULL DEFAULT 0 CHECK(segundos BETWEEN 0 AND 1200),intervalo boolean NOT NULL DEFAULT false,
 CHECK(casa_id<>fora_id),UNIQUE(epoca_id,casa_id,fora_id),FOREIGN KEY(jornada_id,epoca_id) REFERENCES competicao.jornada(id,epoca_id),
 FOREIGN KEY(epoca_id,casa_id) REFERENCES competicao.inscricao,FOREIGN KEY(epoca_id,fora_id) REFERENCES competicao.inscricao,
 CHECK(estado IN ('NAO_AGENDADO','CANCELADO') OR (inicio IS NOT NULL AND recinto_id IS NOT NULL)),
 CHECK(estado NOT IN ('FINALIZADO','HOMOLOGADO') OR (periodo=2 AND segundos=1200 AND NOT intervalo))
);
CREATE TABLE jogo.convocado (id integer GENERATED ALWAYS AS IDENTITY PRIMARY KEY,jogo_id integer NOT NULL REFERENCES competicao.jogo,vinculo_id integer NOT NULL REFERENCES clubes.vinculo,camisola_id integer NOT NULL REFERENCES clubes.camisola,equipa_id integer NOT NULL REFERENCES clubes.equipa,pessoa_id integer NOT NULL REFERENCES nucleo.pessoa,numero smallint NOT NULL CHECK(numero BETWEEN 1 AND 99),titular boolean NOT NULL,goleiro boolean NOT NULL DEFAULT false,estado text NOT NULL CHECK(estado IN ('EM_CAMPO','BANCO','EXPULSO')),UNIQUE(jogo_id,pessoa_id),UNIQUE(jogo_id,equipa_id,numero),UNIQUE(id,jogo_id));
CREATE TABLE jogo.evento (id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,jogo_id integer NOT NULL REFERENCES competicao.jogo,seq integer NOT NULL,periodo smallint NOT NULL CHECK(periodo IN (1,2)),segundos integer NOT NULL CHECK(segundos BETWEEN 0 AND 1200),tipo text NOT NULL CHECK(tipo IN ('INICIO','INTERVALO','SEGUNDA_PARTE','FIM','RELOGIO','GOLO','FALTA','AMARELO','VERMELHO_DIRETO','EXPULSAO_SEGUNDO_AMARELO','SUBSTITUICAO','REPOSICAO','INTERRUPCAO','RETOMA')),equipa_id integer REFERENCES clubes.equipa,jogador_id integer,entra_id integer,relacionado_id bigint REFERENCES jogo.evento,incidente uuid NOT NULL DEFAULT gen_random_uuid(),detalhe jsonb NOT NULL DEFAULT '{}',criado_em timestamptz NOT NULL DEFAULT clock_timestamp(),UNIQUE(jogo_id,seq),FOREIGN KEY(jogador_id,jogo_id) REFERENCES jogo.convocado(id,jogo_id),FOREIGN KEY(entra_id,jogo_id) REFERENCES jogo.convocado(id,jogo_id));
CREATE TABLE jogo.reducao (id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,jogo_id integer NOT NULL REFERENCES competicao.jogo,equipa_id integer NOT NULL REFERENCES clubes.equipa,evento_id bigint NOT NULL UNIQUE REFERENCES jogo.evento,inicio integer NOT NULL CHECK(inicio BETWEEN 0 AND 2400),libertada_em integer,causa text,entrada_evento bigint UNIQUE REFERENCES jogo.evento,CHECK(libertada_em IS NULL OR libertada_em>=inicio));
CREATE TABLE jogo.revisao (id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,evento_id bigint NOT NULL REFERENCES jogo.evento,valido boolean NOT NULL,motivo text NOT NULL CHECK(length(trim(motivo))>=5),utilizador_id integer NOT NULL,criado_em timestamptz NOT NULL DEFAULT clock_timestamp());
CREATE TABLE competicao.resultado (id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,jogo_id integer NOT NULL REFERENCES competicao.jogo,versao integer NOT NULL CHECK(versao>0),casa integer NOT NULL CHECK(casa>=0),fora integer NOT NULL CHECK(fora>=0),motivo text NOT NULL,utilizador_id integer NOT NULL,criado_em timestamptz NOT NULL DEFAULT clock_timestamp(),UNIQUE(jogo_id,versao));
CREATE TABLE arbitragem.oficial (pessoa_id integer PRIMARY KEY REFERENCES nucleo.pessoa);
CREATE TABLE arbitragem.nomeacao (id integer GENERATED ALWAYS AS IDENTITY PRIMARY KEY,jogo_id integer NOT NULL REFERENCES competicao.jogo,pessoa_id integer NOT NULL REFERENCES arbitragem.oficial,funcao text NOT NULL CHECK(funcao IN ('ARBITRO','SEGUNDO_ARBITRO','CRONOMETRISTA','TERCEIRO_ARBITRO')),UNIQUE(jogo_id,funcao),UNIQUE(jogo_id,pessoa_id));
CREATE TABLE seguranca.entidade (id integer GENERATED ALWAYS AS IDENTITY PRIMARY KEY,nome text NOT NULL UNIQUE,tipo text NOT NULL CHECK(tipo IN ('PSP','GNR','PRIVADA')));
CREATE TABLE seguranca.agente (pessoa_id integer PRIMARY KEY REFERENCES nucleo.pessoa,entidade_id integer NOT NULL REFERENCES seguranca.entidade);
CREATE TABLE seguranca.operacao (id integer GENERATED ALWAYS AS IDENTITY PRIMARY KEY,jogo_id integer NOT NULL UNIQUE REFERENCES competicao.jogo,estado text NOT NULL DEFAULT 'PLANEADA' CHECK(estado IN ('PLANEADA','EM_CURSO','FINALIZADA')),responsavel_id integer REFERENCES seguranca.agente,inicio timestamptz,fim timestamptz,avaliacao text,CHECK(estado<>'FINALIZADA' OR (fim IS NOT NULL AND length(trim(avaliacao))>=5 AND responsavel_id IS NOT NULL)));
CREATE TABLE seguranca.efetivo (operacao_id integer REFERENCES seguranca.operacao,agente_id integer REFERENCES seguranca.agente,PRIMARY KEY(operacao_id,agente_id));
CREATE TABLE seguranca.ocorrencia (id integer GENERATED ALWAYS AS IDENTITY PRIMARY KEY,operacao_id integer NOT NULL REFERENCES seguranca.operacao,instante timestamptz NOT NULL DEFAULT clock_timestamp(),descricao text NOT NULL CHECK(length(trim(descricao))>=5),envolvidos text NOT NULL,evidencia text NOT NULL,sha256 text NOT NULL CHECK(sha256 ~ '^[a-f0-9]{64}$'),feridos integer NOT NULL DEFAULT 0 CHECK(feridos>=0),assistencia text,uso_forca boolean NOT NULL DEFAULT false,justificacao_forca text,CHECK(NOT uso_forca OR length(trim(justificacao_forca))>=5),CHECK(feridos=0 OR length(trim(assistencia))>=3));
CREATE TABLE seguranca.correcao (id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,operacao_id integer NOT NULL REFERENCES seguranca.operacao,ocorrencia_id integer REFERENCES seguranca.ocorrencia,texto text NOT NULL CHECK(length(trim(texto))>=5),utilizador_id integer NOT NULL,criado_em timestamptz NOT NULL DEFAULT clock_timestamp());
CREATE TABLE app.utilizador (id integer GENERATED ALWAYS AS IDENTITY PRIMARY KEY,nome text NOT NULL,email text NOT NULL,password_hash text NOT NULL,mudar_password boolean NOT NULL DEFAULT true,ativo boolean NOT NULL DEFAULT true);
CREATE UNIQUE INDEX utilizador_email ON app.utilizador(lower(email));
CREATE TABLE app.role (codigo text PRIMARY KEY);
INSERT INTO app.role VALUES('ADMIN'),('OPERADOR'),('LEITOR'),('SUPER_AUDITOR');
CREATE TABLE app.utilizador_role (utilizador_id integer REFERENCES app.utilizador,role text REFERENCES app.role,PRIMARY KEY(utilizador_id,role));
CREATE TABLE app.super_autorizado (utilizador_id integer PRIMARY KEY REFERENCES app.utilizador);
CREATE TABLE app.sessao (token_hash bytea PRIMARY KEY,utilizador_id integer NOT NULL REFERENCES app.utilizador,expira timestamptz NOT NULL DEFAULT now()+interval '12 hours');
ALTER TABLE jogo.revisao ADD FOREIGN KEY(utilizador_id) REFERENCES app.utilizador;
ALTER TABLE competicao.resultado ADD FOREIGN KEY(utilizador_id) REFERENCES app.utilizador;
ALTER TABLE seguranca.correcao ADD FOREIGN KEY(utilizador_id) REFERENCES app.utilizador;
CREATE TABLE auditoria.intencao (id uuid PRIMARY KEY DEFAULT gen_random_uuid(),utilizador_id integer NOT NULL REFERENCES app.utilizador,objeto text NOT NULL CHECK(objeto IN ('JOGO','SEGURANCA')),objeto_id integer NOT NULL,motivo text NOT NULL CHECK(length(trim(motivo))>=5),original jsonb NOT NULL,criado_em timestamptz NOT NULL DEFAULT clock_timestamp());
CREATE TABLE auditoria.desfecho (id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,intencao_id uuid NOT NULL UNIQUE REFERENCES auditoria.intencao,resultado text NOT NULL CHECK(resultado IN ('EXECUTADA','REJEITADA','CANCELADA')),detalhe jsonb NOT NULL,criado_em timestamptz NOT NULL DEFAULT clock_timestamp());
CREATE TABLE auditoria.operacional (id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,utilizador_id integer REFERENCES app.utilizador,correlacao uuid NOT NULL,tabela text NOT NULL,acao text NOT NULL,antes jsonb,depois jsonb,criado_em timestamptz NOT NULL DEFAULT clock_timestamp());
CREATE TABLE auditoria.meta (id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,utilizador_id integer REFERENCES app.utilizador,correlacao uuid NOT NULL,acao text NOT NULL,alvo text NOT NULL,permitido boolean NOT NULL,criado_em timestamptz NOT NULL DEFAULT clock_timestamp());
CREATE TABLE forense.registo (id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,correlacao uuid NOT NULL,categoria text NOT NULL,instante timestamptz NOT NULL,cifra bytea NOT NULL,anterior text NOT NULL,hash text NOT NULL CHECK(length(hash)=64));
CREATE TABLE forense.checkpoint (id bigint PRIMARY KEY REFERENCES forense.registo,hash text NOT NULL);
ALTER TABLE seguranca.operacao ADD CHECK(fim IS NULL OR (inicio IS NOT NULL AND fim>=inicio));
ALTER TABLE seguranca.operacao ADD CHECK(estado<>'FINALIZADA' OR avaliacao IS NOT NULL);
ALTER TABLE seguranca.ocorrencia ADD CHECK(NOT uso_forca OR justificacao_forca IS NOT NULL);
ALTER TABLE seguranca.ocorrencia ADD CHECK(feridos=0 OR assistencia IS NOT NULL);
ALTER TABLE seguranca.ocorrencia ADD CHECK(length(trim(evidencia))>=1 AND length(trim(envolvidos))>=2);
ALTER TABLE jogo.evento ADD CHECK(seq>0);
ALTER TABLE competicao.epoca
 ADD estado text NOT NULL DEFAULT 'ABERTA' CHECK(estado IN('ABERTA','FINALIZADA')),
 ADD classificacao_final jsonb,
 ADD campeao_id integer REFERENCES clubes.equipa,
 ADD finalizada_em timestamptz,
 ADD finalizada_por integer REFERENCES app.utilizador,
 ADD CHECK((estado='ABERTA' AND classificacao_final IS NULL AND campeao_id IS NULL AND finalizada_em IS NULL AND finalizada_por IS NULL)
 OR (estado='FINALIZADA' AND classificacao_final IS NOT NULL AND jsonb_typeof(classificacao_final)='array' AND jsonb_array_length(classificacao_final)>0 AND campeao_id IS NOT NULL AND finalizada_em IS NOT NULL AND finalizada_por IS NOT NULL));
COMMIT;
