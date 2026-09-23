BEGIN;
-- Contas base da demonstração.
-- Alf e Paulo mantêm o primeiro acesso obrigatório do baseline.
-- José e Adalberto têm credencial permanente de demonstração e não forçam mudança.
INSERT INTO app.utilizador(nome,email,password_hash,mudar_password) VALUES
 ('AlfCyberCop','Alfcybercop@nexuscup.pt','$2a$12$G.mKvqs6oj0vjjm75bY1Xe7brtn3tyDJHKyOk/wzOO/t0EM8GJzwm',true),
 ('Paulo Ricardo Costa Ramalho','Paulo.ramalho@nexuscup.pt','$2a$12$G.mKvqs6oj0vjjm75bY1Xe7brtn3tyDJHKyOk/wzOO/t0EM8GJzwm',true),
 ('José Silva','jose.silva@nexuscup.pt','$2a$12$iF5QJVDlCV.aeJX71Gjxuua7vQzTNEurnHKvBznYK3RG3hRo5jvpm',false),
 ('Adalberto Costa','adalberto.costa@nexuscup.pt','$2a$12$iF5QJVDlCV.aeJX71Gjxuua7vQzTNEurnHKvBznYK3RG3hRo5jvpm',false);

INSERT INTO app.utilizador_role(utilizador_id,role)
SELECT u.id,v.role
FROM app.utilizador u
JOIN (VALUES
 ('alfcybercop@nexuscup.pt','ADMIN'),
 ('alfcybercop@nexuscup.pt','SUPER_AUDITOR'),
 ('paulo.ramalho@nexuscup.pt','ADMIN'),
 ('paulo.ramalho@nexuscup.pt','SUPER_AUDITOR'),
 ('jose.silva@nexuscup.pt','OPERADOR'),
 ('adalberto.costa@nexuscup.pt','OPERADOR'),
 ('adalberto.costa@nexuscup.pt','LEITOR')
) AS v(email,role) ON lower(u.email)=v.email;

INSERT INTO app.super_autorizado(utilizador_id)
SELECT id FROM app.utilizador
WHERE lower(email) IN('alfcybercop@nexuscup.pt','paulo.ramalho@nexuscup.pt');

SELECT set_config('nexus.actor',(SELECT id::text FROM app.utilizador WHERE lower(email)='alfcybercop@nexuscup.pt'),true),
       set_config('nexus.correlation',gen_random_uuid()::text,true);
DO $$
DECLARE nomes text[]:=ARRAY['Duarte Valença','Miguel Figueiral','Rui Sequeira','Tomás Lameirinho','Diogo Cedofeita','Vasco Penedo','Afonso Malveiro','Nuno Castanheira','Gonçalo Pinheiral','Leandro Marialva','Tiago Soutinho','Bruno Alpendre','Ivo Carvalhal','Fábio Portelinha','Simão Valeiro','Henrique Monteluz','Rodrigo Serralva','Guilherme Azenhal','Luís Fontanário','Rafael Amieiral','Daniel Sobralinho','Martim Casalino','Eduardo Vilarinho','André Freixial','Pedro Laranjal','Hugo Ribeirinho','Samuel Oliveiral','Filipe Cerdeiral','César Fozal','Artur Valeseco','Mário Telheiral','Jorge Rosmaninho','Inês Casteleira','Mafalda Valeverde','Joana Pedralva','Beatriz Figueiredo','Carolina Soutelo','Leonor Amieira','Teresa Montalegre','Sofia Cercal'];
 clubes text[]:=ARRAY['Atlético da Ribeira Clara','União do Vale Sereno','Desportivo das Fontes Altas','Académico de Monte Azul'];
 cidades text[]:=ARRAY['Braga','Coimbra','Leiria','Viseu'];
 t integer; n integer; pid integer; vid integer; rid integer; cid integer;
BEGIN
 FOR n IN 1..40 LOOP INSERT INTO nucleo.pessoa(nome,nif,email,telefone) VALUES(nomes[n],(900100000+n)::text,'contacto.'||n||'@exemplo.invalid',NULL); END LOOP;
 FOR t IN 1..4 LOOP
 INSERT INTO competicao.recinto(nome,cidade,capacidade) VALUES('Pavilhão '||clubes[t],cidades[t],400+t*100) RETURNING id INTO rid;
 INSERT INTO clubes.clube(nome) VALUES(clubes[t]) RETURNING id INTO cid;
 INSERT INTO clubes.equipa(clube_id,nome,recinto_id) VALUES(cid,clubes[t]||' Sénior',rid);
 FOR n IN 1..8 LOOP
 pid:=(t-1)*8+n;
 INSERT INTO clubes.vinculo(equipa_id,pessoa_id,funcao,inicio,fim) VALUES(t,pid,CASE WHEN n=8 THEN 'TREINADOR' ELSE 'JOGADOR' END,'2025-07-01','2027-06-30') RETURNING id INTO vid;
 IF n<=7 THEN INSERT INTO clubes.camisola(vinculo_id,equipa_id,numero,inicio,fim) VALUES(vid,t,n,'2025-07-01','2027-06-30'); END IF;
 END LOOP;
 END LOOP;
END $$;
INSERT INTO arbitragem.oficial VALUES(33),(34),(35),(36);
INSERT INTO seguranca.entidade(nome,tipo) VALUES('PSP — Unidade de demonstração','PSP'),('GNR — Unidade de demonstração','GNR'),('Vigilância Vale Claro','PRIVADA');
INSERT INTO seguranca.agente VALUES(37,1),(38,2),(39,3),(40,3);
INSERT INTO competicao.epoca(nome,designacao,inicio,fim) VALUES('TAÇA NEXUS histórica','2025/26','2025-07-01','2026-06-30'),('NEXUS CUP','2026/27','2026-07-01','2027-06-30');
INSERT INTO competicao.inscricao SELECT ep.id,e.id FROM competicao.epoca ep CROSS JOIN clubes.equipa e;
INSERT INTO competicao.jornada(epoca_id,numero) SELECT ep.id,n FROM competicao.epoca ep CROSS JOIN generate_series(1,6) n;
DO $$
DECLARE pairs integer[][]:=ARRAY[[1,4],[2,3],[1,3],[4,2],[1,2],[3,4],[4,1],[3,2],[3,1],[2,4],[2,1],[4,3]]; ep integer; n integer; jo integer;
BEGIN
 FOR ep IN 1..2 LOOP FOR n IN 1..12 LOOP
 SELECT id INTO jo FROM competicao.jornada WHERE epoca_id=ep AND numero=(n+1)/2;
 INSERT INTO competicao.jogo(epoca_id,jornada_id,casa_id,fora_id,recinto_esperado) VALUES(ep,jo,pairs[n][1],pairs[n][2],pairs[n][1]);
 END LOOP; END LOOP;
END $$;
DO $$
DECLARE j record; p record; r jsonb; instant timestamptz; iid uuid; event_id bigint;
BEGIN
 -- Dataset histórico: todos os jogos seguem o fluxo operacional completo.
 FOR j IN SELECT * FROM competicao.jogo WHERE epoca_id=1 ORDER BY id LOOP
  instant:=timestamptz '2026-01-10 14:00:00+00'+((j.id-1)/2)*interval '7 days'+mod(j.id-1,2)*interval '3 hours';
  PERFORM app.command(1,'AGENDAR',jsonb_build_object('jogo_id',j.id,'inicio',instant));
  PERFORM app.command(1,'ARBITRAGEM',jsonb_build_object('jogo_id',j.id,'pessoa_id',33,'funcao','ARBITRO'));
  PERFORM app.command(1,'ARBITRAGEM',jsonb_build_object('jogo_id',j.id,'pessoa_id',34,'funcao','SEGUNDO_ARBITRO'));
  PERFORM app.command(1,'ARBITRAGEM',jsonb_build_object('jogo_id',j.id,'pessoa_id',35,'funcao','CRONOMETRISTA'));
  PERFORM app.command(1,'PREPARAR_SEGURANCA',jsonb_build_object('jogo_id',j.id,'responsavel_id',37,'agentes',jsonb_build_array(39,40)));
  PERFORM app.command(1,'INICIAR_SEGURANCA',jsonb_build_object('jogo_id',j.id,'instante',instant-interval '1 hour'));
  FOR p IN SELECT * FROM clubes.v_jogadores_clubes WHERE equipa_id IN(j.casa_id,j.fora_id) AND funcao='JOGADOR' ORDER BY equipa_id,numero LOOP
   PERFORM app.command(1,'CONVOCAR',jsonb_build_object('jogo_id',j.id,'vinculo_id',p.vinculo_id,'camisola_id',p.camisola_id,'titular',p.numero<=5,'goleiro',p.numero=1));
  END LOOP;
  PERFORM app.command(1,'SIMULAR',jsonb_build_object('jogo_id',j.id));
  IF j.id IN(3,7,11) THEN
   PERFORM app.command(1,'OCORRENCIA',jsonb_build_object('jogo_id',j.id,'instante',instant+interval '105 minutes','descricao',CASE WHEN j.id=11 THEN 'Separação de dois espectadores na saída; assistência a escoriação ligeira.' ELSE 'Assistência preventiva na saída do pavilhão; situação resolvida sem confronto.' END,'envolvidos','Espectadores fictícios, identificados no auto de demonstração','evidencia','Auto académico fictício — equipa de segurança registou acompanhamento na saída.','feridos',CASE WHEN j.id=11 THEN 1 ELSE 0 END,'assistencia','Primeiros socorros no recinto; sem transporte.','uso_forca',j.id=11,'justificacao_forca','Separação manual breve para cessar confronto; cessou após afastamento.'));
  END IF;
  -- Regra NEXUS: a segurança só fecha depois de o jogo estar FINALIZADO.
  PERFORM app.command(1,'FINALIZAR_SEGURANCA',jsonb_build_object('jogo_id',j.id,'instante',instant+interval '2 hours','avaliacao',CASE WHEN j.id IN(3,7,11) THEN 'Saída acompanhada. Ocorrência documentada e revista pelo responsável.' ELSE 'Operação preventiva tranquila. Público saiu sem incidentes.' END));
  PERFORM app.command(1,'HOMOLOGAR',jsonb_build_object('jogo_id',j.id,'motivo','Fecho administrativo do dataset histórico fictício'));
 END LOOP;

 -- Época corrente: só o primeiro jogo começa agendado; os restantes ficam por agendar.
 PERFORM app.command(1,'AGENDAR',jsonb_build_object('jogo_id',13,'inicio','2026-10-03T15:00:00+01:00'));

 -- A época histórica fica realmente encerrada, com classificação final e campeão preservados.
 r:=app.command(1,'FINALIZAR_EPOCA',jsonb_build_object('epoca_id',1));
 IF r ? 'erro' THEN RAISE EXCEPTION 'Fecho da época histórica falhou: %',r; END IF;

 -- Incidente crítico 1: revisão posterior real de um cartão vermelho/expulsão.
 SELECT id INTO event_id FROM jogo.evento WHERE jogo_id=3 AND tipo='EXPULSAO_SEGUNDO_AMARELO' ORDER BY seq LIMIT 1;
 IF event_id IS NULL THEN RAISE EXCEPTION 'Evento vermelho de demonstração não encontrado'; END IF;
 r:=app.command(1,'INTENCAO',jsonb_build_object('objeto','JOGO','objeto_id',3,'motivo','Super Auditoria: validar manipulação posterior de expulsão'));
 iid:=(r->>'id')::uuid;
 r:=app.command(1,'RETIFICAR',jsonb_build_object('intencao_id',iid,'tipo','CARTAO_VERMELHO','evento_id',event_id,'valido',false));
 IF coalesce(r->>'resultado','')<>'EXECUTADA' THEN RAISE EXCEPTION 'Incidente de cartão vermelho não foi executado: %',r; END IF;

 -- Incidente crítico 2: tentativa real de alterar um golo/resultado numa Liga FINALIZADA.
 SELECT id INTO event_id FROM jogo.evento WHERE jogo_id=2 AND tipo='GOLO' ORDER BY seq LIMIT 1;
 IF event_id IS NULL THEN RAISE EXCEPTION 'Golo de demonstração não encontrado'; END IF;
 r:=app.command(1,'INTENCAO',jsonb_build_object('objeto','JOGO','objeto_id',2,'motivo','Super Auditoria: tentativa de alterar resultado oficial após fecho da Liga'));
 iid:=(r->>'id')::uuid;
 r:=app.command(1,'RETIFICAR',jsonb_build_object('intencao_id',iid,'tipo','GOLO','evento_id',event_id,'valido',false));
 IF coalesce(r->>'resultado','')<>'REJEITADA' THEN RAISE EXCEPTION 'Tentativa sobre resultado deveria ter sido bloqueada: %',r; END IF;
END $$;
COMMIT;
