import pg from 'pg';
import assert from 'node:assert/strict';
import {randomBytes} from 'node:crypto';
import {mkdir,readFile,writeFile} from 'node:fs/promises';
import {chromium} from 'playwright-core';
import {baseline,runtimeRole} from '../installer/database.mjs';
import {createApplication} from '../backend/server.js';

// Two directed checks only. Fresh canonical test DB; no existing dataset is reset.
const uiOnly=process.argv.includes('--ui-only');
const previous=uiOnly?JSON.parse(await readFile('test-results/season-close.json','utf8')):null;
const saved=uiOnly?JSON.parse(await readFile('.runtime/season-close.json','utf8')):null;
const results=previous?previous.results.filter(r=>r.result==='PASS'):[];
const key=saved?.key||randomBytes(48).toString('hex'),password='Season!'+randomBytes(18).toString('hex');
const database=saved?.database||'nexuscup_season_'+Date.now();
if(uiOnly)assert.equal(database,previous.database);
const connection={host:'127.0.0.1',port:55432,user:'postgres'};
let owner,server,browser,base,cookie='',adminCookie,redIntent,goalIntent,red,goal,closed;
async function req(path,body,status=200){
 const r=await fetch(base+'/api/'+path,{method:body?'POST':'GET',headers:{Cookie:cookie,'Content-Type':'application/json'},body:body?JSON.stringify(body):undefined});
 const d=await r.json();assert.equal(r.status,status,JSON.stringify(d));
 if(r.headers.has('set-cookie'))cookie=r.headers.get('set-cookie').split(';')[0];return d;
}
const cmd=(acao,dados,status)=>req('command',{acao,dados},status);
async function directed(name,fn){await fn();results.push({name,result:'PASS'});console.log('PASS',name);}
async function sqlRejected(sql,values=[]){
 await owner.query('BEGIN');
 try{await assert.rejects(owner.query(sql,values),/FINALIZADA|imutável/);}finally{await owner.query('ROLLBACK');}
}
try{
 const cluster=new pg.Client({...connection,database:'postgres'});await cluster.connect();
 try{const dir=(await cluster.query('show data_directory')).rows[0].data_directory.replaceAll('\\','/').toLowerCase();assert(dir.endsWith('/nexuscup/.test_pgdata'));if(!uiOnly)await cluster.query(`CREATE DATABASE ${database}`);}finally{await cluster.end();}
 owner=new pg.Client({...connection,database});await owner.connect();if(!uiOnly)await baseline(owner,key);
 const runtime=saved?{user:saved.user,password:saved.password}:await runtimeRole(owner);
 // Isolated login fixture: generated password, never logged or included in evidence.
 await owner.query("UPDATE app.utilizador SET password_hash=crypt($1,gen_salt('bf',12)),mudar_password=false WHERE id=1",[password]);
 const email=(await owner.query('SELECT email FROM app.utilizador WHERE id=1')).rows[0].email;
 await mkdir('.runtime',{recursive:true});await writeFile('.runtime/season-close.json',JSON.stringify({database,key,...runtime}));
 ({server}=createApplication({db:{...connection,...runtime,database},key}));await new Promise(r=>server.listen(0,'127.0.0.1',r));base='http://127.0.0.1:'+server.address().port;
 await req('login',{email,password});adminCookie=cookie;

 if(!uiOnly)await directed('Liga: fecho, RBAC, imutabilidade e dois incidentes reais via HTTP/RPC',async()=>{
  await cmd('FINALIZAR_EPOCA',{epoca_id:2},409);
  assert.equal((await req('dashboard?epoca_id=2')).epoca.estado,'ABERTA');
  const standings=await req('relatorio?epoca_id=1&tipo=classificacao');
  assert(standings.length>1);
  closed=(await cmd('FINALIZAR_EPOCA',{epoca_id:1})).epoca;
  assert.equal(closed.estado,'FINALIZADA');assert.equal(closed.campeao_id,standings[0].equipa_id);
  assert.deepEqual(closed.classificacao_final,standings);assert.equal(closed.finalizada_por,1);assert(closed.finalizada_em);
  const dashboard=await req('dashboard?epoca_id=1');assert.equal(dashboard.estados.HOMOLOGADO,12);assert.equal(dashboard.seguranca_aberta,0);
  const fecho=(await owner.query("SELECT * FROM auditoria.operacional WHERE tabela='competicao.epoca' AND depois->>'estado'='FINALIZADA'")).rows;
  assert.equal(fecho.length,1);assert.equal(fecho[0].antes.estado,'ABERTA');
  await cmd('FINALIZAR_EPOCA',{epoca_id:1},409);
  await cmd('RECINTO',{jogo_id:1,recinto_id:2,motivo:'Operação normal após fecho'},409);
  await cmd('EVENTO',{jogo_id:1,tipo:'GOLO',periodo:2,segundos:1200},409);
  await sqlRejected("UPDATE competicao.epoca SET estado='ABERTA' WHERE id=1");
  await sqlRejected('UPDATE competicao.jornada SET numero=numero WHERE epoca_id=1');
  await sqlRejected('INSERT INTO competicao.inscricao(epoca_id,equipa_id) VALUES(1,1)');
  await sqlRejected('UPDATE jogo.evento SET detalhe=detalhe WHERE jogo_id=1');
  await sqlRejected('UPDATE competicao.resultado SET casa=casa+1 WHERE jogo_id=1');
  const eventsBefore=(await owner.query('SELECT * FROM jogo.evento WHERE jogo_id IN(1,3) ORDER BY id')).rows;
  const resultsBefore=(await owner.query('SELECT * FROM competicao.resultado WHERE jogo_id IN(1,3) ORDER BY id')).rows;
  const onFieldBefore=(await owner.query('SELECT * FROM jogo.convocado WHERE jogo_id=3 ORDER BY id')).rows;
  red=(await req('jogo?jogo_id=3')).eventos.find(e=>['VERMELHO_DIRETO','EXPULSAO_SEGUNDO_AMARELO'].includes(e.tipo));assert(red);
  goal=(await req('jogo?jogo_id=1')).eventos.find(e=>e.tipo==='GOLO'&&e.valido);assert(goal);

  // Real controlled revision; operational/forensic evidence comes only from the system.
  redIntent=(await cmd('INTENCAO',{objeto:'JOGO',objeto_id:3,motivo:'Cenário real: revisão posterior do cartão vermelho na Liga fechada'})).id;
  await cmd('RETIFICAR',{intencao_id:redIntent,tipo:'CARTAO_VERMELHO',evento_id:red.id,valido:false});
  const redDetail=await req('super/detalhe?id='+redIntent);
  assert.equal(redDetail.desfecho.resultado,'EXECUTADA');assert.equal(redDetail.desfecho.detalhe.evento.antes.valido,true);assert.equal(redDetail.desfecho.detalhe.evento.depois.valido,false);
  assert.equal(redDetail.intencao.utilizador_id,1);assert.equal(redDetail.intencao.objeto_id,3);assert(redDetail.desfecho.criado_em);
  assert(redDetail.auditoria.some(e=>e.tabela==='jogo.revisao'));assert(redDetail.forense.length>0);assert(redDetail.integridade.integra);
  assert.equal((await req('jogo?jogo_id=3')).eventos.find(e=>e.id===red.id).valido,false);
  // Attempt the existing goal correction command; guard rejects it and retains outcome.
  goalIntent=(await cmd('INTENCAO',{objeto:'JOGO',objeto_id:1,motivo:'Cenário real: tentativa de alterar resultado da Liga fechada'})).id;
  const denied=await cmd('RETIFICAR',{intencao_id:goalIntent,tipo:'GOLO',evento_id:goal.id,valido:false},409);assert.equal(denied.resultado,'REJEITADA');
  const goalDetail=await req('super/detalhe?id='+goalIntent);assert.equal(goalDetail.desfecho.resultado,'REJEITADA');assert.match(goalDetail.desfecho.detalhe.erro,/resultado oficial protegido/);assert(goalDetail.forense.length>0);
  assert.deepEqual((await owner.query('SELECT * FROM jogo.evento WHERE jogo_id IN(1,3) ORDER BY id')).rows,eventsBefore);
  assert.deepEqual((await owner.query('SELECT * FROM competicao.resultado WHERE jogo_id IN(1,3) ORDER BY id')).rows,resultsBefore);
  assert.deepEqual((await owner.query('SELECT * FROM jogo.convocado WHERE jogo_id=3 ORDER BY id')).rows,onFieldBefore);
  assert.deepEqual((await req('dashboard?epoca_id=1')).epoca,closed);
  assert.deepEqual(await req('relatorio?epoca_id=1&tipo=classificacao'),standings);
  // Existing extraordinary venue correction remains usable and audited after closing.
  const venue=(await cmd('INTENCAO',{objeto:'JOGO',objeto_id:1,motivo:'Correção documental do recinto após fecho'})).id;
  await cmd('RETIFICAR',{intencao_id:venue,tipo:'RECINTO',recinto_id:2});
  for(const role of ['LEITOR','ADMIN']){
   const userEmail=role.toLowerCase()+'-season@example.test';
   await cmd('CRIAR_UTILIZADOR',{nome:'Conta dirigida '+role,email:userEmail,password,role});
   await req('login',{email:userEmail,password});await cmd('PASSWORD',{nova:password+'N1!'});
   await req('super',undefined,403);await req('super/detalhe?id='+redIntent,undefined,403);
   if(role==='LEITOR')await cmd('FINALIZAR_EPOCA',{epoca_id:2},403);
   else{const id=(await cmd('INTENCAO',{objeto:'JOGO',objeto_id:3,motivo:'Verificar restrição da revisão de vermelho'})).id;await cmd('RETIFICAR',{intencao_id:id,tipo:'CARTAO_VERMELHO',evento_id:red.id,valido:true},409);}
   cookie=adminCookie;
  }
  assert((await req('super/integridade')).integra);
 });

 if(uiOnly){redIntent=previous.incidentes.vermelho;goalIntent=previous.incidentes.resultado;closed=(await req('dashboard?epoca_id=1')).epoca;red=(await req('super/detalhe?id='+redIntent)).desfecho.detalhe.evento.antes;}
 await directed('UI: Liga FINALIZADA, campeão, revisão de vermelho e drilldown dos dois incidentes',async()=>{
  browser=await chromium.launch({channel:'msedge',headless:true});const page=await browser.newPage({viewport:{width:1440,height:1000}}),errors=[];
  page.on('pageerror',e=>errors.push(e.message));
  await page.goto(base);await page.getByLabel('Email',{exact:true}).fill(email);await page.getByLabel('Password',{exact:true}).fill(password);await page.getByRole('button',{name:'Entrar',exact:true}).click();await page.locator('#shell').waitFor({state:'visible'});
  await page.locator('#season').selectOption('1');await page.getByRole('heading',{name:/FINALIZADA/}).waitFor();
  assert((await page.locator('#content').innerText()).includes(closed.classificacao_final[0].nome));assert((await page.locator('#content').innerText()).includes('12/12 jogos aplicáveis homologados · 100%'));
  assert.equal(await page.locator('[data-action="close-season"]').count(),0);
  await page.locator('[data-view="jogos"]').click();await page.locator('[data-game="3"]').click();await page.getByRole('button',{name:'Entrar em retificação',exact:true}).waitFor();assert.equal(await page.locator('[data-action="event"]').count(),0);
  await page.getByRole('button',{name:'Entrar em retificação',exact:true}).click();await page.getByLabel('Motivo',{exact:true}).fill('Verificar seleção de vermelho preservando o estado final');await page.getByRole('button',{name:'Guardar',exact:true}).click();
  await page.getByLabel('Evento a retificar',{exact:true}).waitFor();await page.getByLabel('Evento a retificar',{exact:true}).selectOption(String(red.id));assert((await page.getByLabel('Evento a retificar',{exact:true}).innerText()).includes(red.tipo));await page.getByRole('button',{name:'Cancelar',exact:true}).click();await page.locator('#modal').waitFor({state:'hidden'});
  await page.locator('[data-view="super"]').click();
  for(const [id,label] of [[redIntent,'VERMELHO DETETADO'],[goalIntent,'RESULTADO BLOQUEADO']])await page.locator('tr').filter({has:page.locator('[data-action="drill"][data-id="'+id+'"]')}).getByRole('cell',{name:label,exact:true}).waitFor();
  await mkdir('test-results/season-close',{recursive:true});await page.screenshot({path:'test-results/season-close/super.png',fullPage:true});
  for(const [id,expected] of [[redIntent,'Decisão posterior ao jogo'],[goalIntent,'resultado oficial protegido']]){
   await page.locator('[data-action="drill"][data-id="'+id+'"]').click();await page.locator('#modal pre').waitFor();assert((await page.locator('#modal pre').innerText()).includes(expected));await page.getByRole('button',{name:'Fechar',exact:true}).click();
  }
  assert.deepEqual(errors,[]);assert((await req('super/integridade')).integra);
 });
}catch(e){results.push({name:'Execução dirigida',result:'FAIL',error:e.message});console.error('FAIL',e.message);process.exitCode=1;}
finally{
 if(browser)await browser.close();if(server)await new Promise(r=>server.close(r));if(owner)await owner.end();
 await mkdir('test-results',{recursive:true});await writeFile('test-results/season-close.json',JSON.stringify({database,results,incidentes:{vermelho:redIntent,resultado:goalIntent}},null,2));
}
