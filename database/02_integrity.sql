BEGIN;
CREATE FUNCTION app.actor() RETURNS integer LANGUAGE sql STABLE AS $$ SELECT nullif(current_setting('nexus.actor',true),'')::integer $$;
CREATE FUNCTION app.correlation() RETURNS uuid LANGUAGE sql STABLE AS $$ SELECT coalesce(nullif(current_setting('nexus.correlation',true),'')::uuid,gen_random_uuid()) $$;
CREATE FUNCTION app.has_role(u integer,r text) RETURNS boolean LANGUAGE sql STABLE AS $$ SELECT EXISTS(SELECT 1 FROM app.utilizador_role ur JOIN app.utilizador a ON a.id=ur.utilizador_id WHERE ur.utilizador_id=u AND ur.role=r AND a.ativo) AND (r<>'SUPER_AUDITOR' OR EXISTS(SELECT 1 FROM app.super_autorizado WHERE utilizador_id=u)) $$;
CREATE FUNCTION forense.registar(cat text,payload jsonb) RETURNS void LANGUAGE plpgsql AS $$
DECLARE prev text; cipher bytea; ts timestamptz:=clock_timestamp(); cor uuid:=app.correlation(); h text; rid bigint; k text:=current_setting('nexus.key',true);
BEGIN
 IF k IS NULL OR length(k)<32 THEN RAISE EXCEPTION 'Chave forense indisponível'; END IF;
 PERFORM pg_advisory_xact_lock(91001,1);
 SELECT hash INTO prev FROM forense.registo ORDER BY id DESC LIMIT 1;
 prev:=coalesce(prev,repeat('0',64)); cipher:=pgp_sym_encrypt(payload::text,k,'cipher-algo=aes256');
 h:=encode(digest(convert_to(prev||'|'||cor::text||'|'||cat||'|'||extract(epoch from ts)::text||'|'||encode(cipher,'hex'),'UTF8'),'sha256'),'hex');
 INSERT INTO forense.registo(correlacao,categoria,instante,cifra,anterior,hash) VALUES(cor,cat,ts,cipher,prev,h) RETURNING id INTO rid;
 INSERT INTO forense.checkpoint VALUES(rid,h);
END $$;
CREATE FUNCTION forense.verificar() RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE r record; prev text:=repeat('0',64); n integer:=0; h text;
BEGIN
 PERFORM pg_advisory_xact_lock(91001,1);
 FOR r IN SELECT * FROM forense.registo ORDER BY id LOOP
 h:=encode(digest(convert_to(prev||'|'||r.correlacao::text||'|'||r.categoria||'|'||extract(epoch from r.instante)::text||'|'||encode(r.cifra,'hex'),'UTF8'),'sha256'),'hex');
 IF r.anterior<>prev OR r.hash<>h OR NOT EXISTS(SELECT 1 FROM forense.checkpoint c WHERE c.id=r.id AND c.hash=r.hash) THEN RETURN jsonb_build_object('integra',false,'primeiro_invalido',r.id); END IF;
 prev:=r.hash;n:=n+1;
 END LOOP;
 IF (SELECT count(*) FROM forense.checkpoint)<>n THEN RETURN jsonb_build_object('integra',false,'erro','Checkpoint divergente'); END IF;
 RETURN jsonb_build_object('integra',true,'registos',n,'ultimo_hash',prev);
END $$;
CREATE FUNCTION auditoria.imutavel() RETURNS trigger LANGUAGE plpgsql AS $$ BEGIN RAISE EXCEPTION 'Histórico imutável: inserir nova versão'; END $$;
CREATE FUNCTION auditoria.registar() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE a jsonb; d jsonb; cor uuid:=app.correlation();
BEGIN
 IF TG_OP<>'INSERT' THEN a:=to_jsonb(OLD); END IF;
 IF TG_OP<>'DELETE' THEN d:=to_jsonb(NEW); END IF;
 INSERT INTO auditoria.operacional(utilizador_id,correlacao,tabela,acao,antes,depois) VALUES(app.actor(),cor,TG_TABLE_SCHEMA||'.'||TG_TABLE_NAME,TG_OP,a,d);
 PERFORM forense.registar('OPERACIONAL',jsonb_build_object('tabela',TG_TABLE_SCHEMA||'.'||TG_TABLE_NAME,'acao',TG_OP,'antes',a,'depois',d,'utilizador',app.actor(),'correlacao',cor));
 RETURN coalesce(NEW,OLD);
END $$;
CREATE FUNCTION clubes.validar_vinculo() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
 PERFORM pg_advisory_xact_lock(91002,NEW.pessoa_id);
 IF EXISTS(SELECT 1 FROM clubes.vinculo v WHERE v.id<>NEW.id AND v.pessoa_id=NEW.pessoa_id AND v.funcao=NEW.funcao AND daterange(v.inicio,v.fim,'[]') && daterange(NEW.inicio,NEW.fim,'[]')) THEN RAISE EXCEPTION 'Vínculo temporal sobreposto'; END IF;
 IF TG_OP='UPDATE' THEN
 IF (NEW.equipa_id,NEW.pessoa_id,NEW.funcao,NEW.inicio) IS DISTINCT FROM (OLD.equipa_id,OLD.pessoa_id,OLD.funcao,OLD.inicio) THEN RAISE EXCEPTION 'Identidade do vínculo imutável'; END IF;
 IF EXISTS(SELECT 1 FROM jogo.convocado c JOIN competicao.jogo j ON j.id=c.jogo_id WHERE c.vinculo_id=NEW.id AND j.inicio::date>NEW.fim) THEN RAISE EXCEPTION 'Fim invalidaria convocatória histórica'; END IF;
 IF EXISTS(SELECT 1 FROM clubes.camisola c WHERE c.vinculo_id=NEW.id AND (c.fim IS NULL OR c.fim>NEW.fim)) AND NEW.fim IS NOT NULL THEN RAISE EXCEPTION 'Terminar números antes de terminar vínculo'; END IF;
 END IF;
 RETURN NEW;
END $$;
CREATE TRIGGER validar_vinculo BEFORE INSERT OR UPDATE ON clubes.vinculo FOR EACH ROW EXECUTE FUNCTION clubes.validar_vinculo();
CREATE FUNCTION clubes.validar_camisola() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE v clubes.vinculo;
BEGIN
 PERFORM pg_advisory_xact_lock(91003,NEW.equipa_id);
 SELECT * INTO v FROM clubes.vinculo WHERE id=NEW.vinculo_id;
 IF v.id IS NULL OR v.funcao<>'JOGADOR' OR v.equipa_id<>NEW.equipa_id OR NEW.inicio<v.inicio OR coalesce(NEW.fim,'infinity')>coalesce(v.fim,'infinity') THEN RAISE EXCEPTION 'Camisola fora do vínculo'; END IF;
 IF TG_OP='UPDATE' AND (NEW.vinculo_id,NEW.equipa_id,NEW.numero,NEW.inicio) IS DISTINCT FROM (OLD.vinculo_id,OLD.equipa_id,OLD.numero,OLD.inicio) THEN RAISE EXCEPTION 'Número temporal: terminar atribuição e criar outra'; END IF;
 IF TG_OP='UPDATE' AND EXISTS(SELECT 1 FROM jogo.convocado c JOIN competicao.jogo j ON j.id=c.jogo_id WHERE c.camisola_id=NEW.id AND j.inicio::date>NEW.fim) THEN RAISE EXCEPTION 'Fim invalidaria convocatória histórica'; END IF;
 IF EXISTS(SELECT 1 FROM clubes.camisola c WHERE c.id<>NEW.id AND c.equipa_id=NEW.equipa_id AND (c.numero=NEW.numero OR c.vinculo_id=NEW.vinculo_id) AND daterange(c.inicio,c.fim,'[]') && daterange(NEW.inicio,NEW.fim,'[]')) THEN RAISE EXCEPTION 'Número de camisola sobreposto no tempo'; END IF;
 RETURN NEW;
END $$;
CREATE TRIGGER validar_camisola BEFORE INSERT OR UPDATE ON clubes.camisola FOR EACH ROW EXECUTE FUNCTION clubes.validar_camisola();
CREATE FUNCTION jogo.validar_convocado() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE j competicao.jogo; v clubes.vinculo; c clubes.camisola;
BEGIN
 SELECT * INTO j FROM competicao.jogo WHERE id=NEW.jogo_id FOR UPDATE;
 IF TG_OP='UPDATE' THEN
 IF (to_jsonb(NEW)-'estado') IS DISTINCT FROM (to_jsonb(OLD)-'estado') OR current_setting('nexus.engine',true) IS DISTINCT FROM 'on' THEN RAISE EXCEPTION 'Convocatória preservada; estado apenas pelo motor'; END IF;
 RETURN NEW;
 END IF;
 SELECT * INTO v FROM clubes.vinculo WHERE id=NEW.vinculo_id;
 SELECT * INTO c FROM clubes.camisola WHERE id=NEW.camisola_id;
 IF j.estado<>'AGENDADO' OR v.id IS NULL OR c.id IS NULL OR v.funcao<>'JOGADOR' OR v.equipa_id NOT IN(j.casa_id,j.fora_id) OR c.vinculo_id<>v.id OR NOT (daterange(v.inicio,v.fim,'[]') @> j.inicio::date) OR NOT(daterange(c.inicio,c.fim,'[]') @> j.inicio::date) THEN RAISE EXCEPTION 'Jogador não elegível para convocatória'; END IF;
 NEW.equipa_id:=v.equipa_id; NEW.pessoa_id:=v.pessoa_id; NEW.numero:=c.numero;NEW.estado:=CASE WHEN NEW.titular THEN 'EM_CAMPO' ELSE 'BANCO' END;
 IF (SELECT count(*) FROM jogo.convocado WHERE jogo_id=j.id AND equipa_id=v.equipa_id)>=14 OR (NEW.titular AND (SELECT count(*) FROM jogo.convocado WHERE jogo_id=j.id AND equipa_id=v.equipa_id AND titular)>=5) THEN RAISE EXCEPTION 'Limite de convocatória'; END IF;
 RETURN NEW;
END $$;
CREATE TRIGGER validar_convocado BEFORE INSERT OR UPDATE ON jogo.convocado FOR EACH ROW EXECUTE FUNCTION jogo.validar_convocado();
CREATE FUNCTION arbitragem.validar_nomeacao() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE j competicao.jogo;
BEGIN
 PERFORM pg_advisory_xact_lock(91004,NEW.pessoa_id);
 SELECT * INTO j FROM competicao.jogo WHERE id=NEW.jogo_id;
 IF j.inicio IS NULL THEN RAISE EXCEPTION 'Agendar antes de nomear'; END IF;
 IF EXISTS(SELECT 1 FROM arbitragem.nomeacao n JOIN competicao.jogo x ON x.id=n.jogo_id WHERE n.pessoa_id=NEW.pessoa_id AND n.id<>NEW.id AND x.estado<>'CANCELADO' AND tstzrange(x.inicio,x.inicio+interval '2 hours','[)') && tstzrange(j.inicio,j.inicio+interval '2 hours','[)')) THEN RAISE EXCEPTION 'Conflito de arbitragem no período reservado'; END IF;
 RETURN NEW;
END $$;
CREATE TRIGGER validar_nomeacao BEFORE INSERT OR UPDATE ON arbitragem.nomeacao FOR EACH ROW EXECUTE FUNCTION arbitragem.validar_nomeacao();
CREATE FUNCTION competicao.validar_jogo() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
 IF TG_OP='INSERT' THEN
 IF NEW.estado<>'NAO_AGENDADO' OR NEW.segundos<>0 OR NEW.periodo<>1 THEN RAISE EXCEPTION 'Criar jogo não agendado'; END IF;
 SELECT recinto_id INTO NEW.recinto_esperado FROM clubes.equipa WHERE id=NEW.casa_id;
 ELSE
 IF (NEW.periodo,NEW.segundos,NEW.intervalo,NEW.estado) IS DISTINCT FROM (OLD.periodo,OLD.segundos,OLD.intervalo,OLD.estado) AND current_setting('nexus.engine',true) IS DISTINCT FROM 'on' THEN RAISE EXCEPTION 'Estado e relógio exigem motor'; END IF;
 IF (NEW.epoca_id,NEW.jornada_id,NEW.casa_id,NEW.fora_id) IS DISTINCT FROM(OLD.epoca_id,OLD.jornada_id,OLD.casa_id,OLD.fora_id) THEN
 RAISE EXCEPTION 'Emparelhamento definido pela jornada: época, jornada, casa e visitante não são alteráveis';
 END IF;
 IF NEW.inicio IS DISTINCT FROM OLD.inicio AND EXISTS(SELECT 1 FROM jogo.convocado WHERE jogo_id=OLD.id) THEN RAISE EXCEPTION 'Rever convocatória antes de reagendar'; END IF;
 IF NEW.inicio IS DISTINCT FROM OLD.inicio AND EXISTS(SELECT 1 FROM arbitragem.nomeacao WHERE jogo_id=OLD.id) THEN RAISE EXCEPTION 'Remover nomeações antes de reagendar'; END IF;
 END IF;
 IF NEW.recinto_id IS DISTINCT FROM NEW.recinto_esperado AND NEW.recinto_id IS NOT NULL AND nullif(trim(NEW.motivo_recinto),'') IS NULL THEN RAISE EXCEPTION 'Motivo de alteração do recinto obrigatório'; END IF;
 RETURN NEW;
END $$;
CREATE TRIGGER validar_jogo BEFORE INSERT OR UPDATE ON competicao.jogo FOR EACH ROW EXECUTE FUNCTION competicao.validar_jogo();
CREATE FUNCTION seguranca.criar_operacao() RETURNS trigger LANGUAGE plpgsql AS $$ BEGIN INSERT INTO seguranca.operacao(jogo_id) VALUES(NEW.id); RETURN NEW; END $$;
CREATE TRIGGER criar_operacao AFTER INSERT ON competicao.jogo FOR EACH ROW EXECUTE FUNCTION seguranca.criar_operacao();
CREATE FUNCTION seguranca.validar_finalizacao() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE estado_jogo text;
BEGIN
 IF NEW.estado='FINALIZADA' AND OLD.estado IS DISTINCT FROM 'FINALIZADA' THEN
  SELECT estado INTO estado_jogo FROM competicao.jogo WHERE id=NEW.jogo_id;
  IF estado_jogo<>'FINALIZADO' THEN RAISE EXCEPTION 'A operacao de seguranca so pode ser finalizada depois de o jogo estar FINALIZADO'; END IF;
 END IF;
 RETURN NEW;
END $$;
CREATE TRIGGER validar_finalizacao BEFORE UPDATE OF estado ON seguranca.operacao FOR EACH ROW EXECUTE FUNCTION seguranca.validar_finalizacao();
CREATE FUNCTION auditoria.guardar_fecho() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE jid integer; oid integer; fechado boolean:=false; iid uuid:=nullif(current_setting('nexus.intent',true),'')::uuid; obj text; target integer; v jsonb:=coalesce(to_jsonb(NEW),to_jsonb(OLD));
BEGIN
 IF TG_TABLE_SCHEMA='seguranca' THEN
 oid:=CASE WHEN TG_TABLE_NAME='operacao' THEN (v->>'id')::int ELSE (v->>'operacao_id')::int END;
 IF TG_TABLE_NAME='operacao' AND TG_OP='UPDATE' THEN fechado:=OLD.estado='FINALIZADA'; ELSE SELECT estado='FINALIZADA' INTO fechado FROM seguranca.operacao WHERE id=oid; END IF;
 obj:='SEGURANCA'; target:=oid;
 ELSE
 jid:=CASE WHEN TG_TABLE_NAME='jogo' THEN (v->>'id')::int ELSE (v->>'jogo_id')::int END;
 IF TG_TABLE_NAME='revisao' THEN SELECT jogo_id INTO jid FROM jogo.evento WHERE id=(v->>'evento_id')::bigint; END IF;
 IF TG_TABLE_NAME='jogo' AND TG_OP='UPDATE' THEN fechado:=OLD.estado='HOMOLOGADO'; ELSE SELECT estado='HOMOLOGADO' INTO fechado FROM competicao.jogo WHERE id=jid; END IF;
 obj:='JOGO';target:=jid;
 END IF;
 IF fechado AND NOT EXISTS(SELECT 1 FROM auditoria.intencao i WHERE i.id=iid AND i.utilizador_id=app.actor() AND i.objeto=obj AND i.objeto_id=target AND NOT EXISTS(SELECT 1 FROM auditoria.desfecho d WHERE d.intencao_id=i.id)) THEN RAISE EXCEPTION 'Objeto fechado exige intenção de retificação'; END IF;
 RETURN coalesce(NEW,OLD);
END $$;
DO $$ DECLARE t text; BEGIN
 FOREACH t IN ARRAY ARRAY['competicao.jogo','competicao.resultado','jogo.convocado','jogo.evento','jogo.revisao','arbitragem.nomeacao','seguranca.operacao','seguranca.efetivo','seguranca.ocorrencia','seguranca.correcao'] LOOP
 EXECUTE format('CREATE TRIGGER a_guardar_fecho BEFORE INSERT OR UPDATE OR DELETE ON %s FOR EACH ROW EXECUTE FUNCTION auditoria.guardar_fecho()',t);
 END LOOP;
 FOREACH t IN ARRAY ARRAY['nucleo.pessoa','clubes.clube','clubes.equipa','clubes.vinculo','clubes.camisola','competicao.jogo','competicao.resultado','jogo.convocado','jogo.evento','jogo.revisao','jogo.reducao','arbitragem.nomeacao','seguranca.operacao','seguranca.efetivo','seguranca.ocorrencia','seguranca.correcao','auditoria.intencao','auditoria.desfecho'] LOOP
 EXECUTE format('CREATE TRIGGER z_auditar AFTER INSERT OR UPDATE OR DELETE ON %s FOR EACH ROW EXECUTE FUNCTION auditoria.registar()',t);
 END LOOP;
 FOREACH t IN ARRAY ARRAY['jogo.evento','jogo.revisao','competicao.resultado','auditoria.intencao','auditoria.desfecho','auditoria.operacional','auditoria.meta','forense.registo','forense.checkpoint','seguranca.ocorrencia','seguranca.correcao'] LOOP
 EXECUTE format('CREATE TRIGGER imutavel BEFORE UPDATE OR DELETE ON %s FOR EACH ROW EXECUTE FUNCTION auditoria.imutavel()',t);
 END LOOP;
END $$;
CREATE VIEW jogo.v_eventos AS SELECT e.*,coalesce((SELECT valido FROM jogo.revisao r WHERE r.evento_id=e.id ORDER BY r.id DESC LIMIT 1),true) valido,
 CASE WHEN tipo='SEGUNDA_PARTE' THEN '20:01' ELSE lpad((((periodo-1)*1200+segundos)/60)::text,2,'0')||':'||lpad((segundos%60)::text,2,'0') END tempo,
 p.nome jogador,q.nome entra FROM jogo.evento e LEFT JOIN jogo.convocado c ON c.id=e.jogador_id LEFT JOIN nucleo.pessoa p ON p.id=c.pessoa_id LEFT JOIN jogo.convocado b ON b.id=e.entra_id LEFT JOIN nucleo.pessoa q ON q.id=b.pessoa_id;
CREATE VIEW competicao.v_jogos_resultados AS SELECT j.*,c.nome casa,f.nome fora,r.nome recinto,jo.numero jornada,ep.nome competicao,
 (SELECT count(*)::integer FROM jogo.v_eventos e WHERE e.jogo_id=j.id AND e.tipo='GOLO' AND e.valido AND e.equipa_id=j.casa_id) golos_casa,
 (SELECT count(*)::integer FROM jogo.v_eventos e WHERE e.jogo_id=j.id AND e.tipo='GOLO' AND e.valido AND e.equipa_id=j.fora_id) golos_fora
 FROM competicao.jogo j JOIN clubes.equipa c ON c.id=j.casa_id JOIN clubes.equipa f ON f.id=j.fora_id LEFT JOIN competicao.recinto r ON r.id=j.recinto_id JOIN competicao.jornada jo ON jo.id=j.jornada_id JOIN competicao.epoca ep ON ep.id=j.epoca_id;
CREATE VIEW clubes.v_jogadores_clubes AS SELECT v.id vinculo_id,p.id pessoa_id,p.nome,c.nome clube,e.nome equipa,e.id equipa_id,v.funcao,v.inicio,v.fim,n.id camisola_id,n.numero,n.inicio numero_inicio,n.fim numero_fim,p.email,p.telefone FROM clubes.vinculo v JOIN nucleo.pessoa p ON p.id=v.pessoa_id JOIN clubes.equipa e ON e.id=v.equipa_id JOIN clubes.clube c ON c.id=e.clube_id LEFT JOIN clubes.camisola n ON n.vinculo_id=v.id;
CREATE VIEW competicao.v_classificacao AS
 SELECT i.epoca_id,e.id equipa_id,e.nome,count(j.id)::int jogos,count(j.id) FILTER(WHERE gf>ga)::int vitorias,count(j.id) FILTER(WHERE gf=ga)::int empates,count(j.id) FILTER(WHERE gf<ga)::int derrotas,coalesce(sum(gf),0)::int golos_favor,coalesce(sum(ga),0)::int golos_contra,coalesce(sum(CASE WHEN gf>ga THEN 3 WHEN gf=ga THEN 1 ELSE 0 END) FILTER(WHERE j.id IS NOT NULL),0)::int pontos,
 EXISTS(SELECT 1 FROM competicao.jogo x WHERE x.epoca_id=i.epoca_id AND x.estado='FINALIZADO') provisoria
 FROM competicao.inscricao i JOIN clubes.equipa e ON e.id=i.equipa_id LEFT JOIN LATERAL(SELECT x.id,CASE WHEN x.casa_id=e.id THEN golos_casa ELSE golos_fora END gf,CASE WHEN x.casa_id=e.id THEN golos_fora ELSE golos_casa END ga FROM competicao.v_jogos_resultados x WHERE x.epoca_id=i.epoca_id AND e.id IN(x.casa_id,x.fora_id) AND x.estado IN('FINALIZADO','HOMOLOGADO')) j ON true GROUP BY i.epoca_id,e.id;
CREATE FUNCTION competicao.readiness(jid integer) RETURNS jsonb LANGUAGE sql STABLE AS $$
 SELECT jsonb_build_object('pronto',j.estado='FINALIZADO' AND o.estado='FINALIZADA' AND EXISTS(SELECT 1 FROM arbitragem.nomeacao WHERE jogo_id=jid AND funcao='ARBITRO'),
 'motivos',array_remove(ARRAY[CASE WHEN j.estado<>'FINALIZADO' THEN 'Jogo por finalizar' END,CASE WHEN o.estado IS DISTINCT FROM 'FINALIZADA' THEN 'Operação de segurança por finalizar' END,CASE WHEN NOT EXISTS(SELECT 1 FROM arbitragem.nomeacao WHERE jogo_id=jid AND funcao='ARBITRO') THEN 'Arbitragem pendente' END],NULL)) FROM competicao.jogo j LEFT JOIN seguranca.operacao o ON o.jogo_id=j.id WHERE j.id=jid $$;
-- Fecho serializado com as escritas da competição; snapshot imutável.
CREATE FUNCTION competicao.guardar_epoca() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE final jsonb;
BEGIN
 IF TG_OP<>'INSERT' AND OLD.estado='FINALIZADA' THEN RAISE EXCEPTION 'Liga FINALIZADA: fecho e classificação imutáveis'; END IF;
 IF TG_OP='DELETE' THEN RETURN OLD; END IF;
 IF NEW.estado='FINALIZADA' THEN
 IF TG_OP='INSERT' OR NOT app.has_role(app.actor(),'ADMIN') THEN RAISE EXCEPTION 'Fecho reservado à administração'; END IF;
 IF NOT EXISTS(SELECT 1 FROM competicao.jogo WHERE epoca_id=NEW.id AND estado='HOMOLOGADO')
 OR EXISTS(SELECT 1 FROM competicao.jogo WHERE epoca_id=NEW.id AND estado NOT IN('HOMOLOGADO','CANCELADO'))
 OR EXISTS(SELECT 1 FROM competicao.jogo j LEFT JOIN seguranca.operacao o ON o.jogo_id=j.id WHERE j.epoca_id=NEW.id AND j.estado='HOMOLOGADO' AND o.estado IS DISTINCT FROM 'FINALIZADA')
 THEN RAISE EXCEPTION 'Todos os jogos aplicáveis devem estar homologados e com segurança finalizada'; END IF;
 SELECT jsonb_agg(to_jsonb(c) ORDER BY pontos DESC,(golos_favor-golos_contra) DESC,golos_favor DESC,nome) INTO final FROM competicao.v_classificacao c WHERE epoca_id=NEW.id;
 IF final IS NULL OR jsonb_array_length(final)=0 THEN RAISE EXCEPTION 'Classificação indisponível'; END IF;
 IF (SELECT count(*) FROM competicao.v_classificacao c WHERE epoca_id=NEW.id AND c.pontos=(final->0->>'pontos')::int AND c.golos_favor-c.golos_contra=(final->0->>'golos_favor')::int-(final->0->>'golos_contra')::int AND c.golos_favor=(final->0->>'golos_favor')::int)>1
 THEN RAISE EXCEPTION 'Empate no primeiro lugar: desempate regulamentar pendente'; END IF;
 NEW.classificacao_final:=final;NEW.campeao_id:=(final->0->>'equipa_id')::int;NEW.finalizada_em:=clock_timestamp();NEW.finalizada_por:=app.actor();
 END IF;
 RETURN NEW;
END $$;
CREATE TRIGGER a_guardar_epoca BEFORE INSERT OR UPDATE OR DELETE ON competicao.epoca FOR EACH ROW EXECUTE FUNCTION competicao.guardar_epoca();
CREATE TRIGGER z_auditar AFTER INSERT OR UPDATE OR DELETE ON competicao.epoca FOR EACH ROW EXECUTE FUNCTION auditoria.registar();

CREATE FUNCTION competicao.proteger_epoca() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE v jsonb; ep integer; jid integer; oid integer; encerrada boolean; iid uuid:=nullif(current_setting('nexus.intent',true),'')::uuid; permitido boolean;
BEGIN
 -- Em UPDATE verificar tanto a origem como o destino (não mover objetos para contornar o fecho).
 FOR v IN SELECT value FROM jsonb_array_elements(CASE WHEN TG_OP='INSERT' THEN jsonb_build_array(to_jsonb(NEW)) WHEN TG_OP='DELETE' THEN jsonb_build_array(to_jsonb(OLD)) ELSE jsonb_build_array(to_jsonb(OLD),to_jsonb(NEW)) END) LOOP
 jid:=NULL;oid:=NULL;ep:=NULL;
 IF TG_TABLE_NAME IN('jogo','jornada','inscricao') THEN ep:=(v->>'epoca_id')::int;IF TG_TABLE_NAME='jogo' THEN jid:=(v->>'id')::int;END IF;
 ELSIF TG_TABLE_SCHEMA='seguranca' THEN
 IF TG_TABLE_NAME='operacao' THEN oid:=(v->>'id')::int;jid:=(v->>'jogo_id')::int;
 ELSE oid:=(v->>'operacao_id')::int;SELECT jogo_id INTO jid FROM seguranca.operacao WHERE id=oid;END IF;
 ELSE jid:=(v->>'jogo_id')::int;IF TG_TABLE_NAME='revisao' THEN SELECT jogo_id INTO jid FROM jogo.evento WHERE id=(v->>'evento_id')::bigint;END IF;
 END IF;
 IF ep IS NULL THEN SELECT epoca_id INTO ep FROM competicao.jogo WHERE id=jid; END IF;
 SELECT estado='FINALIZADA' INTO encerrada FROM competicao.epoca WHERE id=ep FOR UPDATE;
 IF encerrada THEN
 permitido:=EXISTS(SELECT 1 FROM auditoria.intencao i WHERE i.id=iid AND i.utilizador_id=app.actor() AND app.has_role(app.actor(),'ADMIN') AND NOT EXISTS(SELECT 1 FROM auditoria.desfecho d WHERE d.intencao_id=i.id)
 AND ((i.objeto='JOGO' AND i.objeto_id=jid AND TG_TABLE_NAME IN('revisao','nomeacao','jogo')) OR (i.objeto='SEGURANCA' AND i.objeto_id=oid AND TG_TABLE_NAME='correcao')));
 IF TG_TABLE_NAME='revisao' THEN permitido:=permitido AND app.has_role(app.actor(),'SUPER_AUDITOR') AND EXISTS(SELECT 1 FROM jogo.evento WHERE id=(v->>'evento_id')::bigint AND tipo IN('VERMELHO_DIRETO','EXPULSAO_SEGUNDO_AMARELO')); END IF;
 IF TG_TABLE_NAME IN('revisao','correcao') THEN permitido:=permitido AND TG_OP='INSERT'; END IF;
 IF TG_TABLE_NAME='jogo' THEN permitido:=permitido AND TG_OP='UPDATE' AND (to_jsonb(NEW)-'recinto_id'-'motivo_recinto')=(to_jsonb(OLD)-'recinto_id'-'motivo_recinto'); END IF;
 IF TG_TABLE_NAME='nomeacao' THEN permitido:=permitido AND TG_OP='UPDATE' AND (to_jsonb(NEW)-'pessoa_id')=(to_jsonb(OLD)-'pessoa_id'); END IF;
 IF NOT permitido THEN RAISE EXCEPTION 'Liga FINALIZADA: operação normal bloqueada'; END IF;
 END IF;
 END LOOP;
 RETURN coalesce(NEW,OLD);
END $$;
DO $$ DECLARE t text; BEGIN
 FOREACH t IN ARRAY ARRAY['competicao.jogo','competicao.jornada','competicao.inscricao','competicao.resultado','jogo.convocado','jogo.evento','jogo.revisao','jogo.reducao','arbitragem.nomeacao','seguranca.operacao','seguranca.efetivo','seguranca.ocorrencia','seguranca.correcao'] LOOP
 EXECUTE format('CREATE TRIGGER a0_proteger_epoca BEFORE INSERT OR UPDATE OR DELETE ON %s FOR EACH ROW EXECUTE FUNCTION competicao.proteger_epoca()',t);
 END LOOP;
END $$;
COMMIT;
