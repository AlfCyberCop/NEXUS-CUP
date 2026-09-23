import {readFile} from 'node:fs/promises';
import assert from 'node:assert/strict';
const read=p=>readFile(new URL('../'+p,import.meta.url),'utf8');
const [app,integrity,api,seed,installer,index,server,start]=await Promise.all([
 read('frontend/app.js'),read('database/02_integrity.sql'),read('database/04_api.sql'),read('database/05_seed.sql'),read('installer/install.mjs'),read('frontend/index.html'),read('backend/server.js'),read('installer/Start.ps1')
]);
const checks=[];
const ok=(name,fn)=>{fn();checks.push(name);};
ok('fixture locked in API',()=>{assert.match(api,/Emparelhamento definido pela jornada: Casa e Visitante não podem ser alterados/);assert.doesNotMatch(api,/SET casa_id=coalesce\(\(b->>'casa_id'/);});
ok('fixture locked by DB trigger',()=>assert.match(integrity,/época, jornada, casa e visitante não são alteráveis/));
ok('venue supports new record',()=>{assert.match(app,/Outro recinto \(não está na lista\)/);assert.match(api,/IF a='CRIAR_RECINTO'/);});
ok('single goalkeeper UI',()=>{assert.match(app,/Guarda-redes titular/);assert.match(app,/GUARDAR_CONVOCATORIA/);assert.doesNotMatch(app,/name="keeper_\$\{x\.camisola_id\}"/);});
ok('goalkeeper/starter DB validation',()=>assert.match(api,/Escolher um único guarda-redes titular por equipa/));
ok('security cannot close before final whistle',()=>{assert.match(integrity,/operacao de seguranca so pode ser finalizada depois de o jogo estar FINALIZADO/);assert.match(api,/j\.estado<>'FINALIZADO'/);assert.match(app,/aguarda FIM do jogo/);});
ok('club team roster hierarchy',()=>{assert.match(app,/1 · CLUBE/);assert.match(app,/2 · EQUIPA/);assert.match(app,/3 · PLANTEL/);assert.match(api,/'clubes'/);});
ok('report centre expanded',()=>{for(const word of ['Resumo da competição','Classificação','Jogos e resultados','Resumo por jornadas','Marcadores','Disciplina','Faltas acumuladas','Arbitragem','Segurança','Plantéis','Integridade e auditoria'])assert.ok(app.includes(word),word);});
ok('four baseline users',()=>{for(const mail of ['alfcybercop@nexuscup.pt','paulo.ramalho@nexuscup.pt','jose.silva@nexuscup.pt','adalberto.costa@nexuscup.pt'])assert.ok(seed.toLowerCase().includes(mail));assert.ok(seed.includes('1234567890.ABC')===false,'plaintext permanent password must not be in seed');});
ok('historical league finalised and critical incidents seeded',()=>{assert.match(seed,/FINALIZAR_EPOCA/);assert.match(seed,/CARTAO_VERMELHO/);assert.match(seed,/resultado oficial após fecho da Liga/);assert.match(seed,/REJEITADA/);});
ok('installer replaces selected DB only with explicit flag',()=>{assert.match(installer,/replaceDatabase/);assert.match(installer,/DROP DATABASE/);assert.match(installer,/resetProductFiles/);});
ok('historical rosters are read-only',()=>{assert.match(app,/plantel histórico em modo de leitura/);assert.match(api,/Época FINALIZADA: plantel histórico em modo de leitura/);assert.match(api,/IF a='PLANTEIS'/);});
ok('security occurrence is user friendly',()=>{assert.match(app,/N.º do auto \/ referência/);assert.match(app,/campos adicionais só aparecem/);assert.match(api,/Indicar número do auto ou outra referência/);assert.match(seed,/INSERT INTO seguranca\.entidade/);});
ok('security navigation is direct',()=>{assert.match(app,/data-security-game/);assert.match(app,/Segurança da competição/);assert.match(app,/data-tab=\"\$\{targets\[i\]\}\"/);});
ok('super audit is readable',()=>{assert.match(app,/Intervenções críticas/);assert.match(app,/Atividade recente/);assert.match(app,/Ver detalhes técnicos \/ JSON/);});
ok('build sync marker',()=>{assert.match(index,/v=15/);assert.match(index,/NX15/);assert.match(server,/build/);assert.match(start,/expectedBuild/);});
console.log(JSON.stringify({ok:true,checks:checks.length,names:checks},null,2));
