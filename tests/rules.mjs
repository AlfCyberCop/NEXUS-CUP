import pg from 'pg';
import {readFile,writeFile} from 'node:fs/promises';
import assert from 'node:assert/strict';
import {createApplication} from '../backend/server.js';
const cfg=JSON.parse(await readFile('.runtime/test.json','utf8'));
const {server}=createApplication({db:{host:'127.0.0.1',port:55432,user:cfg.user,password:cfg.password,database:cfg.database},key:cfg.key});await new Promise(r=>server.listen(0,'127.0.0.1',r));
const base='http://127.0.0.1:'+server.address().port;let cookie='';const results=[];
async function req(path,body,status=200){const r=await fetch(base+'/api/'+path,{method:body?'POST':'GET',headers:{Cookie:cookie,'Content-Type':'application/json'},body:body?JSON.stringify(body):undefined});const d=await r.json();assert.equal(r.status,status,JSON.stringify(d));if(r.headers.has('set-cookie'))cookie=r.headers.get('set-cookie').split(';')[0];return d;}
const cmd=(acao,dados,status)=>req('command',{acao,dados},status);
async function prepare(jid){
 await cmd('AGENDAR',{jogo_id:jid,inicio:`2026-11-${String(jid).padStart(2,'0')}T15:00:00Z`});
 await cmd('ARBITRAGEM',{jogo_id:jid,pessoa_id:33,funcao:'ARBITRO'});await cmd('PREPARAR_SEGURANCA',{jogo_id:jid,responsavel_id:37});await cmd('INICIAR_SEGURANCA',{jogo_id:jid});
 let s=await req('jogo?jogo_id='+jid);for(const p of s.elegiveis)await cmd('CONVOCAR',{jogo_id:jid,vinculo_id:p.vinculo_id,camisola_id:p.camisola_id,titular:p.numero<=5,goleiro:p.numero===1});
 s=await req('jogo?jogo_id='+jid);
 const h=n=>s.convocados.find(x=>x.equipa_id===s.jogo.casa_id&&x.numero===n),f=n=>s.convocados.find(x=>x.equipa_id===s.jogo.fora_id&&x.numero===n);
 const e=(tipo,segundos,p,ent,status=200)=>cmd('EVENTO',{jogo_id:jid,tipo,periodo:1,segundos,equipa_id:p?.equipa_id||ent?.equipa_id,jogador_id:p?.id,entra_id:ent?.id,detalhe:{autorizado_por:'CRONOMETRISTA'}},status);
 return {h,f,e,load:()=>req('jogo?jogo_id='+jid)};
}
async function test(name,fn){try{await fn();results.push({name,result:'PASS'});console.log('PASS',name);}catch(e){results.push({name,result:'FAIL',error:e.stack});console.error('FAIL',name,e.message);}}
try{
 await req('login',{email:'Paulo.ramalho@nexuscup.pt',password:process.env.NEXUS_BOOTSTRAP_PASSWORD});await cmd('PASSWORD',{nova:'TesteRegras!'+Date.now()});
 await test('FIFA: 4×4 e golo não libertam redução; dois minutos efetivos libertam',async()=>{const {h,f,e,load}=await prepare(15);await e('INICIO',0);await e('VERMELHO_DIRETO',10,h(2));await e('VERMELHO_DIRETO',10,f(2));await e('GOLO',30,h(3));let s=await load();assert(s.reducoes.every(x=>x.libertada_em===null));await e('RELOGIO',130);s=await load();assert(s.reducoes.every(x=>x.libertada_em===130&&x.causa==='TEMPO'));await e('REPOSICAO',130,null,h(6));await e('REPOSICAO',130,null,f(6));});
 await test('FIFA: 5×3 liberta apenas um lugar por golo',async()=>{const {h,f,e,load}=await prepare(16);await e('INICIO',0);await e('VERMELHO_DIRETO',10,f(2));await e('VERMELHO_DIRETO',10,f(3));await e('GOLO',30,h(2));let s=await load();assert.equal(s.reducoes.filter(x=>x.libertada_em!==null).length,1);await e('REPOSICAO',30,null,f(6));await e('REPOSICAO',30,null,f(7),409);await e('GOLO',40,h(2));s=await load();assert.equal(s.reducoes.filter(x=>x.libertada_em!==null).length,2);});
 await test('FIFA: 4×3 liberta um lugar quando marca a equipa com quatro',async()=>{const {h,f,e,load}=await prepare(17);await e('INICIO',0);await e('VERMELHO_DIRETO',10,h(2));await e('VERMELHO_DIRETO',10,f(2));await e('VERMELHO_DIRETO',10,f(3));await e('GOLO',30,h(3));const s=await load();assert.equal(s.reducoes.filter(x=>x.libertada_em!==null).length,1);assert.equal(s.reducoes.find(x=>x.libertada_em!==null).equipa_id,f(2).equipa_id);});
 await test('FIFA: golo da equipa em inferioridade não liberta; expulsão de suplente não reduz',async()=>{const {h,f,e,load}=await prepare(18);await e('INICIO',0);await e('VERMELHO_DIRETO',10,h(2));await e('VERMELHO_DIRETO',10,f(6));await e('GOLO',30,h(3));const s=await load();assert.equal(s.reducoes.length,1);assert.equal(s.reducoes[0].libertada_em,null);});
 await test('FIFA: 3×3 e golo não libertam qualquer redução',async()=>{const {h,f,e,load}=await prepare(19);await e('INICIO',0);for(const p of [h(2),h(3),f(2),f(3)])await e('VERMELHO_DIRETO',10,p);await e('GOLO',30,h(4));assert((await load()).reducoes.every(x=>x.libertada_em===null));});
 await test('Simulador via API termina a 40:00, sem homologar nem fechar segurança',async()=>{const {load}=await prepare(20);await cmd('SIMULAR',{jogo_id:20});const s=await load();assert.equal(s.jogo.estado,'FINALIZADO');assert.equal(s.jogo.periodo,2);assert.equal(s.jogo.segundos,1200);assert.equal(s.seguranca.estado,'EM_CURSO');assert.equal(s.resultados.length,0);assert(s.eventos.some(x=>x.tipo==='SUBSTITUICAO'));});
 await test('FIFA: menos de três jogadores interrompe e bloqueia retoma',async()=>{const {h,e,load}=await prepare(21);await e('INICIO',0);for(const p of [h(2),h(3),h(4)])await e('VERMELHO_DIRETO',10,p);assert.equal((await load()).jogo.estado,'INTERROMPIDO');await e('RETOMA',10,null,null,409);});
 await test('Arbitragem: nomeação em períodos sobrepostos rejeitada',async()=>{await cmd('AGENDAR',{jogo_id:22,inicio:'2026-11-15T15:30:00Z'});await cmd('ARBITRAGEM',{jogo_id:22,pessoa_id:33,funcao:'ARBITRO'},409);});
 await test('Pós-fecho: tentativa direta rejeitada também gera RED persistente',async()=>{const before=(await req('super')).red_flags.length;await cmd('RECINTO',{jogo_id:1,recinto_id:2,motivo:'Tentativa fora do fluxo explícito'},409);const after=(await req('super')).red_flags;assert.equal(after.length,before+1);assert(after.some(x=>x.motivo.includes('Tentativa direta')&&x.resultado==='REJEITADA'));});
}catch(e){results.push({name:'EXECUÇÃO',result:'FAIL',error:e.stack});console.error(e);}finally{await writeFile('test-results/rules.json',JSON.stringify(results,null,2));await new Promise(r=>server.close(r));process.exitCode=results.some(x=>x.result==='FAIL')?1:0;}
