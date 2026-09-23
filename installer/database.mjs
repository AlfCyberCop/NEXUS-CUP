import pg from 'pg';
import {readFile,readdir} from 'node:fs/promises';
import {randomBytes} from 'node:crypto';
import {root} from '../backend/config.mjs';
export async function baseline(client,key){
 const occupied=await client.query("select nspname from pg_namespace where nspname in ('app','nucleo','competicao')");
 if(occupied.rowCount)throw Error('Base de dados já contém schema de aplicação. Instalação limpa exige BD nova; nenhum dado foi alterado.');
 await client.query('BEGIN');
 try{
 await client.query("select set_config('nexus.key',$1,true)",[key]);
 for(const name of (await readdir(root+'database')).filter(n=>/^0[1-5]_.*\.sql$/.test(n)).sort()){
 const sql=(await readFile(root+'database/'+name,'utf8')).replace(/^BEGIN;\s*|^COMMIT;\s*/gm,'');
 await client.query(sql);
 }
 await client.query('COMMIT');
 }catch(e){await client.query('ROLLBACK');throw e;}
}
export async function runtimeRole(client){
 const role='nexuscup_'+randomBytes(6).toString('hex'),password=randomBytes(32).toString('hex');
 await client.query(`CREATE ROLE ${role} LOGIN PASSWORD '${password}' NOSUPERUSER NOCREATEDB NOCREATEROLE NOINHERIT`);
 await client.query(`REVOKE ALL ON ALL TABLES IN SCHEMA app,nucleo,clubes,competicao,jogo,seguranca,arbitragem,auditoria,forense FROM PUBLIC;
 REVOKE ALL ON ALL FUNCTIONS IN SCHEMA app,nucleo,clubes,competicao,jogo,seguranca,arbitragem,auditoria,forense FROM PUBLIC;
 REVOKE ALL ON ALL PROCEDURES IN SCHEMA competicao,jogo FROM PUBLIC;
 GRANT USAGE ON SCHEMA app TO ${role}; GRANT EXECUTE ON FUNCTION app.rpc(text,text,jsonb),app.login(text,text),app.health() TO ${role};`);
 return {user:role,password};
}
