import assert from 'node:assert/strict';
import {readFile,writeFile,mkdir,stat} from 'node:fs/promises';
import path from 'node:path';
import {normalizeOptions,planInstallation,copyPayload,checkConnection} from '../installer/install.mjs';
import {configuration,root} from '../backend/config.mjs';

const results=[];
try{
 const defaults=normalizeOptions({});assert.equal(defaults.destination,'C:\\temp\\NEXUSCUP');assert.equal(defaults.host,'localhost');assert.equal(defaults.port,5432);assert.equal(defaults.database,'nexuscup');
 const parent=path.join(root,'.runtime','installer-smoke-'+Date.now());
 for(const mode of ['complete','database','application']){
  const o=normalizeOptions({mode,destination:path.join(parent,mode)}),plan=await planInstallation(o);
  assert(plan.ok);assert.equal(plan.mode,mode);assert.equal(plan.reportPresent,false);assert.equal(plan.warnings.length,1);
 }
 for(const mode of ['database','application']){
  const o=normalizeOptions({mode,destination:path.join(parent,mode)});assert.equal(await copyPayload(o),null);
  assert((await stat(path.join(o.destination,'database','01_schema.sql'))).isFile());
  await assert.rejects(planInstallation(o),/nova ou vazia/);
  if(mode==='application'){assert((await stat(path.join(o.destination,'node_modules','pg','package.json'))).isFile());await assert.rejects(stat(path.join(o.destination,'node_modules','playwright-core')));}
  await assert.rejects(stat(path.join(o.destination,'.runtime')));
 }
 assert.throws(()=>normalizeOptions({port:6666}));assert.throws(()=>normalizeOptions({port:55432}));
 assert.equal(normalizeOptions({host:'db.example.test',port:5433}).host,'db.example.test');
 assert.equal(configuration({PGHOST:'db.example.test',PGPORT:'5433',NEXUS_FORENSIC_KEY:'x'.repeat(48)}).db.host,'db.example.test');
 const saved=JSON.parse(await readFile('.runtime/season-close.json','utf8'));
 const check=await checkConnection({...saved,mode:'application',destination:path.join(parent,'connect'),host:'localhost',port:55432,test:true});
 assert(check.validated);assert.equal(check.product,'NEXUS-CUP');assert.equal(check.password,undefined);assert.equal(check.key,undefined);
 results.push({name:'Instalador texto/motor: preflight 3 modos, copia seletiva, PDF ausente e ligacao real sem instalar BD',result:'PASS'});
 console.log('PASS instalador: defaults, 3 modos, copia, PDF ausente, compatibilidade e autenticacao PostgreSQL');
}catch(e){results.push({name:'Smoke instalador',result:'FAIL',error:e.message});console.error('FAIL',e.message);process.exitCode=1;}
await mkdir('test-results',{recursive:true});await writeFile('test-results/installer-smoke.json',JSON.stringify(results,null,2));
