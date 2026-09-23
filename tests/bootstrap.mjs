import pg from 'pg';
import {randomBytes} from 'node:crypto';
import {mkdir,writeFile} from 'node:fs/promises';
import {baseline,runtimeRole} from '../installer/database.mjs';
const admin=new pg.Client({host:'127.0.0.1',port:55432,user:'postgres',database:'postgres'});await admin.connect();
const dir=await admin.query('show data_directory');if(!dir.rows[0].data_directory.replaceAll('\\','/').toLowerCase().endsWith('/nexuscup/.test_pgdata'))throw Error('Cluster não pertence à árvore canónica');
const db='nexuscup_test_'+Date.now();await admin.query(`CREATE DATABASE ${db}`);await admin.end();
const c=new pg.Client({host:'127.0.0.1',port:55432,user:'postgres',database:db});await c.connect();
const key=randomBytes(48).toString('hex');
try{await baseline(c,key); const runtime=await runtimeRole(c);await mkdir('.runtime',{recursive:true});await writeFile('.runtime/test.json',JSON.stringify({database:db,key,...runtime}));console.log('BASELINE_OK',db);}finally{await c.end();}
