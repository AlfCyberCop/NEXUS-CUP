import http from 'node:http';
import {readFile} from 'node:fs/promises';
import {pathToFileURL} from 'node:url';
import {createHash} from 'node:crypto';
import pg from 'pg';
import {configuration,root,build} from './config.mjs';

export function createApplication(config){
 const pool=new pg.Pool(config.db),limiter=new Map();
 async function db(fn){const c=await pool.connect();try{await c.query('BEGIN');await c.query("SELECT set_config('nexus.key',$1,true)",[config.key]);const result=await fn(c);await c.query('COMMIT');return result;}catch(e){await c.query('ROLLBACK');throw e;}finally{c.release();}}
 const rpc=(token,action,data)=>db(async c=>(await c.query('SELECT app.rpc($1,$2,$3) result',[token,action,data])).rows[0].result);
 const cookie=t=>`nexus_sid=${t}; Path=/; HttpOnly; SameSite=Strict; Max-Age=${t?43200:0}`;
 const send=(res,status,data,headers={})=>{res.writeHead(status,{'Content-Type':'application/json; charset=utf-8','Cache-Control':'no-store','X-Content-Type-Options':'nosniff','X-Frame-Options':'DENY','Referrer-Policy':'no-referrer','Content-Security-Policy':"default-src 'self'; script-src 'self'; style-src 'self'; frame-ancestors 'none'; base-uri 'none'; form-action 'self'",...headers});res.end(typeof data==='string'?data:JSON.stringify(data));};
 const server=http.createServer(async(req,res)=>{
 try{
 const url=new URL(req.url,'http://localhost');
 if(!['127.0.0.1','localhost'].includes((req.headers.host||'').split(':')[0]))return send(res,403,{erro:'Host não permitido'});
 if(req.method==='POST' && req.headers.origin && req.headers.origin!==`http://${req.headers.host}`)return send(res,403,{erro:'Origem não permitida'});
 if(url.pathname==='/api/health'){
 const health=await db(async c=>(await c.query('SELECT app.health() result')).rows[0].result);
 return send(res,200,{...health,build,instance:createHash('sha256').update(root).digest('hex').slice(0,16)});
 }
 if(!url.pathname.startsWith('/api/')){
 const files={'/':'index.html','/app.js':'app.js','/style.css':'style.css'};if(!files[url.pathname])return send(res,404,{erro:'Não encontrado'});
 const ext=url.pathname.endsWith('.js')?'text/javascript':url.pathname.endsWith('.css')?'text/css':'text/html';
 return send(res,200,await readFile(root+'frontend/'+files[url.pathname],'utf8'),{'Content-Type':ext+'; charset=utf-8'});
 }
 let data={};if(req.method==='POST'){let buf='';for await(const chunk of req){buf+=chunk;if(buf.length>65536)return send(res,413,{erro:'Pedido demasiado grande'});}try{data=JSON.parse(buf||'{}');}catch{return send(res,400,{erro:'JSON inválido'});}}
 const token=(req.headers.cookie||'').split(';').map(s=>s.trim()).find(s=>s.startsWith('nexus_sid='))?.slice(10)||'';
 if(url.pathname==='/api/login' && req.method==='POST'){
 const ip=req.socket.remoteAddress;const now=Date.now();let bucket=limiter.get(ip);if(!bucket||now-bucket.since>60000){bucket={since:now,n:0};limiter.set(ip,bucket);}if(++bucket.n>20)return send(res,429,{erro:'Aguardar um minuto antes de repetir'});
 const result=await db(async c=>(await c.query('SELECT app.login($1,$2) result',[String(data.email||''),String(data.password||'')])).rows[0].result);
 if(result.erro)return send(res,result.status||400,result);bucket.n=0;const {token:t,...publicResult}=result;return send(res,200,publicResult,{'Set-Cookie':cookie(t)});
 }
 let action,args=data;
 if(url.pathname==='/api/command' && req.method==='POST'){action=String(data.acao||'');args=data.dados||{};}
 else if(req.method==='GET'){
 const routes={'/api/me':'ME','/api/catalogo':'CATALOGO','/api/jogos':'JOGOS','/api/jogo':'JOGO','/api/dashboard':'DASHBOARD','/api/planteis':'PLANTEIS','/api/relatorio':'RELATORIO','/api/super':'SUPER','/api/super/detalhe':'SUPER_DETALHE','/api/super/integridade':'INTEGRIDADE'};action=routes[url.pathname];args=Object.fromEntries(url.searchParams);
 }
 if(!action)return send(res,404,{erro:'Endpoint não encontrado'});
 const result=await rpc(token,action,args);
 return send(res,result?.status||200,result,action==='LOGOUT'?{'Set-Cookie':cookie('')}:{});
 }catch(e){console.error('Pedido falhou:',e.code||e.message);send(res,500,{erro:'Falha interna. Consultar registo local do servidor.'});}
 });
 server.on('close',()=>pool.end());return {server,pool,rpc};
}
if(process.argv[1] && import.meta.url===pathToFileURL(process.argv[1]).href){
 const config=configuration();const {server}=createApplication(config);
 server.on('error',e=>{console.error(`Não foi possível iniciar NEXUS-CUP: ${e.message}`);process.exitCode=1;});
 server.listen(config.port,'127.0.0.1',()=>console.log(`NEXUS-CUP V1.0 — http://127.0.0.1:${config.port}`));
}
