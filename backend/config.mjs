import {readFileSync} from 'node:fs';
import {fileURLToPath} from 'node:url';
export const root=fileURLToPath(new URL('../',import.meta.url));
export const build='NX15-20260920';
export function configuration(env=process.env){
 const port=Number(env.PGPORT||5432);
 if(!Number.isInteger(port)||port<1||port>65535||port===6666) throw Error('Porta PostgreSQL não permitida');
 if(port===55432 && env.NEXUS_TEST!=='1') throw Error('Porta de testes exige NEXUS_TEST=1');
 const appPort=Number(env.PORT||3000);if(!Number.isInteger(appPort)||appPort<1024||appPort>65535||appPort===6666)throw Error('Porta HTTP não permitida');
 if(!env.NEXUS_FORENSIC_KEY || env.NEXUS_FORENSIC_KEY.length<32)throw Error('Chave forense necessária');
 return {db:{host:env.PGHOST||'localhost',port,user:env.PGUSER,password:env.PGPASSWORD,database:env.PGDATABASE||'nexuscup',max:8},key:env.NEXUS_FORENSIC_KEY,port:appPort};
}
