BEGIN;
CREATE FUNCTION jogo.validar_evento() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE j competicao.jogo; p jogo.convocado; q jogo.convocado; n integer; t integer; r jogo.reducao;
BEGIN
 SELECT * INTO j FROM competicao.jogo WHERE id=NEW.jogo_id FOR UPDATE;
 IF j.id IS NULL THEN RAISE EXCEPTION 'Jogo inexistente'; END IF;
 SELECT coalesce(max(seq),0)+1 INTO n FROM jogo.evento WHERE jogo_id=j.id;
 IF NEW.seq IS NOT NULL AND NEW.seq<>n THEN RAISE EXCEPTION 'Sequência inválida'; END IF; NEW.seq:=n;
 IF NEW.equipa_id IS NOT NULL AND NEW.equipa_id NOT IN(j.casa_id,j.fora_id) THEN RAISE EXCEPTION 'Equipa fora do jogo'; END IF;
 SELECT * INTO p FROM jogo.convocado WHERE id=NEW.jogador_id AND jogo_id=j.id;
 SELECT * INTO q FROM jogo.convocado WHERE id=NEW.entra_id AND jogo_id=j.id;
 IF NEW.tipo='INICIO' THEN
 IF j.estado<>'AGENDADO' OR NEW.periodo<>1 OR NEW.segundos<>0 THEN RAISE EXCEPTION 'Início inválido'; END IF;
 IF NOT EXISTS(SELECT 1 FROM seguranca.operacao o WHERE o.jogo_id=j.id AND o.estado='EM_CURSO' AND o.responsavel_id IS NOT NULL) OR NOT EXISTS(SELECT 1 FROM arbitragem.nomeacao WHERE jogo_id=j.id AND funcao='ARBITRO') THEN RAISE EXCEPTION 'Preparar segurança e arbitragem'; END IF;
 FOR n IN SELECT unnest(ARRAY[j.casa_id,j.fora_id]) LOOP
 IF (SELECT count(*) FROM jogo.convocado WHERE jogo_id=j.id AND equipa_id=n AND estado='EM_CAMPO') NOT BETWEEN 3 AND 5 OR (SELECT count(*) FROM jogo.convocado WHERE jogo_id=j.id AND equipa_id=n AND estado='EM_CAMPO' AND goleiro)<>1 THEN RAISE EXCEPTION 'Selecionar 3 a 5 titulares incluindo um guarda-redes por equipa'; END IF;
 END LOOP;
 ELSIF NEW.tipo='RETOMA' THEN
 IF j.estado<>'INTERROMPIDO' OR NEW.periodo<>j.periodo OR NEW.segundos<>j.segundos THEN RAISE EXCEPTION 'Retoma deve preservar instante'; END IF;
 IF EXISTS(SELECT 1 FROM (SELECT unnest(ARRAY[j.casa_id,j.fora_id]) eq) x WHERE (SELECT count(*) FROM jogo.convocado WHERE jogo_id=j.id AND equipa_id=x.eq AND estado='EM_CAMPO')<3) THEN RAISE EXCEPTION 'Menos de três jogadores: não retomar'; END IF;
 ELSIF NEW.tipo='SEGUNDA_PARTE' THEN
 IF j.estado<>'EM_CURSO' OR NOT j.intervalo OR NEW.periodo<>2 OR NEW.segundos<>0 THEN RAISE EXCEPTION 'Segunda parte exige intervalo'; END IF;
 ELSE
 IF j.estado<>'EM_CURSO' OR j.intervalo OR NEW.periodo<>j.periodo OR NEW.segundos<j.segundos THEN RAISE EXCEPTION 'Estado ou relógio inválido'; END IF;
 END IF;
 IF NEW.tipo='INTERVALO' AND (NEW.periodo<>1 OR NEW.segundos<>1200) THEN RAISE EXCEPTION 'Intervalo aos 20:00'; END IF;
 IF NEW.tipo='FIM' AND (NEW.periodo<>2 OR NEW.segundos<>1200) THEN RAISE EXCEPTION 'Finalização regulamentar apenas aos 40:00'; END IF;
 IF NEW.tipo IN('GOLO','FALTA','AMARELO','VERMELHO_DIRETO','EXPULSAO_SEGUNDO_AMARELO','SUBSTITUICAO') THEN
 IF p.id IS NULL OR p.equipa_id IS DISTINCT FROM NEW.equipa_id OR p.estado='EXPULSO' THEN RAISE EXCEPTION 'Jogador não elegível para evento'; END IF;
 IF NEW.tipo IN('GOLO','FALTA','SUBSTITUICAO') AND p.estado<>'EM_CAMPO' THEN RAISE EXCEPTION 'Jogador não está em campo'; END IF;
 END IF;
 IF NEW.tipo='AMARELO' AND (SELECT count(*) FROM jogo.evento WHERE jogador_id=p.id AND tipo='AMARELO')>=2 THEN RAISE EXCEPTION 'Dois amarelos já registados'; END IF;
 IF NEW.tipo='EXPULSAO_SEGUNDO_AMARELO' AND (NEW.relacionado_id IS NULL OR NOT EXISTS(SELECT 1 FROM jogo.evento WHERE id=NEW.relacionado_id AND jogador_id=p.id AND tipo='AMARELO') OR (SELECT count(*) FROM jogo.evento WHERE jogador_id=p.id AND tipo='AMARELO')<>2) THEN RAISE EXCEPTION 'Expulsão exige segundo amarelo'; END IF;
 IF NEW.tipo='SUBSTITUICAO' AND (q.id IS NULL OR q.estado<>'BANCO' OR q.equipa_id<>p.equipa_id) THEN RAISE EXCEPTION 'Entrada exige suplente elegível da mesma equipa'; END IF;
 IF NEW.tipo='FALTA' AND coalesce(NEW.detalhe->>'classe','') NOT IN('DIRETO','INDIRETO') THEN RAISE EXCEPTION 'Indicar falta de livre direto ou indireto'; END IF;
 t:=(NEW.periodo-1)*1200+NEW.segundos;
 UPDATE jogo.reducao SET libertada_em=inicio+120,causa='TEMPO' WHERE jogo_id=j.id AND libertada_em IS NULL AND inicio+120<=t;
 IF NEW.tipo='REPOSICAO' THEN
 SELECT * INTO r FROM jogo.reducao WHERE jogo_id=j.id AND equipa_id=NEW.equipa_id AND libertada_em IS NOT NULL AND entrada_evento IS NULL ORDER BY id LIMIT 1 FOR UPDATE;
 IF r.id IS NULL OR q.id IS NULL OR q.equipa_id IS DISTINCT FROM NEW.equipa_id OR q.estado<>'BANCO' OR coalesce(NEW.detalhe->>'autorizado_por','') NOT IN('CRONOMETRISTA','TERCEIRO_ARBITRO') THEN RAISE EXCEPTION 'Reposição exige redução cumprida, suplente e autorização oficial'; END IF;
 IF (SELECT count(*) FROM jogo.convocado WHERE jogo_id=j.id AND equipa_id=q.equipa_id AND estado='EM_CAMPO')>=5 THEN RAISE EXCEPTION 'Máximo cinco jogadores'; END IF;
 END IF;
 PERFORM set_config('nexus.engine','on',true);
 UPDATE competicao.jogo SET periodo=NEW.periodo,segundos=NEW.segundos,
 estado=CASE NEW.tipo WHEN 'INICIO' THEN 'EM_CURSO' WHEN 'RETOMA' THEN 'EM_CURSO' WHEN 'INTERRUPCAO' THEN 'INTERROMPIDO' WHEN 'FIM' THEN 'FINALIZADO' ELSE estado END,
 intervalo=CASE NEW.tipo WHEN 'INTERVALO' THEN true WHEN 'SEGUNDA_PARTE' THEN false ELSE intervalo END WHERE id=j.id;
 RETURN NEW;
END $$;
CREATE TRIGGER b_validar_evento BEFORE INSERT ON jogo.evento FOR EACH ROW EXECUTE FUNCTION jogo.validar_evento();
CREATE FUNCTION jogo.aplicar_evento() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE p jogo.convocado; n integer; adversario integer; nc integer; nf integer; rid bigint;
BEGIN
 PERFORM set_config('nexus.engine','on',true);
 SELECT * INTO p FROM jogo.convocado WHERE id=NEW.jogador_id;
 IF NEW.tipo='SUBSTITUICAO' THEN
 UPDATE jogo.convocado SET estado='BANCO' WHERE id=NEW.jogador_id;
 UPDATE jogo.convocado SET estado='EM_CAMPO' WHERE id=NEW.entra_id;
 ELSIF NEW.tipo IN('VERMELHO_DIRETO','EXPULSAO_SEGUNDO_AMARELO') THEN
 IF p.estado='EM_CAMPO' THEN INSERT INTO jogo.reducao(jogo_id,equipa_id,evento_id,inicio) VALUES(NEW.jogo_id,NEW.equipa_id,NEW.id,(NEW.periodo-1)*1200+NEW.segundos); END IF;
 UPDATE jogo.convocado SET estado='EXPULSO' WHERE id=p.id;
 IF (SELECT count(*) FROM jogo.convocado WHERE jogo_id=NEW.jogo_id AND equipa_id=p.equipa_id AND estado='EM_CAMPO')<3 THEN
 INSERT INTO jogo.evento(jogo_id,periodo,segundos,tipo,relacionado_id,detalhe) VALUES(NEW.jogo_id,NEW.periodo,NEW.segundos,'INTERRUPCAO',NEW.id,'{"motivo":"Menos de três jogadores"}'); END IF;
 ELSIF NEW.tipo='AMARELO' THEN
 IF (SELECT count(*) FROM jogo.evento WHERE jogador_id=p.id AND tipo='AMARELO')=2 THEN
 INSERT INTO jogo.evento(jogo_id,periodo,segundos,tipo,equipa_id,jogador_id,relacionado_id,incidente) VALUES(NEW.jogo_id,NEW.periodo,NEW.segundos,'EXPULSAO_SEGUNDO_AMARELO',NEW.equipa_id,p.id,NEW.id,NEW.incidente); END IF;
 ELSIF NEW.tipo='GOLO' THEN
 SELECT CASE WHEN casa_id=NEW.equipa_id THEN fora_id ELSE casa_id END INTO adversario FROM competicao.jogo WHERE id=NEW.jogo_id;
 SELECT count(*) INTO nc FROM jogo.convocado WHERE jogo_id=NEW.jogo_id AND equipa_id=NEW.equipa_id AND estado='EM_CAMPO';
 SELECT count(*) INTO nf FROM jogo.convocado WHERE jogo_id=NEW.jogo_id AND equipa_id=adversario AND estado='EM_CAMPO';
 IF (nc=5 AND nf IN(3,4)) OR (nc=4 AND nf=3) THEN
 SELECT id INTO rid FROM jogo.reducao WHERE jogo_id=NEW.jogo_id AND equipa_id=adversario AND libertada_em IS NULL ORDER BY id LIMIT 1 FOR UPDATE;
 UPDATE jogo.reducao SET libertada_em=(NEW.periodo-1)*1200+NEW.segundos,causa='GOLO:'||NEW.id WHERE id=rid;
 END IF;
 ELSIF NEW.tipo='REPOSICAO' THEN
 SELECT id INTO rid FROM jogo.reducao WHERE jogo_id=NEW.jogo_id AND equipa_id=NEW.equipa_id AND libertada_em IS NOT NULL AND entrada_evento IS NULL ORDER BY id LIMIT 1 FOR UPDATE;
 UPDATE jogo.reducao SET entrada_evento=NEW.id WHERE id=rid;
 UPDATE jogo.convocado SET estado='EM_CAMPO' WHERE id=NEW.entra_id;
 END IF;
 RETURN NEW;
END $$;
CREATE TRIGGER m_aplicar_evento AFTER INSERT ON jogo.evento FOR EACH ROW EXECUTE FUNCTION jogo.aplicar_evento();
CREATE PROCEDURE competicao.homologar(jid integer,motivo text) LANGUAGE plpgsql AS $$
DECLARE j record;
BEGIN
 PERFORM 1 FROM competicao.jogo WHERE id=jid FOR UPDATE;
 IF NOT coalesce((competicao.readiness(jid)->>'pronto')::boolean,false) THEN RAISE EXCEPTION 'Homologação bloqueada: %',competicao.readiness(jid)->'motivos'; END IF;
 SELECT * INTO j FROM competicao.v_jogos_resultados WHERE id=jid;
 INSERT INTO competicao.resultado(jogo_id,versao,casa,fora,motivo,utilizador_id) VALUES(jid,1,j.golos_casa,j.golos_fora,motivo,app.actor());
 PERFORM set_config('nexus.engine','on',true);
 UPDATE competicao.jogo SET estado='HOMOLOGADO' WHERE id=jid;
END $$;
CREATE FUNCTION jogo.emitir(jid integer,tipo text,periodo integer,segundos integer,equipa integer DEFAULT NULL,jogador integer DEFAULT NULL,entra integer DEFAULT NULL,detalhe jsonb DEFAULT '{}') RETURNS bigint LANGUAGE plpgsql AS $$
DECLARE eid bigint;
BEGIN INSERT INTO jogo.evento(jogo_id,tipo,periodo,segundos,equipa_id,jogador_id,entra_id,detalhe) VALUES(jid,tipo,periodo,segundos,equipa,jogador,entra,detalhe) RETURNING id INTO eid;RETURN eid;END $$;
CREATE PROCEDURE jogo.simular(jid integer) LANGUAGE plpgsql AS $$
DECLARE j competicao.jogo; c integer[]; f integer[];
BEGIN
 SELECT * INTO j FROM competicao.jogo WHERE id=jid FOR UPDATE;
 SELECT array_agg(id ORDER BY numero) INTO c FROM jogo.convocado WHERE jogo_id=jid AND equipa_id=j.casa_id;
 SELECT array_agg(id ORDER BY numero) INTO f FROM jogo.convocado WHERE jogo_id=jid AND equipa_id=j.fora_id;
 IF array_length(c,1)<7 OR array_length(f,1)<7 THEN RAISE EXCEPTION 'Simulador exige convocatórias preparadas com sete jogadores por equipa'; END IF;
 PERFORM jogo.emitir(jid,'INICIO',1,0);
 PERFORM jogo.emitir(jid,'GOLO',1,235,j.casa_id,c[2]);
 PERFORM jogo.emitir(jid,'FALTA',1,480,j.fora_id,f[2],NULL,'{"classe":"DIRETO"}');
 PERFORM jogo.emitir(jid,'AMARELO',1,480,j.fora_id,f[2]);
 PERFORM jogo.emitir(jid,'SUBSTITUICAO',1,600,j.casa_id,c[3],c[6]);
 PERFORM jogo.emitir(jid,'INTERVALO',1,1200);
 PERFORM jogo.emitir(jid,'SEGUNDA_PARTE',2,0);
 IF mod(jid,3)=0 THEN
 PERFORM jogo.emitir(jid,'AMARELO',2,135,j.fora_id,f[2]);
 PERFORM jogo.emitir(jid,'GOLO',2,170,j.casa_id,c[2]);
 PERFORM jogo.emitir(jid,'REPOSICAO',2,170,j.fora_id,NULL,f[6],'{"autorizado_por":"CRONOMETRISTA"}');
 ELSE PERFORM jogo.emitir(jid,'GOLO',2,170,j.fora_id,f[3]); END IF;
 PERFORM jogo.emitir(jid,'SUBSTITUICAO',2,450,j.casa_id,c[6],c[3]);
 PERFORM jogo.emitir(jid,'FALTA',2,540,j.casa_id,c[4],NULL,'{"classe":"INDIRETO"}');
 IF mod(jid,2)=0 THEN PERFORM jogo.emitir(jid,'GOLO',2,800,j.casa_id,c[4]); END IF;
 PERFORM jogo.emitir(jid,'FIM',2,1200);
END $$;
COMMIT;
