BEGIN;
CREATE FUNCTION app.command(u integer,a text,b jsonb) RETURNS jsonb LANGUAGE plpgsql AS $$
#variable_conflict use_column
DECLARE jid integer:=(b->>'jogo_id')::integer; j competicao.jogo; oid integer; x record; item record; v integer; eid bigint; iid uuid; i auditoria.intencao; out jsonb; antes jsonb; token text; role_name text;
BEGIN
 PERFORM set_config('nexus.actor',u::text,true);
 IF a='ME' THEN RETURN (SELECT jsonb_build_object('id',id,'nome',nome,'email',email,'mudar_password',mudar_password,'roles',(SELECT jsonb_agg(role) FROM app.utilizador_role WHERE utilizador_id=u)) FROM app.utilizador WHERE id=u); END IF;
 IF a='PASSWORD' THEN
 IF length(b->>'nova')<12 OR length(b->>'nova')>64 OR (b->>'nova')!~'[A-Z]' OR (b->>'nova')!~'[a-z]' OR (b->>'nova')!~'[0-9]' OR (b->>'nova')!~'[^a-zA-Z0-9]' THEN RAISE EXCEPTION 'Password: 12 a 64 caracteres, maiúscula, minúscula, número e símbolo'; END IF;
 IF EXISTS(SELECT 1 FROM app.utilizador WHERE id=u AND crypt(b->>'nova',password_hash)=password_hash) THEN RAISE EXCEPTION 'Escolher password diferente'; END IF;
 UPDATE app.utilizador SET password_hash=crypt(b->>'nova',gen_salt('bf',12)),mudar_password=false WHERE id=u;
 DELETE FROM app.sessao WHERE utilizador_id=u AND token_hash<>decode(current_setting('nexus.session'),'hex');
 PERFORM forense.registar('PASSWORD',jsonb_build_object('utilizador',u)); RETURN '{"ok":true}';
 END IF;
 IF a='LOGOUT' THEN DELETE FROM app.sessao WHERE token_hash=decode(current_setting('nexus.session'),'hex'); RETURN '{"ok":true}'; END IF;
 IF a IN('SUPER','SUPER_DETALHE','INTEGRIDADE') THEN
 INSERT INTO auditoria.meta(utilizador_id,correlacao,acao,alvo,permitido) VALUES(u,app.correlation(),a,coalesce(b->>'id','SUPER_AUDITORIA'),app.has_role(u,'SUPER_AUDITOR'));
 PERFORM forense.registar(CASE WHEN app.has_role(u,'SUPER_AUDITOR') THEN 'ACESSO_SUPER' ELSE 'ACESSO_NEGADO' END,jsonb_build_object('utilizador',u,'acao',a,'alvo',b));
 IF NOT app.has_role(u,'SUPER_AUDITOR') THEN RETURN '{"erro":"Acesso negado","status":403}'; END IF;
 IF a='INTEGRIDADE' THEN RETURN forense.verificar(); END IF;
 IF a='SUPER_DETALHE' THEN
 SELECT * INTO i FROM auditoria.intencao WHERE id=(b->>'id')::uuid;
 RETURN jsonb_build_object('intencao',to_jsonb(i),'desfecho',(SELECT to_jsonb(d) FROM auditoria.desfecho d WHERE intencao_id=i.id),
 'auditoria',(SELECT coalesce(jsonb_agg(o ORDER BY id),'[]') FROM auditoria.operacional o WHERE o.correlacao IN(SELECT correlacao FROM auditoria.operacional WHERE depois->>'id'=i.id::text OR depois->>'intencao_id'=i.id::text)),
 'meta',(SELECT coalesce(jsonb_agg(m ORDER BY id),'[]') FROM auditoria.meta m WHERE alvo=i.id::text),
 'forense',(SELECT coalesce(jsonb_agg(jsonb_build_object('id',f.id,'hash',f.hash,'anterior',f.anterior,'payload',pgp_sym_decrypt(f.cifra,current_setting('nexus.key'))::jsonb) ORDER BY f.id),'[]') FROM forense.registo f WHERE f.correlacao IN(SELECT correlacao FROM auditoria.operacional WHERE depois->>'id'=i.id::text OR depois->>'intencao_id'=i.id::text)), 'integridade',forense.verificar());
 END IF;
 RETURN jsonb_build_object('red_flags',(SELECT coalesce(jsonb_agg(x ORDER BY criado_em DESC),'[]') FROM (SELECT i.*,u.nome utilizador,d.resultado,d.detalhe FROM auditoria.intencao i JOIN app.utilizador u ON u.id=i.utilizador_id LEFT JOIN auditoria.desfecho d ON d.intencao_id=i.id) x),
 'acessos',(SELECT coalesce(jsonb_agg(x ORDER BY id DESC),'[]') FROM (SELECT m.*,u.nome utilizador FROM auditoria.meta m LEFT JOIN app.utilizador u ON u.id=m.utilizador_id ORDER BY m.id DESC LIMIT 200) x),'integridade',forense.verificar());
 END IF;
 IF a='CATALOGO' THEN RETURN jsonb_build_object('epocas',(SELECT jsonb_agg(e ORDER BY id DESC) FROM competicao.epoca e),'clubes',(SELECT jsonb_agg(c ORDER BY nome) FROM clubes.clube c),'equipas',(SELECT jsonb_agg(e ORDER BY nome) FROM clubes.equipa e),'recintos',(SELECT jsonb_agg(e ORDER BY nome) FROM competicao.recinto e),'arbitros',(SELECT jsonb_agg(x) FROM (SELECT p.id,p.nome FROM arbitragem.oficial o JOIN nucleo.pessoa p ON p.id=o.pessoa_id) x),'agentes',(SELECT jsonb_agg(x) FROM (SELECT p.id,p.nome,e.nome entidade FROM seguranca.agente a JOIN nucleo.pessoa p ON p.id=a.pessoa_id JOIN seguranca.entidade e ON e.id=a.entidade_id) x),'jornadas',(SELECT jsonb_agg(x ORDER BY epoca_id,numero) FROM competicao.jornada x)); END IF;
 IF a='JOGOS' THEN RETURN (SELECT coalesce(jsonb_agg(x ORDER BY jornada,id),'[]') FROM competicao.v_jogos_resultados x WHERE epoca_id=(b->>'epoca_id')::int); END IF;
 IF a='DASHBOARD' THEN RETURN (SELECT jsonb_build_object('epoca',(SELECT to_jsonb(e) FROM competicao.epoca e WHERE id=(b->>'epoca_id')::int),'estados',(SELECT jsonb_object_agg(estado,n) FROM (SELECT estado,count(*) n FROM competicao.jogo WHERE epoca_id=(b->>'epoca_id')::int GROUP BY estado) x),'seguranca_aberta',(SELECT count(*) FROM seguranca.operacao o JOIN competicao.jogo j ON j.id=o.jogo_id WHERE j.epoca_id=(b->>'epoca_id')::int AND j.estado<>'CANCELADO' AND o.estado<>'FINALIZADA'))); END IF;
 IF a='PLANTEIS' THEN
 RETURN (SELECT coalesce(jsonb_agg(x ORDER BY equipa,nome,numero_inicio),'[]') FROM clubes.v_jogadores_clubes x JOIN competicao.inscricao i ON i.equipa_id=x.equipa_id JOIN competicao.epoca e ON e.id=i.epoca_id WHERE i.epoca_id=(b->>'epoca_id')::int AND x.inicio<=e.fim AND (x.fim IS NULL OR x.fim>=e.inicio) AND (x.numero_inicio IS NULL OR (x.numero_inicio<=e.fim AND (x.numero_fim IS NULL OR x.numero_fim>=e.inicio))));
 END IF;
 IF a='JOGO' THEN
 SELECT * INTO j FROM competicao.jogo WHERE id=jid;
 IF j.id IS NULL THEN RAISE EXCEPTION 'Jogo inexistente'; END IF;
 SELECT id INTO oid FROM seguranca.operacao WHERE jogo_id=jid;
 RETURN jsonb_build_object('epoca',(SELECT to_jsonb(e) FROM competicao.epoca e WHERE id=j.epoca_id),'jogo',(SELECT to_jsonb(x) FROM competicao.v_jogos_resultados x WHERE id=jid),'readiness',competicao.readiness(jid),
 'eventos',(SELECT coalesce(jsonb_agg(x ORDER BY seq),'[]') FROM jogo.v_eventos x WHERE jogo_id=jid),
 'convocados',(SELECT coalesce(jsonb_agg(x ORDER BY equipa_id,numero),'[]') FROM (SELECT c.*,p.nome FROM jogo.convocado c JOIN nucleo.pessoa p ON p.id=c.pessoa_id WHERE jogo_id=jid) x),
 'elegiveis',(SELECT coalesce(jsonb_agg(x ORDER BY equipa_id,numero),'[]') FROM clubes.v_jogadores_clubes x WHERE equipa_id IN(j.casa_id,j.fora_id) AND funcao='JOGADOR' AND daterange(inicio,fim,'[]') @> j.inicio::date AND daterange(numero_inicio,numero_fim,'[]') @> j.inicio::date AND NOT EXISTS(SELECT 1 FROM jogo.convocado c WHERE c.jogo_id=jid AND c.pessoa_id=x.pessoa_id)),
 'arbitragem',(SELECT coalesce(jsonb_agg(x),'[]') FROM (SELECT n.*,p.nome FROM arbitragem.nomeacao n JOIN nucleo.pessoa p ON p.id=n.pessoa_id WHERE jogo_id=jid) x),
 'seguranca',(SELECT to_jsonb(o) FROM seguranca.operacao o WHERE id=oid),'efetivos',(SELECT coalesce(jsonb_agg(x),'[]') FROM (SELECT e.agente_id,p.nome FROM seguranca.efetivo e JOIN nucleo.pessoa p ON p.id=e.agente_id WHERE operacao_id=oid) x),
 'ocorrencias',(SELECT coalesce(jsonb_agg(x ORDER BY instante),'[]') FROM seguranca.ocorrencia x WHERE operacao_id=oid),
 'correcoes_seguranca',(SELECT coalesce(jsonb_agg(x ORDER BY id),'[]') FROM seguranca.correcao x WHERE operacao_id=oid),
 'reducoes',(SELECT coalesce(jsonb_agg(x ORDER BY id),'[]') FROM jogo.reducao x WHERE jogo_id=jid),'resultados',(SELECT coalesce(jsonb_agg(x ORDER BY versao),'[]') FROM competicao.resultado x WHERE jogo_id=jid));
 END IF;
 IF a='RELATORIO' THEN
 CASE b->>'tipo'
 WHEN 'classificacao' THEN RETURN coalesce((SELECT classificacao_final FROM competicao.epoca WHERE id=(b->>'epoca_id')::int),(SELECT coalesce(jsonb_agg(x ORDER BY pontos DESC,(golos_favor-golos_contra) DESC,golos_favor DESC,nome),'[]') FROM competicao.v_classificacao x WHERE epoca_id=(b->>'epoca_id')::int));
 WHEN 'jogadores' THEN RETURN (SELECT coalesce(jsonb_agg(x ORDER BY clube,nome),'[]') FROM clubes.v_jogadores_clubes x JOIN competicao.inscricao i ON i.equipa_id=x.equipa_id JOIN competicao.epoca e ON e.id=i.epoca_id WHERE i.epoca_id=(b->>'epoca_id')::int AND x.inicio<=e.fim AND (x.fim IS NULL OR x.fim>=e.inicio) AND (x.numero_inicio IS NULL OR (x.numero_inicio<=e.fim AND (x.numero_fim IS NULL OR x.numero_fim>=e.inicio))));
 WHEN 'golos' THEN RETURN (SELECT coalesce(jsonb_agg(x ORDER BY golos DESC,jogador),'[]') FROM (SELECT e.jogador,count(*) golos FROM jogo.v_eventos e JOIN competicao.jogo j ON j.id=e.jogo_id WHERE j.epoca_id=(b->>'epoca_id')::int AND tipo='GOLO' AND valido GROUP BY jogador) x);
 WHEN 'cartoes' THEN RETURN (SELECT coalesce(jsonb_agg(x ORDER BY jogo_id,seq),'[]') FROM (SELECT e.jogo_id,e.tempo,e.seq,e.jogador,e.tipo FROM jogo.v_eventos e JOIN competicao.jogo j ON j.id=e.jogo_id WHERE j.epoca_id=(b->>'epoca_id')::int AND (jid IS NULL OR j.id=jid) AND tipo IN('AMARELO','VERMELHO_DIRETO','EXPULSAO_SEGUNDO_AMARELO') AND valido) x);
 WHEN 'faltas' THEN RETURN (SELECT coalesce(jsonb_agg(x),'[]') FROM (SELECT e.jogo_id,e.periodo,t.nome equipa,count(*) FILTER(WHERE detalhe->>'classe'='DIRETO') acumuladas,count(*) FILTER(WHERE detalhe->>'classe'='INDIRETO') indiretas FROM jogo.evento e JOIN competicao.jogo j ON j.id=e.jogo_id JOIN clubes.equipa t ON t.id=e.equipa_id WHERE j.epoca_id=(b->>'epoca_id')::int AND tipo='FALTA' GROUP BY e.jogo_id,e.periodo,t.nome) x);
 WHEN 'seguranca' THEN RETURN (SELECT coalesce(jsonb_agg(x ORDER BY jornada,jogo_id),'[]') FROM (SELECT o.jogo_id,jo.numero jornada,casa.nome casa,fora.nome fora,j.estado jogo_estado,o.estado,o.avaliacao,resp.nome responsavel,count(oc.id) ocorrencias,coalesce(sum(oc.feridos),0) feridos,count(oc.id) FILTER(WHERE oc.uso_forca) uso_forca,(SELECT count(*) FROM seguranca.efetivo ef WHERE ef.operacao_id=o.id) efetivos FROM seguranca.operacao o JOIN competicao.jogo j ON j.id=o.jogo_id JOIN competicao.jornada jo ON jo.id=j.jornada_id JOIN clubes.equipa casa ON casa.id=j.casa_id JOIN clubes.equipa fora ON fora.id=j.fora_id LEFT JOIN seguranca.agente ag ON ag.pessoa_id=o.responsavel_id LEFT JOIN nucleo.pessoa resp ON resp.id=ag.pessoa_id LEFT JOIN seguranca.ocorrencia oc ON oc.operacao_id=o.id WHERE j.epoca_id=(b->>'epoca_id')::int GROUP BY o.id,jo.numero,casa.nome,fora.nome,j.estado,resp.nome) x);
 WHEN 'arbitragem' THEN RETURN (SELECT coalesce(jsonb_agg(x ORDER BY jornada,jogo_id),'[]') FROM (SELECT j.id jogo_id,jo.numero jornada,c.nome casa,f.nome fora,j.inicio,coalesce(jsonb_agg(jsonb_build_object('funcao',n.funcao,'nome',p.nome) ORDER BY n.funcao) FILTER(WHERE n.id IS NOT NULL),'[]'::jsonb) oficiais FROM competicao.jogo j JOIN competicao.jornada jo ON jo.id=j.jornada_id JOIN clubes.equipa c ON c.id=j.casa_id JOIN clubes.equipa f ON f.id=j.fora_id LEFT JOIN arbitragem.nomeacao n ON n.jogo_id=j.id LEFT JOIN nucleo.pessoa p ON p.id=n.pessoa_id WHERE j.epoca_id=(b->>'epoca_id')::int GROUP BY j.id,jo.numero,c.nome,f.nome,j.inicio) x);
 WHEN 'auditoria' THEN
  IF NOT app.has_role(u,'SUPER_AUDITOR') THEN RETURN '{"erro":"Acesso negado","status":403}'; END IF;
  RETURN jsonb_build_object('integridade',forense.verificar(),'intervencoes',(SELECT coalesce(jsonb_agg(x ORDER BY criado_em DESC),'[]') FROM (SELECT i.id,i.objeto,i.objeto_id,i.motivo,i.criado_em,d.resultado,d.detalhe FROM auditoria.intencao i LEFT JOIN auditoria.desfecho d ON d.intencao_id=i.id) x));
 ELSE RETURN (SELECT coalesce(jsonb_agg(x ORDER BY jornada,id),'[]') FROM competicao.v_jogos_resultados x WHERE epoca_id=(b->>'epoca_id')::int AND ((b->>'jornada') IS NULL OR jornada=(b->>'jornada')::int));
 END CASE;
 END IF;
 IF NOT(app.has_role(u,'ADMIN') OR app.has_role(u,'OPERADOR')) THEN RETURN '{"erro":"Sem permissão de escrita","status":403}'; END IF;
 IF a='CRIAR_RECINTO' THEN
 IF length(trim(coalesce(b->>'nome','')))<3 OR length(trim(coalesce(b->>'cidade','')))<2 OR coalesce((b->>'capacidade')::int,0)<1 THEN RAISE EXCEPTION 'Novo recinto: nome, cidade e capacidade valida sao obrigatorios'; END IF;
 IF EXISTS(SELECT 1 FROM competicao.recinto WHERE lower(nome)=lower(trim(b->>'nome'))) THEN RAISE EXCEPTION 'Ja existe um recinto com esse nome'; END IF;
 INSERT INTO competicao.recinto(nome,cidade,capacidade) VALUES(trim(b->>'nome'),trim(b->>'cidade'),(b->>'capacidade')::int) RETURNING id INTO v;
 PERFORM forense.registar('RECINTO_CRIADO',jsonb_build_object('utilizador',u,'recinto_id',v,'nome',trim(b->>'nome'),'cidade',trim(b->>'cidade'),'capacidade',(b->>'capacidade')::int));
 RETURN (SELECT to_jsonb(r) FROM competicao.recinto r WHERE id=v);
 END IF;
 IF a='FINALIZAR_EPOCA' THEN
 IF NOT app.has_role(u,'ADMIN') THEN RETURN '{"erro":"Fecho reservado à administração","status":403}'; END IF;
 UPDATE competicao.epoca SET estado='FINALIZADA' WHERE id=(b->>'epoca_id')::int RETURNING to_jsonb(competicao.epoca.*) INTO out;
 IF NOT FOUND THEN RAISE EXCEPTION 'Época inexistente'; END IF;
 RETURN jsonb_build_object('ok',true,'epoca',out);
 END IF;
 IF a='INTENCAO' THEN
 IF NOT app.has_role(u,'ADMIN') THEN RETURN '{"erro":"Retificação reservada à administração","status":403}'; END IF;
 IF b->>'objeto'='JOGO' THEN
 SELECT to_jsonb(x) INTO antes FROM competicao.v_jogos_resultados x WHERE id=(b->>'objeto_id')::int AND estado='HOMOLOGADO';
 ELSE SELECT to_jsonb(x) INTO antes FROM seguranca.operacao x WHERE id=(b->>'objeto_id')::int AND estado='FINALIZADA'; END IF;
 IF antes IS NULL THEN RAISE EXCEPTION 'Objeto não está formalmente fechado'; END IF;
 INSERT INTO auditoria.intencao(utilizador_id,objeto,objeto_id,motivo,original) VALUES(u,b->>'objeto',(b->>'objeto_id')::int,b->>'motivo',antes) RETURNING id INTO iid;
 RETURN jsonb_build_object('id',iid);
 END IF;
 IF a IN('RETIFICAR','CANCELAR_RETIFICACAO') THEN
 SELECT * INTO i FROM auditoria.intencao WHERE id=(b->>'intencao_id')::uuid FOR UPDATE;
 IF i.id IS NULL OR i.utilizador_id<>u OR NOT app.has_role(u,'ADMIN') OR EXISTS(SELECT 1 FROM auditoria.desfecho WHERE intencao_id=i.id) THEN RAISE EXCEPTION 'Intenção indisponível'; END IF;
 IF a='CANCELAR_RETIFICACAO' THEN INSERT INTO auditoria.desfecho(intencao_id,resultado,detalhe) VALUES(i.id,'CANCELADA',b);RETURN '{"ok":true}'; END IF;
 PERFORM set_config('nexus.intent',i.id::text,true);
 BEGIN
 IF i.objeto='JOGO' THEN
 PERFORM 1 FROM competicao.jogo WHERE id=i.objeto_id FOR UPDATE;
 IF b->>'tipo'='GOLO' THEN
 IF EXISTS(SELECT 1 FROM competicao.epoca e JOIN competicao.jogo j ON j.epoca_id=e.id WHERE j.id=i.objeto_id AND e.estado='FINALIZADA') THEN RAISE EXCEPTION 'Liga FINALIZADA: resultado oficial protegido'; END IF;
 IF NOT EXISTS(SELECT 1 FROM jogo.evento WHERE id=(b->>'evento_id')::bigint AND jogo_id=i.objeto_id AND tipo='GOLO') THEN RAISE EXCEPTION 'Selecionar golo pertencente ao jogo'; END IF;
 INSERT INTO jogo.revisao(evento_id,valido,motivo,utilizador_id) VALUES((b->>'evento_id')::bigint,(b->>'valido')::boolean,i.motivo,u);
 SELECT * INTO x FROM competicao.v_jogos_resultados WHERE id=i.objeto_id;
 INSERT INTO competicao.resultado(jogo_id,versao,casa,fora,motivo,utilizador_id) SELECT i.objeto_id,coalesce(max(versao),0)+1,x.golos_casa,x.golos_fora,i.motivo,u FROM competicao.resultado WHERE jogo_id=i.objeto_id;
 ELSIF b->>'tipo'='CARTAO_VERMELHO' THEN
 IF NOT app.has_role(u,'SUPER_AUDITOR') THEN RAISE EXCEPTION 'Revisão de vermelho reservada a SUPER_AUDITOR'; END IF;
 SELECT to_jsonb(e) INTO antes FROM jogo.v_eventos e WHERE id=(b->>'evento_id')::bigint AND jogo_id=i.objeto_id AND tipo IN('VERMELHO_DIRETO','EXPULSAO_SEGUNDO_AMARELO');
 IF antes IS NULL THEN RAISE EXCEPTION 'Selecionar cartão vermelho pertencente ao jogo'; END IF;
 IF jsonb_typeof(b->'valido') IS DISTINCT FROM 'boolean' OR (antes->>'valido')::boolean=(b->>'valido')::boolean THEN RAISE EXCEPTION 'Indicar novo estado de validade do cartão'; END IF;
 INSERT INTO jogo.revisao(evento_id,valido,motivo,utilizador_id) VALUES((b->>'evento_id')::bigint,(b->>'valido')::boolean,i.motivo,u);
 SELECT jsonb_build_object('antes',antes,'depois',to_jsonb(e),'ambito','Decisão posterior ao jogo; efeitos em campo e resultado histórico preservados') INTO antes FROM jogo.v_eventos e WHERE id=(b->>'evento_id')::bigint;
 ELSIF b->>'tipo'='RECINTO' THEN UPDATE competicao.jogo SET recinto_id=(b->>'recinto_id')::int,motivo_recinto=i.motivo WHERE id=i.objeto_id;
 ELSIF b->>'tipo'='ARBITRAGEM' THEN UPDATE arbitragem.nomeacao SET pessoa_id=(b->>'pessoa_id')::int WHERE jogo_id=i.objeto_id AND funcao=b->>'funcao'; IF NOT FOUND THEN RAISE EXCEPTION 'Nomeação inexistente'; END IF;
 ELSE RAISE EXCEPTION 'Tipo de retificação não suportado'; END IF;
 SELECT to_jsonb(x) INTO out FROM competicao.v_jogos_resultados x WHERE id=i.objeto_id;
 ELSE
 IF b->>'ocorrencia_id' IS NOT NULL AND NOT EXISTS(SELECT 1 FROM seguranca.ocorrencia WHERE id=(b->>'ocorrencia_id')::int AND operacao_id=i.objeto_id) THEN RAISE EXCEPTION 'Ocorrência fora da operação'; END IF;
 INSERT INTO seguranca.correcao(operacao_id,ocorrencia_id,texto,utilizador_id) VALUES(i.objeto_id,(b->>'ocorrencia_id')::int,b->>'texto',u) RETURNING to_jsonb(seguranca.correcao.*) INTO out;
 END IF;
 INSERT INTO auditoria.desfecho(intencao_id,resultado,detalhe) VALUES(i.id,'EXECUTADA',jsonb_build_object('antes',i.original,'pedido',b,'depois',out,'evento',CASE WHEN b->>'tipo'='CARTAO_VERMELHO' THEN antes ELSE NULL END));
 RETURN jsonb_build_object('ok',true,'resultado','EXECUTADA');
 EXCEPTION WHEN OTHERS THEN
 INSERT INTO auditoria.desfecho(intencao_id,resultado,detalhe) VALUES(i.id,'REJEITADA',jsonb_build_object('pedido',b,'erro',SQLERRM,'sqlstate',SQLSTATE));
 RETURN jsonb_build_object('erro',SQLERRM,'status',409,'resultado','REJEITADA');
 END;
 END IF;
 IF a='UTILIZADORES' THEN
 IF NOT app.has_role(u,'ADMIN') THEN RETURN '{"erro":"Acesso negado","status":403}'; END IF;
 RETURN (SELECT jsonb_agg(x ORDER BY nome) FROM (SELECT id,nome,email,ativo,mudar_password,(SELECT jsonb_agg(role) FROM app.utilizador_role WHERE utilizador_id=z.id) roles FROM app.utilizador z) x);
 END IF;
 IF a='CRIAR_UTILIZADOR' THEN
 IF NOT app.has_role(u,'ADMIN') OR (b->>'role') NOT IN('ADMIN','OPERADOR','LEITOR') THEN RETURN '{"erro":"Role não permitida","status":403}'; END IF;
 IF length(b->>'password')<12 THEN RAISE EXCEPTION 'Password temporária insuficiente'; END IF;
 INSERT INTO app.utilizador(nome,email,password_hash) VALUES(b->>'nome',b->>'email',crypt(b->>'password',gen_salt('bf',12))) RETURNING id INTO v;
 INSERT INTO app.utilizador_role VALUES(v,b->>'role');PERFORM forense.registar('UTILIZADOR_CRIADO',jsonb_build_object('id',v,'role',b->>'role'));RETURN jsonb_build_object('id',v);
 END IF;
 IF a IN('PESSOA','ADICIONAR_JOGADOR','TERMINAR_VINCULO','NUMERO') THEN
  IF b->>'epoca_id' IS NULL OR NOT EXISTS(SELECT 1 FROM competicao.epoca WHERE id=(b->>'epoca_id')::int) THEN RAISE EXCEPTION 'Selecionar uma época válida'; END IF;
  IF EXISTS(SELECT 1 FROM competicao.epoca WHERE id=(b->>'epoca_id')::int AND estado='FINALIZADA') THEN RAISE EXCEPTION 'Época FINALIZADA: plantel histórico em modo de leitura'; END IF;
 END IF;
 IF a='PESSOA' THEN UPDATE nucleo.pessoa SET nome=b->>'nome',email=nullif(b->>'email',''),telefone=nullif(b->>'telefone','') WHERE id=(b->>'pessoa_id')::int;RETURN '{"ok":true}'; END IF;
 IF a='ADICIONAR_JOGADOR' THEN
 IF NOT EXISTS(SELECT 1 FROM competicao.inscricao WHERE epoca_id=(b->>'epoca_id')::int AND equipa_id=(b->>'equipa_id')::int) THEN RAISE EXCEPTION 'A equipa não está inscrita na época selecionada'; END IF;
 INSERT INTO nucleo.pessoa(nome,nif,email,telefone) VALUES(b->>'nome',nullif(b->>'nif',''),nullif(b->>'email',''),nullif(b->>'telefone','')) RETURNING id INTO v;
 INSERT INTO clubes.vinculo(equipa_id,pessoa_id,funcao,inicio,fim) VALUES((b->>'equipa_id')::int,v,'JOGADOR',(b->>'inicio')::date,nullif(b->>'fim','')::date) RETURNING id INTO v;
 INSERT INTO clubes.camisola(vinculo_id,equipa_id,numero,inicio,fim) VALUES(v,(b->>'equipa_id')::int,(b->>'numero')::int,(b->>'inicio')::date,nullif(b->>'fim','')::date); RETURN jsonb_build_object('id',v);
 END IF;
 IF a='TERMINAR_VINCULO' THEN
 UPDATE clubes.camisola SET fim=(b->>'fim')::date WHERE vinculo_id=(b->>'vinculo_id')::int AND (fim IS NULL OR fim>(b->>'fim')::date);
 UPDATE clubes.vinculo SET fim=(b->>'fim')::date WHERE id=(b->>'vinculo_id')::int; RETURN '{"ok":true}'; END IF;
 IF a='NUMERO' THEN
 SELECT * INTO x FROM clubes.vinculo WHERE id=(b->>'vinculo_id')::int FOR UPDATE;
 UPDATE clubes.camisola SET fim=(b->>'inicio')::date-1 WHERE vinculo_id=x.id AND (fim IS NULL OR fim>=(b->>'inicio')::date);
 INSERT INTO clubes.camisola(vinculo_id,equipa_id,numero,inicio,fim) VALUES(x.id,x.equipa_id,(b->>'numero')::int,(b->>'inicio')::date,x.fim); RETURN '{"ok":true}'; END IF;
 SELECT * INTO j FROM competicao.jogo WHERE id=jid FOR UPDATE;
 IF j.id IS NULL THEN RAISE EXCEPTION 'Jogo inexistente'; END IF;
 SELECT id INTO oid FROM seguranca.operacao WHERE jogo_id=jid FOR UPDATE;
 PERFORM set_config('nexus.engine','on',true);
 CASE a
 WHEN 'AGENDAR' THEN
 IF j.estado NOT IN('NAO_AGENDADO','ADIADO') THEN RAISE EXCEPTION 'Jogo não pode ser agendado'; END IF;
 IF (b ? 'casa_id' AND (b->>'casa_id')::int IS DISTINCT FROM j.casa_id) OR (b ? 'fora_id' AND (b->>'fora_id')::int IS DISTINCT FROM j.fora_id) THEN RAISE EXCEPTION 'Emparelhamento definido pela jornada: Casa e Visitante não podem ser alterados no agendamento'; END IF;
 UPDATE competicao.jogo SET inicio=(b->>'inicio')::timestamptz,recinto_id=coalesce((b->>'recinto_id')::int,recinto_esperado),estado='AGENDADO',motivo_recinto=b->>'motivo' WHERE id=jid;
 WHEN 'RECINTO' THEN
 UPDATE competicao.jogo SET recinto_id=(b->>'recinto_id')::int,motivo_recinto=b->>'motivo' WHERE id=jid;
 WHEN 'ADIAR' THEN IF j.estado<>'AGENDADO' THEN RAISE EXCEPTION 'Só jogo agendado pode ser adiado'; END IF;UPDATE competicao.jogo SET estado='ADIADO' WHERE id=jid;
 WHEN 'CANCELAR_JOGO' THEN IF j.estado NOT IN('NAO_AGENDADO','AGENDADO','ADIADO','INTERROMPIDO') OR length(b->>'motivo')<5 THEN RAISE EXCEPTION 'Cancelamento exige estado compatível e motivo'; END IF; UPDATE competicao.jogo SET estado='CANCELADO' WHERE id=jid;PERFORM forense.registar('CANCELAMENTO',b);
 WHEN 'ARBITRAGEM' THEN INSERT INTO arbitragem.nomeacao(jogo_id,pessoa_id,funcao) VALUES(jid,(b->>'pessoa_id')::int,b->>'funcao') ON CONFLICT(jogo_id,funcao) DO UPDATE SET pessoa_id=excluded.pessoa_id;
 WHEN 'CONVOCAR' THEN INSERT INTO jogo.convocado(jogo_id,vinculo_id,camisola_id,equipa_id,pessoa_id,numero,titular,goleiro,estado) VALUES(jid,(b->>'vinculo_id')::int,(b->>'camisola_id')::int,0,0,1,(b->>'titular')::boolean,coalesce((b->>'goleiro')::boolean,false),'BANCO');
 WHEN 'GUARDAR_CONVOCATORIA' THEN
  IF j.estado<>'AGENDADO' THEN RAISE EXCEPTION 'Convocatória apenas disponível para jogo AGENDADO'; END IF;
  IF jsonb_typeof(coalesce(b->'jogadores','[]'::jsonb))<>'array' THEN RAISE EXCEPTION 'Lista de convocados inválida'; END IF;
  -- Em AGENDADO a convocatória pode ser revista integralmente antes do apito inicial.
  -- A substituição é atómica dentro do app.rpc: se a nova seleção for inválida, o pedido faz rollback.
  DELETE FROM jogo.convocado WHERE jogo_id=jid;
  FOR item IN SELECT * FROM jsonb_to_recordset(coalesce(b->'jogadores','[]'::jsonb)) AS t(vinculo_id int,camisola_id int,titular boolean,goleiro boolean) LOOP
   INSERT INTO jogo.convocado(jogo_id,vinculo_id,camisola_id,equipa_id,pessoa_id,numero,titular,goleiro,estado) VALUES(jid,item.vinculo_id,item.camisola_id,0,0,1,coalesce(item.titular,false),coalesce(item.goleiro,false),'BANCO');
  END LOOP;
  FOR v IN SELECT unnest(ARRAY[j.casa_id,j.fora_id]) LOOP
   IF (SELECT count(*) FROM jogo.convocado WHERE jogo_id=jid AND equipa_id=v AND estado='EM_CAMPO') NOT BETWEEN 3 AND 5 THEN RAISE EXCEPTION 'Cada equipa deve ter entre 3 e 5 titulares'; END IF;
   IF (SELECT count(*) FROM jogo.convocado WHERE jogo_id=jid AND equipa_id=v AND estado='EM_CAMPO' AND goleiro)<>1 THEN RAISE EXCEPTION 'Escolher um único guarda-redes titular por equipa'; END IF;
  END LOOP;
 WHEN 'REMOVER_CONVOCADO' THEN IF j.estado<>'AGENDADO' THEN RAISE EXCEPTION 'Convocatória fechada após início'; END IF;DELETE FROM jogo.convocado WHERE jogo_id=jid AND id=(b->>'id')::int;
 WHEN 'PREPARAR_SEGURANCA' THEN
 IF j.estado NOT IN('AGENDADO','ADIADO') THEN RAISE EXCEPTION 'Agendar antes de preparar segurança'; END IF;
 UPDATE seguranca.operacao SET responsavel_id=(b->>'responsavel_id')::int WHERE id=oid;
 INSERT INTO seguranca.efetivo VALUES(oid,(b->>'responsavel_id')::int) ON CONFLICT DO NOTHING;
 FOR v IN SELECT value::int FROM jsonb_array_elements_text(coalesce(b->'agentes','[]')) LOOP INSERT INTO seguranca.efetivo VALUES(oid,v) ON CONFLICT DO NOTHING; END LOOP;
 WHEN 'INICIAR_SEGURANCA' THEN UPDATE seguranca.operacao SET estado='EM_CURSO',inicio=coalesce((b->>'instante')::timestamptz,clock_timestamp()) WHERE id=oid AND estado='PLANEADA' AND responsavel_id IS NOT NULL;IF NOT FOUND THEN RAISE EXCEPTION 'Preparar responsável da operação'; END IF;
 WHEN 'OCORRENCIA' THEN
 IF NOT EXISTS(SELECT 1 FROM seguranca.operacao WHERE id=oid AND estado='EM_CURSO') THEN RAISE EXCEPTION 'Operação não está em curso'; END IF;
 IF length(trim(coalesce(b->>'descricao','')))<5 THEN RAISE EXCEPTION 'Descrição: indicar pelo menos 5 caracteres'; END IF;
 IF length(trim(coalesce(b->>'envolvidos','')))<2 THEN RAISE EXCEPTION 'Envolvidos: indicar pessoas ou grupo envolvido'; END IF;
 IF length(trim(coalesce(b->>'evidencia','')))<1 THEN RAISE EXCEPTION 'Indicar número do auto ou outra referência'; END IF;
 IF coalesce((b->>'feridos')::int,0)<0 THEN RAISE EXCEPTION 'Número de feridos inválido'; END IF;
 IF coalesce((b->>'feridos')::int,0)>0 AND length(trim(coalesce(b->>'assistencia','')))<3 THEN RAISE EXCEPTION 'Com feridos, indicar a assistência prestada'; END IF;
 IF coalesce((b->>'uso_forca')::boolean,false) AND length(trim(coalesce(b->>'justificacao_forca','')))<5 THEN RAISE EXCEPTION 'Com uso da força, indicar justificação e meios utilizados'; END IF;
 INSERT INTO seguranca.ocorrencia(operacao_id,instante,descricao,envolvidos,evidencia,sha256,feridos,assistencia,uso_forca,justificacao_forca) VALUES(oid,coalesce((b->>'instante')::timestamptz,clock_timestamp()),trim(b->>'descricao'),trim(b->>'envolvidos'),trim(b->>'evidencia'),encode(digest(trim(b->>'evidencia'),'sha256'),'hex'),coalesce((b->>'feridos')::int,0),nullif(trim(coalesce(b->>'assistencia','')),''),coalesce((b->>'uso_forca')::boolean,false),nullif(trim(coalesce(b->>'justificacao_forca','')),''));
 WHEN 'FINALIZAR_SEGURANCA' THEN
 IF j.estado<>'FINALIZADO' THEN RAISE EXCEPTION 'A operacao de seguranca so pode ser finalizada depois de o jogo estar FINALIZADO'; END IF;
 UPDATE seguranca.operacao SET estado='FINALIZADA',fim=coalesce((b->>'instante')::timestamptz,clock_timestamp()),avaliacao=b->>'avaliacao' WHERE id=oid AND estado='EM_CURSO';
 IF NOT FOUND THEN RAISE EXCEPTION 'Operacao nao esta em curso'; END IF;
 WHEN 'EVENTO' THEN eid:=jogo.emitir(jid,b->>'tipo',(b->>'periodo')::int,(b->>'segundos')::int,(b->>'equipa_id')::int,(b->>'jogador_id')::int,(b->>'entra_id')::int,coalesce(b->'detalhe','{}'));RETURN jsonb_build_object('id',eid);
 WHEN 'HOMOLOGAR' THEN CALL competicao.homologar(jid,coalesce(b->>'motivo','Homologação administrativa explícita'));
 WHEN 'SIMULAR' THEN CALL jogo.simular(jid);
 WHEN 'SIMULAR_JORNADA' THEN FOR x IN SELECT id FROM competicao.jogo WHERE jornada_id=j.jornada_id AND estado='AGENDADO' ORDER BY id LOOP CALL jogo.simular(x.id); END LOOP;
 ELSE RAISE EXCEPTION 'Comando desconhecido';
 END CASE;
 RETURN jsonb_build_object('ok',true);
END $$;
CREATE FUNCTION app.rpc(t text,a text,b jsonb DEFAULT '{}') RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public AS $$
DECLARE u integer; out jsonb; closed_object text; closed_id integer; original jsonb; rejected_id uuid;
BEGIN
 PERFORM set_config('nexus.correlation',gen_random_uuid()::text,true);
 PERFORM set_config('nexus.intent','',true);PERFORM set_config('nexus.engine','off',true);
 SELECT s.utilizador_id INTO u FROM app.sessao s JOIN app.utilizador x ON x.id=s.utilizador_id WHERE s.token_hash=digest(t,'sha256') AND s.expira>now() AND x.ativo;
 PERFORM set_config('nexus.actor',coalesce(u::text,''),true);
 IF u IS NULL THEN
 IF a IN('SUPER','SUPER_DETALHE','INTEGRIDADE') THEN INSERT INTO auditoria.meta(utilizador_id,correlacao,acao,alvo,permitido) VALUES(NULL,app.correlation(),a,'SEM_SESSAO',false);PERFORM forense.registar('ACESSO_NEGADO',jsonb_build_object('acao',a,'sessao',false)); END IF;
 RETURN jsonb_build_object('erro','Autenticação necessária','status',CASE WHEN a IN('SUPER','SUPER_DETALHE','INTEGRIDADE') THEN 403 ELSE 401 END);
 END IF;
 PERFORM set_config('nexus.session',encode(digest(t,'sha256'),'hex'),true);
 IF (SELECT mudar_password FROM app.utilizador WHERE id=u) AND a NOT IN('ME','PASSWORD','LOGOUT') THEN RETURN '{"erro":"Alterar password no primeiro acesso","status":428}'; END IF;
 BEGIN out:=app.command(u,a,b);
 EXCEPTION WHEN OTHERS THEN
 PERFORM forense.registar('COMANDO_REJEITADO',jsonb_build_object('utilizador',u,'acao',a,'pedido',b-'password'-'nova','erro',SQLERRM,'sqlstate',SQLSTATE));
 IF a IN('RECINTO','ARBITRAGEM','CONVOCAR','GUARDAR_CONVOCATORIA','EVENTO','HOMOLOGAR','AGENDAR','ADIAR','PREPARAR_SEGURANCA','INICIAR_SEGURANCA','OCORRENCIA','FINALIZAR_SEGURANCA') THEN
 IF a IN('PREPARAR_SEGURANCA','INICIAR_SEGURANCA','OCORRENCIA','FINALIZAR_SEGURANCA') THEN
 SELECT 'SEGURANCA',s.id,to_jsonb(s) INTO closed_object,closed_id,original FROM seguranca.operacao s WHERE jogo_id=(b->>'jogo_id')::int AND estado='FINALIZADA';
 ELSE SELECT 'JOGO',s.id,to_jsonb(s) INTO closed_object,closed_id,original FROM competicao.v_jogos_resultados s WHERE id=(b->>'jogo_id')::int AND estado='HOMOLOGADO'; END IF;
 IF original IS NOT NULL THEN
 INSERT INTO auditoria.intencao(utilizador_id,objeto,objeto_id,motivo,original) VALUES(u,closed_object,closed_id,'Tentativa direta sobre objeto fechado: '||a,original) RETURNING id INTO rejected_id;
 INSERT INTO auditoria.desfecho(intencao_id,resultado,detalhe) VALUES(rejected_id,'REJEITADA',jsonb_build_object('pedido',b,'erro',SQLERRM,'sqlstate',SQLSTATE));
 END IF;
 END IF;
 RETURN jsonb_build_object('erro',SQLERRM,'status',409);
 END;
 RETURN out;
END $$;
CREATE FUNCTION app.login(mail text,pw text) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public AS $$
DECLARE u app.utilizador; t text;
BEGIN
 PERFORM set_config('nexus.correlation',gen_random_uuid()::text,true);
 SELECT * INTO u FROM app.utilizador WHERE lower(email)=lower(trim(mail)) AND ativo;
 IF u.id IS NULL OR crypt(pw,u.password_hash) IS DISTINCT FROM u.password_hash THEN PERFORM forense.registar('LOGIN_NEGADO',jsonb_build_object('email',mail));RETURN '{"erro":"Credenciais inválidas","status":401}'; END IF;
 t:=encode(gen_random_bytes(32),'hex');INSERT INTO app.sessao(token_hash,utilizador_id) VALUES(digest(t,'sha256'),u.id);
 PERFORM forense.registar('LOGIN',jsonb_build_object('utilizador',u.id));RETURN jsonb_build_object('token',t,'mudar_password',u.mudar_password);
END $$;
CREATE FUNCTION app.health() RETURNS jsonb LANGUAGE sql SECURITY DEFINER SET search_path=pg_catalog,public AS $$ SELECT jsonb_build_object('product','NEXUS-CUP','version','V1.0','schema',EXISTS(SELECT 1 FROM app.versao WHERE versao='V1.0'),'datasets',(SELECT count(*) FROM competicao.epoca),'db_port',current_setting('port')::int) $$;
COMMIT;
