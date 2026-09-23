import pg from 'pg';
import {randomBytes} from 'node:crypto';
import {readFile,readdir,stat,mkdir,cp,rm} from 'node:fs/promises';
import path from 'node:path';
import {pathToFileURL} from 'node:url';
import {createRequire} from 'node:module';
import {baseline,runtimeRole} from './database.mjs';
import {createApplication} from '../backend/server.js';
import {root,build} from '../backend/config.mjs';
export async function validateDatabase(c,{fresh=false}={}){
 const count=(sql)=>c.query(sql).then(r=>Number(r.rows[0].n));
 if(await count("select count(*) n from app.versao where versao='V1.0' and produto='NEXUS-CUP'")!==1)throw Error('Versão inválida');
 if(await count('select count(*) n from competicao.epoca')!==2)throw Error('Datasets incompletos');
 if(fresh){
 if(await count("select count(*) n from competicao.jogo where epoca_id=1 and estado='HOMOLOGADO'")!==12)throw Error('Histórica incompleta');
 if(await count("select count(*) n from competicao.epoca where id=1 and estado='FINALIZADA' and classificacao_final is not null and campeao_id is not null")!==1)throw Error('Época histórica não ficou formalmente FINALIZADA');
 if(await count("select count(*) n from competicao.epoca where id=2 and estado='ABERTA'")!==1)throw Error('Época corrente deveria estar ABERTA');
 if(await count("select count(*) n from competicao.jogo where epoca_id=2 and estado='AGENDADO'")!==1 || await count("select count(*) n from competicao.jogo where epoca_id=2 and estado='NAO_AGENDADO'")!==11)throw Error('Estado inicial da NEXUS CUP inválido');
 if(await count('select count(*) n from app.utilizador')!==4)throw Error('Utilizadores base incompletos');
 if(await count('select count(*) n from app.utilizador where mudar_password')!==2)throw Error('Primeiro acesso inválido');
 if(await count("select count(*) n from app.utilizador where lower(email) in ('jose.silva@nexuscup.pt','adalberto.costa@nexuscup.pt') and mudar_password=false and crypt('1234567890.ABC',password_hash)=password_hash")!==2)throw Error('Credenciais permanentes de José/Adalberto inválidas');
 if(await count("select count(*) n from app.super_autorizado")!==2 || await count("select count(*) n from app.super_autorizado sa join app.utilizador u on u.id=sa.utilizador_id where lower(u.email) in ('alfcybercop@nexuscup.pt','paulo.ramalho@nexuscup.pt')")!==2)throw Error('SUPER_AUDITOR deve ficar apenas em Alf e Paulo');
 if(await count("select count(*) n from auditoria.desfecho d where d.resultado='EXECUTADA' and d.detalhe->'pedido'->>'tipo'='CARTAO_VERMELHO'")<1)throw Error('Incidente de cartão vermelho da Super Auditoria ausente');
 if(await count("select count(*) n from auditoria.desfecho d where d.resultado='REJEITADA' and d.detalhe->'pedido'->>'tipo'='GOLO'")<1)throw Error('Tentativa bloqueada sobre resultado ausente');
 }
 if(await count('select count(*) n from competicao.jogo j left join seguranca.operacao o on o.jogo_id=j.id where o.id is null')!==0)throw Error('Jogo sem segurança');
 if(!(await c.query('select forense.verificar() r')).rows[0].r.integra)throw Error('Cadeia forense inválida');
 if(await count(`select count(*) n from competicao.v_jogos_resultados j join lateral (select * from competicao.resultado where jogo_id=j.id order by versao desc limit 1) r on true where r.casa<>j.golos_casa or r.fora<>j.golos_fora`)!==0)throw Error('Resultado oficial divergente');
 const pw=randomBytes(24).toString('hex');await c.query('BEGIN');try{
 const u=await c.query("insert into app.utilizador(nome,email,password_hash) values('Verificação de instalação','probe@installation.invalid',crypt($1,gen_salt('bf',12))) returning id",[pw]);
 const auth=await c.query("select app.login('probe@installation.invalid',$1) r",[pw]);if(!auth.rows[0].r.token||!auth.rows[0].r.mudar_password)throw Error('Falha na autenticação');
 }finally{await c.query('ROLLBACK');}
}
const require=createRequire(import.meta.url);
export const reportName='NEXUS-CUP V1.0 - Relatório Técnico.pdf';
class InstallError extends Error {}
const fail=message=>{throw new InstallError(message);};
const exists=async file=>{try{await stat(file);return true;}catch(e){if(e.code==='ENOENT')return false;throw e;}};
export function normalizeOptions(input){
 const o={mode:'complete',destination:'C:\\temp\\NEXUSCUP',host:'localhost',port:5432,database:'nexuscup',user:'postgres',replaceDatabase:false,...input};o.port=Number(o.port);o.replaceDatabase=o.replaceDatabase===true;
 if(!['complete','database','application'].includes(o.mode))fail('Tipo de instalação inválido.');
 if(!Number.isInteger(o.port)||o.port<1||o.port>65535||o.port===6666||(o.port===55432&&o.test!==true))fail('Porta inválida; 55432 exige modo de testes explícito.');
 if(!/^[a-z][a-z0-9_]{2,50}$/.test(o.database))fail('BD: usar 3 a 51 letras minúsculas, números ou underscore, começando por letra.');
 if(typeof o.host!=='string'||!o.host.trim()||/[\s\/\\\u0000]/.test(o.host))fail('Indicar hostname ou IP PostgreSQL válido.');
 if(typeof o.user!=='string'||!o.user.trim())fail('Indicar utilizador PostgreSQL.');
 if(typeof o.destination!=='string'||!path.isAbsolute(o.destination))fail('Escolher diretório de destino absoluto.');
 o.destination=path.resolve(o.destination);return o;
}
const connection=o=>({host:o.host,port:o.port,user:o.user,password:o.password,database:o.database,connectionTimeoutMillis:8000,query_timeout:15000});
export function publicError(e){
 if(e instanceof InstallError)return e.message;
 if(e.code==='28P01'||e.code==='28000')return 'Autenticação PostgreSQL recusada. Verifique utilizador e password.';
 if(['ECONNREFUSED','ENOTFOUND','ETIMEDOUT','EHOSTUNREACH'].includes(e.code))return 'PostgreSQL indisponível. Verifique host, porta e acesso de rede.';
 if(e.code==='3D000')return 'A base de dados indicada não existe.';
 if(e.code==='42501')return 'Permissões PostgreSQL insuficientes para esta operação.';
 return 'Operação não concluída. Verifique ligação, permissões e compatibilidade. Se autorizou REPOR BD, consulte a recuperação protegida antes de repetir.';
}
export async function checkConnection(input){
 const o=normalizeOptions(input);
 if(o.mode!=='application')fail('Teste de ligação disponível no modo Apenas Aplicação.');
 if(typeof o.key!=='string'||o.key.length<32)fail('Importar a configuração DPAPI da BD ou indicar a chave forense original.');
 const c=new pg.Client(connection(o));
 try{
 await c.connect();await c.query('BEGIN READ ONLY');
 const h=(await c.query('SELECT app.health() r')).rows[0].r;
 if(h.product!=='NEXUS-CUP'||h.version!=='V1.0'||h.schema!==true)fail('BD incompatível com NEXUS-CUP V1.0.');
 const compatible=(await c.query("SELECT count(*)::int n FROM pg_attribute a JOIN pg_class c ON c.oid=a.attrelid JOIN pg_namespace n ON n.oid=c.relnamespace WHERE n.nspname='competicao' AND c.relname='epoca' AND a.attname IN('estado','classificacao_final','campeao_id','finalizada_em','finalizada_por') AND NOT a.attisdropped")).rows[0].n;
 if(compatible!==5)fail('BD anterior ao fecho da Liga. Usar uma BD compatível com esta versão.');
 const role=(await c.query('SELECT rolsuper,rolcreatedb,rolcreaterole,rolbypassrls FROM pg_roles WHERE rolname=current_user')).rows[0];
 const direct=(await c.query("SELECT count(*)::int n FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace WHERE c.relkind IN('r','p') AND n.nspname IN('app','nucleo','clubes','competicao','jogo','arbitragem','seguranca','auditoria','forense') AND has_table_privilege(current_user,c.oid,'SELECT,INSERT,UPDATE,DELETE,TRUNCATE')")).rows[0].n;
 if(Object.values(role).some(Boolean)||direct)fail('Usar a conta runtime restrita criada pelo instalador, não uma conta administrativa.');
 for(const fn of ['app.rpc(text,text,jsonb)','app.login(text,text)','app.health()'])if(!(await c.query('SELECT has_function_privilege(current_user,$1,\'EXECUTE\') ok',[fn])).rows[0].ok)fail('Conta sem permissões de acesso NEXUS-CUP.');
 await c.query('ROLLBACK');return {ok:true,validated:true,product:h.product,version:h.version,message:'Ligação, autenticação PostgreSQL e compatibilidade validadas.'};
 }finally{await c.end();}
}
export async function planInstallation(input){
 const o=normalizeOptions(input),source=path.resolve(root);
 if(o.destination.toLowerCase()===source.toLowerCase())fail('Escolher uma pasta de destino diferente da origem.');
 let destinationState='new',destinationWarning=null;
 if(await exists(o.destination)){
   const info=await stat(o.destination);
   if(!info.isDirectory()||info.isSymbolicLink())fail('O destino tem de ser uma pasta normal.');
   const entries=await readdir(o.destination);
   if(entries.length){
     let recognized=false;
     try{
       const pkg=JSON.parse(await readFile(path.join(o.destination,'package.json'),'utf8'));
       recognized=pkg?.name==='nexus-cup';
     }catch{}
     if(!recognized)recognized=(await exists(path.join(o.destination,'INSTALAR.cmd')))&&(await exists(path.join(o.destination,'installer')));
     destinationState=recognized?'nexuscup':'nonempty';
     destinationWarning=recognized
       ?'Instalação NEXUS-CUP existente: os ficheiros do produto serão atualizados; .runtime e a BD não são apagados.'
       :'A pasta contém outros ficheiros. Apenas ficheiros com os mesmos nomes do NEXUS-CUP poderão ser substituídos; os restantes serão preservados.';
   } else destinationState='empty';
 }
 let databaseExists=false;
 if(o.mode!=='application'){
   const admin=new pg.Client({...connection(o),database:'postgres'});
   try{await admin.connect();databaseExists=(await admin.query('SELECT 1 FROM pg_database WHERE datname=$1',[o.database])).rowCount>0;}finally{await admin.end();}
 }
 const reportPresent=await exists(path.join(root,'docs',reportName));
 const warnings=[];
 if(destinationWarning)warnings.push(destinationWarning);
 if(databaseExists)warnings.push(`A BD ${o.database} já existe. Só será eliminada e recriada após confirmação explícita de reposição.`);
 if(!reportPresent)warnings.push('Relatório Técnico PDF ausente; a instalação pode continuar.');
 return {ok:true,mode:o.mode,destination:o.destination,host:o.host,port:o.port,database:o.database,user:o.user,reportPresent,destinationState,databaseExists,warnings};
}
// Copy only installed production packages; never copy runtime, logs, pgdata or dev dependencies.
async function copyProductionDependencies(destination){
 const seen=new Set();
 async function copyPackage(name,from){
 const resolve=createRequire(from);let folder=path.dirname(resolve.resolve(name));
 while(true){const meta=path.join(folder,'package.json');if(await exists(meta)){const pkg=JSON.parse(await readFile(meta,'utf8'));if(pkg.name===name){
 if(seen.has(name))return;seen.add(name);
 await cp(folder,path.join(destination,'node_modules',name),{recursive:true,force:true,errorOnExist:false,filter:file=>!path.relative(folder,file).split(path.sep).includes('node_modules')});
 for(const dep of Object.keys(pkg.dependencies||{}))await copyPackage(dep,meta);return;
 }}const parent=path.dirname(folder);if(parent===folder)fail('Dependência indisponível. Executar npm ci na origem.');folder=parent;}
 }
 await copyPackage('pg',path.join(root,'package.json'));
}
export async function copyPayload(o,{resetProductFiles=false}={}){
 await mkdir(o.destination,{recursive:true});
 if(resetProductFiles){
  // Reinstalação reconhecida: remover apenas o subconjunto do produto que este modo vai repor.
  // .runtime e ficheiros alheios ao NEXUS-CUP são preservados.
  const stale=o.mode==='database'?['database']:o.mode==='application'?['backend','frontend','installer','node_modules']:['backend','frontend','installer','database','node_modules'];
  for(const name of stale)await rm(path.join(o.destination,name),{recursive:true,force:true});
 }
 const files=o.mode==='database'?['database','BUILD.txt']:o.mode==='application'?['backend','frontend','installer','package.json','package-lock.json','INSTALAR.cmd','INICIAR.cmd','BUILD.txt']:['backend','frontend','installer','database','package.json','package-lock.json','INSTALAR.cmd','INICIAR.cmd','BUILD.txt'];
 for(const file of files)await cp(path.join(root,file),path.join(o.destination,file),{recursive:true,errorOnExist:false,force:true});
 if(o.mode!=='database')await copyProductionDependencies(o.destination);
 const report=path.join(root,'docs',reportName);
 if(await exists(report)){await cp(report,path.join(o.destination,reportName),{errorOnExist:false,force:true});return path.join(o.destination,reportName);}
 return null;
}
async function validateApplication(settings){
 const app=createApplication({db:connection(settings),key:settings.key});
 try{
 await new Promise((resolve,reject)=>{app.server.once('error',reject);app.server.listen(0,'127.0.0.1',resolve);});
 const url='http://127.0.0.1:'+app.server.address().port;
 const health=await fetch(url+'/api/health').then(r=>r.json());if(health.product!=='NEXUS-CUP'||!health.schema||health.build!==build)fail('Health/build inválido.');
 if(!(await fetch(url).then(r=>r.text())).includes('NEXUS-CUP V1.0'))fail('Frontend indisponível.');
 if((await fetch(url+'/api/me')).status!==401)fail('Sessão anónima não bloqueada.');
 }finally{if(app.server.listening)await new Promise(r=>app.server.close(r));else await app.pool.end();}
}
export async function install(input){
 const o=normalizeOptions(input),plan=await planInstallation(o);let settings,created=false;
 // Validate existing DB before creating any application files.
 if(o.mode==='application')await checkConnection(o);
 const reportPath=await copyPayload(o,{resetProductFiles:plan.destinationState==='nexuscup'});
 try{
 if(o.mode==='application')settings={host:o.host,port:o.port,database:o.database,user:o.user,password:o.password,key:o.key};
 else{
 const admin=new pg.Client({...connection(o),database:'postgres'});
 try{
   await admin.connect();
   const dbExists=(await admin.query('SELECT 1 FROM pg_database WHERE datname=$1',[o.database])).rowCount>0;
   if(dbExists){
     if(!o.replaceDatabase)fail('A BD já existe. Volte à configuração e autorize explicitamente a reposição da BD.');
     await admin.query('SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE datname=$1 AND pid<>pg_backend_pid()',[o.database]);
     await admin.query(`DROP DATABASE "${o.database}"`);
   }
   await admin.query(`CREATE DATABASE "${o.database}"`);created=true;
 }finally{await admin.end();}
 settings={host:o.host,port:o.port,database:o.database,key:randomBytes(48).toString('hex')};
 const c=new pg.Client(connection(o));
 try{await c.connect();await baseline(c,settings.key);await c.query("SELECT set_config('nexus.key',$1,false)",[settings.key]);await validateDatabase(c,{fresh:true});Object.assign(settings,await runtimeRole(c));}finally{await c.end();}
 }
 Object.assign(settings,{appPort:3000,test:o.test===true,product:'NEXUS-CUP',version:'V1.0',build,mode:o.mode,validated:true});
 if(o.mode!=='database')await validateApplication(settings);
 return {...settings,ok:true,destination:o.destination,reportPath,warnings:plan.warnings};
 }catch(e){return {ok:false,error:publicError(e),destination:o.destination,recovery:created?settings:undefined};}
}
async function main(){
 let input='';for await(const chunk of process.stdin)input+=chunk;
 try{const o=JSON.parse(input);const result=o.action==='check'?await checkConnection(o):o.action==='plan'?await planInstallation(o):await install(o);process.stdout.write(JSON.stringify(result));if(result.ok===false)process.exitCode=1;}
 catch(e){process.stdout.write(JSON.stringify({ok:false,error:publicError(e)}));process.exitCode=1;}
}
if(process.argv[1]&&import.meta.url===pathToFileURL(process.argv[1]).href)main();
