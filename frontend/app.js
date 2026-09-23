const $=s=>document.querySelector(s),esc=s=>String(s??'').replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
let me,cat,view='dashboard',game,tab='JOGO',filter='',pendingIntent=null,selectedClubId=null,selectedTeamId=null,activeReport='resumo';
const writable=()=>me?.roles?.some(r=>['ADMIN','OPERADOR'].includes(r));
const admin=()=>me?.roles?.includes('ADMIN');
const season=()=>Number($('#season').value),round=()=>Number($('#round').value)||null;
const seasonObject=()=>cat?.epocas?.find(e=>Number(e.id)===season())||null;
const seasonClosed=()=>seasonObject()?.estado==='FINALIZADA';
const seasonWritable=()=>writable()&&!seasonClosed();
const time=j=>`${String(Math.floor(((j.periodo-1)*1200+j.segundos)/60)).padStart(2,'0')}:${String(j.segundos%60).padStart(2,'0')}`;
function notice(s){$('#message').textContent=s;$('#message').hidden=false;setTimeout(()=>$('#message').hidden=true,6500);}
async function api(path,body){const r=await fetch('/api/'+path,body?{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify(body)}:{});const data=await r.json();if(!r.ok)throw Error(data.erro||'Operação falhou');return data;}
const command=(acao,dados={})=>api('command',{acao,dados});
const opt=(list,value='id',label='nome',selected)=>list.map(x=>`<option value="${esc(x[value])}" ${String(x[value])===String(selected)?'selected':''}>${esc(x[label])}</option>`).join('');
function table(rows,columns){if(!rows?.length)return '<div class="panel muted">Sem registos neste contexto.</div>';return `<div class="tablewrap"><table><thead><tr>${columns.map(c=>`<th>${esc(c[0])}</th>`).join('')}</tr></thead><tbody>${rows.map(r=>`<tr>${columns.map(c=>`<td>${typeof c[1]==='function'?c[1](r):esc(r[c[1]])}</td>`).join('')}</tr>`).join('')}</tbody></table></div>`;}
const input=(name,label,type='text',value='',extra='')=>`<label>${esc(label)}<input name="${name}" type="${type}" value="${esc(value)}" ${extra}></label>`;
const select=(name,label,options)=>`<label for="field-${name}">${esc(label)}</label><select id="field-${name}" name="${name}">${options}</select>`;
const button=(action,label,extra='')=>`<button data-action="${action}" ${extra}>${label}</button>`;
const stateTone=s=>({HOMOLOGADO:'green',FINALIZADO:'blue',EM_CURSO:'blue',AGENDADO:'blue',ADIADO:'orange',INTERROMPIDO:'orange',NAO_AGENDADO:'gray',CANCELADO:'red'}[s]||'gray');
const statePill=s=>`<span class="pill ${stateTone(s)}-pill">${esc(String(s||'').replaceAll('_',' '))}</span>`;
const teamInitial=n=>esc(String(n||'?').trim().split(/\s+/).filter(Boolean).slice(0,2).map(x=>x[0]).join('').toUpperCase()||'?');
const fmtDate=v=>v?new Date(v).toLocaleString('pt-PT',{dateStyle:'short',timeStyle:'short'}):'—';
function updateContextHint(){const h=$('#roundHint');if(h)h.textContent=round()?`Jornada ${round()} ativa`:'Época completa';}
function roundFocus(rows){
 const n=round();if(!n)return '';
 const hom=rows.filter(x=>x.estado==='HOMOLOGADO').length,goals=rows.reduce((a,x)=>a+Number(x.golos_casa||0)+Number(x.golos_fora||0),0);
 return `<section class="round-focus"><div class="round-focus-head"><div><span class="eyebrow">FILTRO ATIVO</span><h2>Jornada ${esc(n)}</h2><p>O dashboard, os jogos e a segurança estão agora limitados a esta jornada.</p></div><button data-action="clear-round" class="secondary">Ver época completa</button></div><div class="round-focus-kpis"><span><b>${rows.length}</b> jogos</span><span><b>${hom}</b> homologados</span><span><b>${goals}</b> golos</span></div>${rows.length?`<div class="round-focus-games">${rows.map(r=>`<button data-game="${r.id}"><span>${esc(r.casa)}</span><b>${['FINALIZADO','HOMOLOGADO'].includes(r.estado)?`${r.golos_casa} – ${r.golos_fora}`:'VS'}</b><span>${esc(r.fora)}</span>${statePill(r.estado)}</button>`).join('')}</div>`:`<div class="empty-state"><b>Sem jogos</b><p>Esta jornada ainda não tem encontros disponíveis.</p></div>`}</section>`;
}
function clubCatalog(rows=[]){
 const fallbackNames=new Map();for(const r of rows)if(r.equipa_id&&r.clube)fallbackNames.set(Number(cat.equipas.find(e=>e.id===r.equipa_id)?.clube_id),r.clube);
 const ids=[...new Set(cat.equipas.map(e=>Number(e.clube_id)))];
 return ids.map(id=>({id,nome:cat.clubes?.find(c=>Number(c.id)===id)?.nome||fallbackNames.get(id)||`Clube ${id}`,equipas:cat.equipas.filter(e=>Number(e.clube_id)===id)})).sort((a,b)=>a.nome.localeCompare(b.nome,'pt'));
}
function teamMeta(teamId,rows=[]){const t=cat.equipas.find(e=>Number(e.id)===Number(teamId));if(!t)return null;const club=clubCatalog(rows).find(c=>c.id===Number(t.clube_id));const recinto=cat.recintos.find(r=>Number(r.id)===Number(t.recinto_id));return {...t,clube:club?.nome||'Clube',recinto:recinto?.nome||'Sem recinto'};}
function rosterManager(rows){
 const clubs=clubCatalog(rows);if(!clubs.length)return '<section class="panel"><p class="muted">Sem clubes/equipas disponíveis.</p></section>';
 if(!selectedClubId||!clubs.some(c=>c.id===Number(selectedClubId)))selectedClubId=clubs[0].id;
 const club=clubs.find(c=>c.id===Number(selectedClubId));
 if(!selectedTeamId||!club.equipas.some(t=>Number(t.id)===Number(selectedTeamId)))selectedTeamId=club.equipas[0]?.id||null;
 const team=teamMeta(selectedTeamId,rows);const players=rows.filter(r=>Number(r.equipa_id)===Number(selectedTeamId));
 const current=players.filter(r=>!r.fim||new Date(r.fim)>=new Date());
 const clubStrip=`<section class="hierarchy-panel"><div class="hierarchy-title"><div><span class="eyebrow">1 · CLUBE</span><h2>Escolher clube</h2></div><small>${clubs.length} clube${clubs.length===1?'':'s'}</small></div><div class="club-grid">${clubs.map(c=>{const n=rows.filter(r=>c.equipas.some(t=>t.id===r.equipa_id)).length;return `<button class="club-card ${c.id===Number(selectedClubId)?'selected':''}" data-club="${c.id}"><span class="club-mark">${teamInitial(c.nome)}</span><span><strong>${esc(c.nome)}</strong><small>${c.equipas.length} equipa${c.equipas.length===1?'':'s'} · ${n} vínculo${n===1?'':'s'}</small></span></button>`}).join('')}</div></section>`;
 const teamStrip=`<section class="hierarchy-panel"><div class="hierarchy-title"><div><span class="eyebrow">2 · EQUIPA</span><h2>${esc(club.nome)}</h2></div></div><div class="team-grid">${club.equipas.map(t=>{const n=rows.filter(r=>Number(r.equipa_id)===Number(t.id)&&r.funcao==='JOGADOR').length;const m=teamMeta(t.id,rows);return `<button class="team-card ${Number(t.id)===Number(selectedTeamId)?'selected':''}" data-team="${t.id}"><span class="team-card-badge">${teamInitial(t.nome)}</span><span><strong>${esc(t.nome)}</strong><small>${esc(t.categoria||'Sénior')} · ${n} jogador${n===1?'':'es'}</small><em>⌖ ${esc(m?.recinto||'Sem recinto')}</em></span></button>`}).join('')}</div></section>`;
 const roster=`<section class="squad-panel"><div class="squad-header"><div><span class="eyebrow">3 · PLANTEL</span><h2>${esc(team?.nome||'Equipa')}</h2><p>${esc(team?.clube||'')} · ${esc(team?.categoria||'')} · ⌖ ${esc(team?.recinto||'')}</p></div>${seasonWritable()?button('add-player','＋ Adicionar jogador',`data-team-id="${selectedTeamId}"`):''}</div><div class="squad-stats"><div><b>${current.filter(r=>r.funcao==='JOGADOR').length}</b><span>Jogadores ativos</span></div><div><b>${current.filter(r=>r.funcao!=='JOGADOR').length}</b><span>Staff / outras funções</span></div><div><b>${current.filter(r=>r.numero).length}</b><span>Com dorsal</span></div></div>${players.length?`<div class="squad-list">${players.map(r=>`<article class="person-row"><span class="shirt-number">${r.numero?esc(r.numero):'—'}</span><div class="person-main"><strong>${esc(r.nome)}</strong><small>${esc(r.funcao)} · ${r.inicio?esc(r.inicio.slice(0,10)):'—'} → ${r.fim?esc(r.fim.slice(0,10)):'Em aberto'}</small></div><div class="person-actions">${seasonWritable()?`${button('edit-person','Editar',`data-person="${r.pessoa_id}" data-name="${esc(r.nome)}"`)} ${r.funcao==='JOGADOR'?button('number','Dorsal',`data-vinculo="${r.vinculo_id}"`):''} ${button('end-link','Terminar vínculo',`data-vinculo="${r.vinculo_id}"`)}`:''}</div></article>`).join('')}</div>`:`<div class="empty-state"><b>Plantel vazio</b><p>${seasonClosed()?'Sem jogadores registados nesta época.':'Adiciona o primeiro jogador a esta equipa.'}</p></div>`}</section>`;
 const lock=seasonClosed()?`<div class="history-lock"><span>🔒</span><div><strong>Época finalizada — plantel histórico em modo de leitura</strong><small>Não é possível adicionar jogadores, alterar dados, dorsais ou vínculos nesta época.</small></div></div>`:'';
 return `<div class="management-flow">${lock}${clubStrip}${teamStrip}${roster}</div>`;
}
const reportDefs={
 resumo:{icon:'✦',group:'BÁSICOS',title:'Resumo da competição',desc:'Estado da época, jogos, homologação, líder e indicadores principais.'},
 classificacao:{icon:'🏆',group:'BÁSICOS',title:'Classificação',desc:'Posição, jogos, vitórias, empates, derrotas, golos e pontos.'},
 resultados:{icon:'▣',group:'BÁSICOS',title:'Jogos e resultados',desc:'Calendário, resultados, recinto e estado de cada encontro.'},
 jornadas:{icon:'◫',group:'BÁSICOS',title:'Resumo por jornadas',desc:'Leitura rápida da competição jornada a jornada.'},
 golos:{icon:'⚽',group:'DESPORTIVO',title:'Marcadores',desc:'Ranking de golos marcados na época.'},
 cartoes:{icon:'▰',group:'DESPORTIVO',title:'Disciplina',desc:'Amarelos, vermelhos e expulsões registadas.'},
 faltas:{icon:'⚑',group:'DESPORTIVO',title:'Faltas acumuladas',desc:'Faltas diretas e indiretas por jogo e período.'},
 arbitragem:{icon:'♜',group:'OPERAÇÃO',title:'Arbitragem',desc:'Nomeações e equipa de arbitragem por jogo.'},
 seguranca:{icon:'🛡',group:'OPERAÇÃO',title:'Segurança',desc:'Operações, responsáveis, efetivos, ocorrências e fecho.'},
 jogadores:{icon:'♙',group:'OPERAÇÃO',title:'Plantéis',desc:'Jogadores, dorsais, funções e vínculos por equipa.'},
 auditoria:{icon:'◎',group:'CONTROLO',title:'Integridade e auditoria',desc:'Cadeia forense e intervenções críticas sobre objetos fechados.',role:'SUPER_AUDITOR'}
};
function reportCenter(){
 const groups=['BÁSICOS','DESPORTIVO','OPERAÇÃO','CONTROLO'];
 const allowed=Object.entries(reportDefs).filter(([,d])=>!d.role||me?.roles?.includes(d.role));
 if(!allowed.some(([k])=>k===activeReport))activeReport='resumo';
 const list=groups.map(g=>{const items=allowed.filter(([,d])=>d.group===g);return items.length?`<div class="report-group"><div class="report-group-title">${g}</div>${items.map(([k,d])=>`<button class="report-list-item ${activeReport===k?'selected':''}" data-report="${k}"><span class="report-list-icon">${d.icon}</span><span class="report-list-copy"><strong>${d.title}</strong><small>${d.desc}</small></span><span class="report-list-arrow">→</span></button>`).join('')}</div>`:'';}).join('');
 return `<div class="report-layout"><aside class="report-catalog"><div class="report-catalog-head"><span class="eyebrow">CENTRO DE RELATÓRIOS</span><h2>Relatórios NEXUS</h2><p>Leitura funcional da competição, sem nomes técnicos da base de dados.</p></div>${list}</aside><section class="report-stage"><div class="report-stage-toolbar"><div><span class="eyebrow">RELATÓRIO ATIVO</span><strong>${reportDefs[activeReport]?.title||''}</strong></div><button data-action="print-report" class="secondary">Imprimir / PDF</button></div><section id="report" class="report-output"></section></section></div>`;
}
function reportEmpty(text='Sem dados para os filtros selecionados.'){return `<div class="empty-state"><b>Sem resultados</b><p>${esc(text)}</p></div>`;}

function seasonPanel(d,allowClose=false){
 const e=d.epoca;if(!e)return '';
 const total=Object.entries(d.estados||{}).filter(([s])=>s!=='CANCELADO').reduce((n,[,v])=>n+v,0),hom=d.estados?.HOMOLOGADO||0;
 const pct=total?Math.round(hom*100/total):0;
 const champion=e.estado==='FINALIZADA'&&e.classificacao_final?.length?`<div class="season-champion"><span>🏆</span><div><small>CAMPEÃO</small><strong>${esc(e.classificacao_final[0].nome)}</strong><p>Classificação final preservada · ${esc(new Date(e.finalizada_em).toLocaleString('pt-PT'))}</p></div></div>`:'';
 return `<section class="season-card"><div class="season-head"><div><span class="eyebrow">COMPETIÇÃO</span><h2>${esc(e.nome)}</h2></div>${statePill(e.estado)}</div><p class="season-progress">${hom}/${total} jogos homologados · ${pct}% concluído</p>${champion}${allowClose&&e.estado!=='FINALIZADA'&&admin()?`<div class="actions">${button('close-season','Finalizar Liga',total&&hom===total&&!d.seguranca_aberta?'':'disabled')}</div>`:''}${e.classificacao_final?`<h3>Classificação final</h3>${table(e.classificacao_final,[['Equipa','nome'],['Jogos','jogos'],['Pontos','pontos'],['GM','golos_favor'],['GS','golos_contra']])}`:''}</section>`;
}
function gameSignals(){
 const j=game.jogo;
 const teamReady=id=>{
  const rows=game.convocados.filter(x=>x.equipa_id===id);
  const starters=rows.filter(x=>x.estado==='EM_CAMPO');
  return starters.length>=3&&starters.length<=5&&starters.filter(x=>x.goleiro).length===1;
 };
 const rosterReady=teamReady(j.casa_id)&&teamReady(j.fora_id);
 const rosterAny=game.convocados.length>0;
 const refereeReady=game.arbitragem.some(x=>x.funcao==='ARBITRO');
 const refereeAny=game.arbitragem.length>0;
 const sec=game.seguranca?.estado||'PLANEADA';
 const closed=game.epoca?.estado==='FINALIZADA';
 let matchClass='yellow',matchText=esc(j.estado.replaceAll('_',' '));
 if(j.estado==='HOMOLOGADO'){matchClass='green';matchText='Homologado';}
 else if(closed&&j.estado!=='HOMOLOGADO'){matchClass='red';matchText='Fechado / rever';}
 else if(['NAO_AGENDADO','ADIADO','CANCELADO'].includes(j.estado)){matchClass='orange';}
 const items=[
  [rosterReady?'green':rosterAny?'yellow':'orange','Plantéis',rosterReady?'Prontos':rosterAny?'A completar':'Pendentes'],
  [refereeReady?'green':refereeAny?'yellow':'orange','Arbitragem',refereeReady?'Árbitro nomeado':refereeAny?'A completar':'Pendente'],
  [sec==='FINALIZADA'&&!['FINALIZADO','HOMOLOGADO'].includes(game.jogo.estado)?'red':sec==='FINALIZADA'?'green':sec==='EM_CURSO'?'yellow':'orange','Segurança',sec==='FINALIZADA'&&!['FINALIZADO','HOMOLOGADO'].includes(game.jogo.estado)?'Fecho antecipado inválido':sec==='FINALIZADA'?'Finalizada':sec==='EM_CURSO'?'Em curso':'Por iniciar'],
  [matchClass,'Jogo',matchText]
 ];
 const targets=['PLANTEIS','ARBITRAGEM','SEGURANCA','JOGO'];
 return `<div class="signals">${items.map(([cls,label,state],i)=>`<button type="button" class="signal signal-${cls}" data-tab="${targets[i]}" title="Abrir ${esc(label)}"><span class="signal-dot"></span><div><b>${esc(label)}</b><small>${esc(state)}</small></div><span class="signal-arrow">→</span></button>`).join('')}</div>`;
}
function rosterTeam(teamId,label){
 const name=cat.equipas.find(x=>x.id===teamId)?.nome||'Equipa';
 const rows=game.convocados.filter(x=>x.equipa_id===teamId);
 return `<section class="roster-team"><h3>${esc(label)} · ${esc(name)}</h3>${table(rows,[['#','numero'],['Jogador','nome'],['Papel',r=>`${r.estado==='EM_CAMPO'?'Titular':'Banco'}${r.goleiro?' · GR':''}`],['Ação',r=>writable()&&game.jogo.estado==='AGENDADO'&&game.epoca?.estado!=='FINALIZADA'?button('remove-player','Remover',`data-id="${r.id}"`):'']])}</section>`;
}
function callupTeam(teamId,label){
 const name=cat.equipas.find(x=>x.id===teamId)?.nome||'Equipa';
 const rows=game.elegiveis.filter(x=>x.equipa_id===teamId).sort((a,b)=>a.numero-b.numero);
 const current=game.convocados.filter(x=>x.equipa_id===teamId);
 const currentStarters=current.filter(x=>x.estado==='EM_CAMPO').length;
 const keeper=current.find(x=>x.goleiro&&x.estado==='EM_CAMPO');
 const starterSlots=Math.max(0,5-currentStarters);
 const preferredKeeper=rows.find(x=>Number(x.numero)===1)||rows[0]||null;
 const keeperControl=keeper
  ? `<div class="keeper-choice locked"><span>Guarda-redes titular</span><strong>#${esc(keeper.numero)} ${esc(keeper.nome)}</strong><small>Já definido nesta convocatória</small></div>`
  : rows.length?`<label class="keeper-choice"><span>Guarda-redes titular</span><select name="keeper_${teamId}" required>${rows.map(x=>`<option value="${x.camisola_id}" ${preferredKeeper?.camisola_id===x.camisola_id?'selected':''}>#${esc(x.numero)} ${esc(x.nome)}</option>`).join('')}</select><small>É escolhido um único GR para a equipa. Os restantes jogadores deixam de aparecer como “GR”.</small></label>`:'';
 return `<section class="callup-team"><div class="callup-head"><span>${esc(label)}</span><strong>${esc(name)}</strong><small>${current.length} já convocados · ${rows.length} elegíveis</small></div>${keeperControl}${rows.length?`<div class="callup-list">${rows.map((x,i)=>`<div class="callup-row"><label class="call-main"><input type="checkbox" name="call_${x.camisola_id}" checked><span><b>#${esc(x.numero)} ${esc(x.nome)}</b><small>Convocar</small></span></label><label class="call-role"><input type="checkbox" name="starter_${x.camisola_id}" ${i<starterSlots?'checked':''}>Titular</label></div>`).join('')}</div>`:'<div class="muted">Convocatória desta equipa já preparada.</div>'}</section>`;
}

function form(title,fields,submit){$('#modalBody').innerHTML=`<h2>${esc(title)}</h2><form id="dialogForm" autocomplete="off">${fields}<div class="actions"><button>Guardar</button><button type="button" data-action="close" class="secondary">Cancelar</button></div></form>`;$('#modal').showModal();$('#dialogForm').onsubmit=async e=>{e.preventDefault();const data=Object.fromEntries(new FormData(e.target));try{await submit(data);$('#modal').close();notice('Operação guardada');await refresh();}catch(err){notice(err.message);}};}
async function boot(){me=await api('me');if(me.mudar_password){$('#gate').hidden=false;$('#shell').hidden=true;$('#gate').innerHTML=`<form id="password" class="panel"><h1>Alterar password</h1><p>Primeiro acesso. Escolha uma password com 12 a 64 caracteres, maiúscula, minúscula, número e símbolo.</p>${input('nova','Nova password','password','','required minlength="12" maxlength="64" autocomplete="new-password"')}${input('confirmacao','Repetir password','password','','required')}<button>Guardar e entrar</button></form>`;$('#password').onsubmit=async e=>{e.preventDefault();const d=Object.fromEntries(new FormData(e.target));if(d.nova!==d.confirmacao)return notice('As passwords não coincidem');try{await command('PASSWORD',{nova:d.nova});await boot();}catch(err){notice(err.message);}};return;}
 cat=await api('catalogo');$('#gate').hidden=true;$('#shell').hidden=false;$('#identity').textContent=me.nome;$('#season').innerHTML=opt(cat.epocas,'id','nome');
 const menu=[['dashboard','⌂','Dashboard'],['jogos','▣','Jogos'],['planteis','♙','Clubes e plantéis'],['seguranca','🛡','Segurança'],['relatorios','▤','Centro de relatórios']];if(admin())menu.push(['utilizadores','♙','Utilizadores']);if(me.roles.includes('SUPER_AUDITOR'))menu.push(['super','◉','Super Auditoria']);
 $('#nav').innerHTML=menu.map(([v,i,n])=>`<button data-view="${v}"><span class="nav-icon">${i}</span><span>${n}</span></button>`).join('');$('#identityRole').textContent=me.roles.join(' · ');updateRounds();updateContextHint();await refresh();}
function updateRounds(){const prev=$('#round').value;$('#round').innerHTML='<option value="">Todas as jornadas</option>'+opt(cat.jornadas.filter(x=>Number(x.epoca_id)===season()),'numero','numero');if([...$('#round').options].some(o=>o.value===prev))$('#round').value=prev;updateContextHint();}
async function refresh(){
 for(const b of document.querySelectorAll('[data-view]'))b.classList.toggle('active',b.dataset.view===view);
 const names={dashboard:'Dashboard operacional',jogos:'Jornadas e jogos',planteis:'Clubes e plantéis',seguranca:'Segurança da competição',relatorios:'Centro de relatórios',utilizadores:'Utilizadores',super:'Super Auditoria',jogo:'Cockpit do jogo'};
 $('#title').textContent=names[view];$('#contextTitle').textContent=names[view];
 if(view==='jogo')return loadGame(game.jogo.id);
 if(view==='dashboard'){
  const [d,allGames,securityOps]=await Promise.all([api(`dashboard?epoca_id=${season()}`),api(`jogos?epoca_id=${season()}`),api(`relatorio?epoca_id=${season()}&tipo=seguranca`)]),states=['NAO_AGENDADO','AGENDADO','ADIADO','EM_CURSO','INTERROMPIDO','FINALIZADO','HOMOLOGADO'];
  const labels={NAO_AGENDADO:'Por agendar',AGENDADO:'Agendados',ADIADO:'Adiados',EM_CURSO:'Em curso',INTERROMPIDO:'Interrompidos',FINALIZADO:'Por homologar',HOMOLOGADO:'Homologados'};
  const scoped=round()?allGames.filter(x=>Number(x.jornada)===round()):allGames;
  const counts=round()?Object.fromEntries(states.map(st=>[st,scoped.filter(x=>x.estado===st).length])):(d.estados||{});
  const securityOpen=round()?securityOps.filter(x=>Number(x.jornada)===round()&&x.estado!=='FINALIZADA').length:d.seguranca_aberta;
  $('#content').innerHTML=seasonPanel(d,true)+roundFocus(scoped)+`<div class="cards">${states.map(st=>`<button class="card" data-filter="${st}"><span>${labels[st]}</span><b>${counts?.[st]||0}</b></button>`).join('')}<button class="card" data-filter="SEGURANCA"><span>Segurança aberta</span><b>${securityOpen}</b></button></div><section class="panel"><h2>Fluxo operacional</h2><p>Jornada → agendamento → recinto → plantéis → arbitragem → segurança → jogo → homologação. As alterações críticas ficam auditadas e a Liga fechada bloqueia operação normal.</p></section>`;
 }
 if(view==='jogos'){
  let rows=await api(`jogos?epoca_id=${season()}`);if(round())rows=rows.filter(x=>x.jornada===round());
  if(filter==='SEGURANCA'){const states=await Promise.all(rows.map(x=>api('jogo?jogo_id='+x.id)));rows=rows.filter((x,i)=>states[i].seguranca.estado!=='FINALIZADA');}
  else if(filter)rows=rows.filter(x=>x.estado===filter);
  const groups=[...new Set(rows.map(r=>r.jornada))].sort((a,b)=>Number(a)-Number(b));
  const board=groups.map(n=>{const games=rows.filter(r=>r.jornada===n);return `<section class="round-block"><div class="round-head"><div><span class="eyebrow">JORNADA ${esc(n)}</span><h2>Jogos da jornada</h2></div><span class="round-count">${games.length} jogo${games.length===1?'':'s'}</span></div><div class="match-grid">${games.map(r=>{const scheduled=!!r.inicio;const result=['FINALIZADO','HOMOLOGADO'].includes(r.estado)?`${r.golos_casa} – ${r.golos_fora}`:'VS';const dt=scheduled?new Date(r.inicio).toLocaleString('pt-PT',{dateStyle:'short',timeStyle:'short'}):'Por agendar';return `<button class="match-card" data-game="${r.id}"><div class="match-card-top">${statePill(r.estado)}<span class="match-date">${esc(dt)}</span></div><div class="match-teams"><div class="match-team home"><span class="mini-badge">${teamInitial(r.casa)}</span><strong>${esc(r.casa)}</strong><small>Casa</small></div><div class="match-score">${esc(result)}</div><div class="match-team away"><strong>${esc(r.fora)}</strong><small>Visitante</small><span class="mini-badge">${teamInitial(r.fora)}</span></div></div><div class="match-card-bottom"><span>⌖ ${esc(r.recinto||'Recinto por definir')}</span><strong>Abrir jogo →</strong></div></button>`}).join('')}</div></section>`}).join('');
  $('#content').innerHTML=(filter?`<div class="actions"><span class="pill">${esc(filter.replaceAll('_',' '))}</span>${button('clear-filter','Mostrar todos','class="secondary"')}</div>`:'')+(board||'<section class="panel"><p class="muted">Não existem jogos para este filtro.</p></section>');
 }
 if(view==='planteis'){
  const rows=await api(`planteis?epoca_id=${season()}`);
  $('#content').innerHTML=rosterManager(rows);
 }
 if(view==='seguranca'){
  let rows=await api(`relatorio?epoca_id=${season()}&tipo=seguranca`);if(round())rows=rows.filter(r=>Number(r.jornada)===round());const open=rows.filter(r=>r.estado!=='FINALIZADA').length,final=rows.length-open;
  $('#content').innerHTML=`<section class="security-hub-hero"><div><span class="eyebrow">CENTRO OPERACIONAL</span><h2>Segurança da competição</h2><p>Atalho direto para cada operação. Abre o jogo já no separador Segurança.</p></div><div class="security-hub-kpis"><span><b>${open}</b> abertas</span><span><b>${final}</b> finalizadas</span></div></section><div class="security-hub-grid">${rows.map(r=>`<article class="security-hub-card ${r.estado==='FINALIZADA'?'done':'active'}"><header><div><span class="eyebrow">JORNADA ${esc(r.jornada)} · JOGO #${esc(r.jogo_id)}</span><strong>${esc(r.casa)} × ${esc(r.fora)}</strong></div>${statePill(r.estado==='FINALIZADA'?'HOMOLOGADO':r.estado==='EM_CURSO'?'EM_CURSO':'NAO_AGENDADO')}</header><div class="security-hub-metrics"><span><b>${esc(r.efetivos||0)}</b> efetivos</span><span><b>${esc(r.ocorrencias||0)}</b> ocorrências</span><span><b>${esc(r.feridos||0)}</b> feridos</span></div><p><b>Responsável:</b> ${esc(r.responsavel||'Por definir')}</p><button data-security-game="${r.jogo_id}">Abrir Segurança →</button></article>`).join('')||reportEmpty('Não existem operações nesta época.')}</div>`;
 }
 if(view==='relatorios'){$('#content').innerHTML=reportCenter();await renderReport();}
 if(view==='utilizadores'){$('#content').innerHTML=`<div class="actions">${button('new-user','Criar utilizador')}</div>`+table(await command('UTILIZADORES'),[['Nome','nome'],['Email','email'],['Roles',r=>esc(r.roles.join(', '))],['Primeiro acesso',r=>r.mudar_password?'<span class="pill orange-pill">Alteração obrigatória</span>':'<span class="pill green-pill">Concluído</span>']]);}
 if(view==='super'){
  const d=await api('super'),summary=await api(`dashboard?epoca_id=${season()}`),flags=d.red_flags||[],access=d.acessos||[];
  const blocked=flags.filter(x=>x.resultado==='REJEITADA').length,executed=flags.filter(x=>x.resultado==='EXECUTADA').length,denied=access.filter(x=>!x.permitido).length;
  const actionLabel=a=>({SUPER:'Acesso à Super Auditoria',SUPER_DETALHE:'Consulta de evidência',INTEGRIDADE:'Verificação da cadeia forense'}[a]||String(a||'Ação de auditoria').replaceAll('_',' '));
  const outcome=r=>r.detalhe?.pedido?.tipo==='CARTAO_VERMELHO'&&r.resultado==='EXECUTADA'?['VERMELHO DETETADO','orange']:r.detalhe?.pedido?.tipo==='GOLO'&&r.resultado==='REJEITADA'?['RESULTADO BLOQUEADO','red']:r.resultado==='REJEITADA'?['BLOQUEADA','red']:r.resultado==='EXECUTADA'?['REGISTADA','green']:r.resultado==='CANCELADA'?['CANCELADA','gray']:['EM ANÁLISE','orange'];
  $('#content').innerHTML=`<section class="super-hero"><div class="super-mark">◎</div><div><span class="eyebrow">CONTROLO DE INTEGRIDADE</span><h2>Super Auditoria</h2><p>${esc(summary.epoca?.nome||'Competição')} · visão simples das intervenções críticas e do rasto forense.</p></div><span class="integrity-badge ${d.integridade.integra?'ok':'bad'}">${d.integridade.integra?'✓ Cadeia íntegra':'! Divergência detetada'}</span></section><div class="super-kpis"><article><small>Registos forenses</small><b>${d.integridade.registos||0}</b><span>cadeia verificada</span></article><article><small>Intervenções críticas</small><b>${flags.length}</b><span>${executed} registadas</span></article><article><small>Alterações bloqueadas</small><b>${blocked}</b><span>não chegaram ao objeto protegido</span></article><article><small>Acessos negados</small><b>${denied}</b><span>tentativas sem autorização</span></article></div><section class="panel"><div class="section-title"><div><span class="eyebrow">INCIDENTES CRÍTICOS</span><h2>Intervenções sobre objetos fechados</h2><p>Cada cartão explica o que foi tentado, por quem e qual foi o resultado.</p></div></div><div class="audit-case-grid">${flags.map(r=>{const [label,tone]=outcome(r);return `<article class="audit-case audit-${tone}"><header><span class="audit-object">${esc(r.objeto)} #${esc(r.objeto_id)}</span><span class="pill ${tone}-pill">${esc(label)}</span></header><h3>${esc(r.motivo)}</h3><div class="audit-meta"><span><b>Utilizador</b>${esc(r.utilizador||'—')}</span><span><b>Data</b>${fmtDate(r.criado_em)}</span></div><p>${r.resultado==='REJEITADA'?'A alteração foi bloqueada e o objeto oficial permaneceu intacto.':r.resultado==='EXECUTADA'?'A intervenção foi registada com evidência e preservação do histórico.':'A intervenção não produziu alteração definitiva.'}</p><button data-action="drill" data-id="${r.id}">Ver evidência →</button></article>`}).join('')||reportEmpty('Sem intervenções críticas nesta instalação.')}</div></section><section class="panel"><div class="section-title"><div><span class="eyebrow">META-AUDITORIA</span><h2>Atividade recente</h2><p>Quem acedeu à auditoria e se o acesso foi permitido.</p></div></div><div class="audit-access-list">${access.slice(0,20).map(r=>`<article><span class="audit-access-icon ${r.permitido?'ok':'bad'}">${r.permitido?'✓':'!'}</span><div><strong>${esc(actionLabel(r.acao))}</strong><small>${esc(r.utilizador||'Sem sessão')} · ${fmtDate(r.criado_em)}</small></div><span class="pill ${r.permitido?'green-pill':'red-pill'}">${r.permitido?'Permitido':'Negado'}</span></article>`).join('')||reportEmpty('Sem atividade de auditoria.')}</div></section>`;
 }
}
async function renderReport(){
 const tipo=activeReport,def=reportDefs[tipo];
 let d=null,body='';
 const head=(right='')=>`<div class="report-head"><div><span class="report-icon">${def.icon}</span><div><h2>${def.title}</h2><p>${def.desc}</p></div></div>${right}</div>`;

 if(tipo==='resumo'){
  const [dash,allGames,stand,securityOps]=await Promise.all([
   api(`dashboard?epoca_id=${season()}`),
   api(`jogos?epoca_id=${season()}`),
   api(`relatorio?epoca_id=${season()}&tipo=classificacao`),
   api(`relatorio?epoca_id=${season()}&tipo=seguranca`)
  ]);
  const games=round()?allGames.filter(x=>Number(x.jornada)===round()):allGames;
  const total=games.length;
  const hom=games.filter(x=>x.estado==='HOMOLOGADO').length;
  const played=games.filter(x=>['FINALIZADO','HOMOLOGADO'].includes(x.estado)).length;
  const goals=games.reduce((n,x)=>n+Number(x.golos_casa||0)+Number(x.golos_fora||0),0);
  const leader=stand?.[0]?.nome||'—';
  const leaderPoints=stand?.[0]?.pontos??0;
  const securityOpen=round()
   ?securityOps.filter(x=>Number(x.jornada)===round()&&x.estado!=='FINALIZADA').length
   :dash.seguranca_aberta;

  const rows=[
   {indicador:'Competição',valor:dash.epoca?.nome||'Época',leitura:dash.epoca?.estado||'ABERTA'},
   {indicador:round()?`Jogos da Jornada ${round()}`:'Jogos da época',valor:total,leitura:`${played} disputados`},
   {indicador:'Homologados',valor:hom,leitura:`${total?Math.round(hom*100/total):0}% do contexto atual`},
   {indicador:'Golos registados',valor:goals,leitura:'Total no contexto selecionado'},
   {indicador:'Segurança por fechar',valor:securityOpen,leitura:securityOpen?'Existem operações pendentes':'Sem operações abertas'},
   {indicador:'Líder da época',valor:leader,leitura:`${leaderPoints} pontos`}
  ];
  body=head(statePill(dash.epoca?.estado||'ABERTA'))+
   (round()?`<div class="info">Resumo limitado à Jornada ${round()}. A classificação continua a representar a época completa.</div>`:'')+
   table(rows,[
    ['Indicador','indicador'],
    ['Valor',r=>`<strong>${esc(r.valor)}</strong>`],
    ['Leitura','leitura']
   ]);
  $('#report').innerHTML=body;return;
 }

 if(tipo==='jornadas'){
  d=await api(`jogos?epoca_id=${season()}`);
  if(round())d=d.filter(x=>Number(x.jornada)===round());
  if(!d?.length){$('#report').innerHTML=reportEmpty();return;}
  body=head(`<span>${d.length} jogos</span>`)+table(d,[
   ['Jornada',r=>`J${esc(r.jornada)}`],
   ['Jogo',r=>`#${esc(r.id)}`],
   ['Casa','casa'],
   ['Resultado',r=>['FINALIZADO','HOMOLOGADO','EM_CURSO','INTERROMPIDO'].includes(r.estado)?`<strong>${esc(r.golos_casa)} – ${esc(r.golos_fora)}</strong>`:'VS'],
   ['Visitante','fora'],
   ['Data / hora',r=>fmtDate(r.inicio)],
   ['Recinto',r=>esc(r.recinto||'Por definir')],
   ['Estado',r=>statePill(r.estado)]
  ]);
  $('#report').innerHTML=body;return;
 }

 if(tipo==='jogadores'){
  d=await api(`planteis?epoca_id=${season()}`);
  if(!d?.length){$('#report').innerHTML=reportEmpty('Não existem vínculos de plantel nesta época.');return;}
  d=[...d].sort((a,b)=>
   String(a.clube||'').localeCompare(String(b.clube||''),'pt')||
   String(a.equipa||'').localeCompare(String(b.equipa||''),'pt')||
   Number(a.numero||999)-Number(b.numero||999)||
   String(a.nome||'').localeCompare(String(b.nome||''),'pt')
  );
  body=head(`<span>${d.length} vínculos</span>`)+
   (round()?`<div class="info">Plantéis pertencem à época completa; o filtro Jornada ${round()} não altera este relatório.</div>`:'')+
   table(d,[
    ['Clube','clube'],
    ['Equipa','equipa'],
    ['N.º',r=>r.numero?esc(r.numero):'—'],
    ['Nome','nome'],
    ['Função',r=>esc(String(r.funcao||'').replaceAll('_',' '))],
    ['Início',r=>r.inicio?esc(String(r.inicio).slice(0,10)):'—'],
    ['Fim',r=>r.fim?esc(String(r.fim).slice(0,10)):'Em aberto']
   ]);
  $('#report').innerHTML=body;return;
 }

 d=await api(`relatorio?epoca_id=${season()}&tipo=${tipo}`+(round()?'&jornada='+round():''));

 if(round()&&['seguranca','arbitragem'].includes(tipo))
  d=d.filter(r=>Number(r.jornada)===round());

 if(round()&&['cartoes','faltas'].includes(tipo)){
  const ids=new Set(
   (await api(`jogos?epoca_id=${season()}`))
    .filter(x=>Number(x.jornada)===round())
    .map(x=>Number(x.id))
  );
  d=d.filter(r=>ids.has(Number(r.jogo_id)));
 }

 if(tipo==='auditoria'){
  const integ=d.integridade||{},rows=d.intervencoes||[];
  const summaryRows=[
   {indicador:'Estado da cadeia',valor:integ.integra?'ÍNTEGRA':'DIVERGENTE'},
   {indicador:'Registos forenses',valor:integ.registos||0},
   {indicador:'Intervenções registadas',valor:rows.length}
  ];
  body=head(`<span class="pill ${integ.integra?'green-pill':'red-pill'}">${integ.integra?'CADEIA ÍNTEGRA':'DIVERGENTE'}</span>`);
  body+=table(summaryRows,[['Indicador','indicador'],['Valor',r=>`<strong>${esc(r.valor)}</strong>`]]);
  if(rows.length){
   body+=`<h3 class="report-subtitle">Intervenções críticas</h3>`+table(rows,[
    ['Objeto',r=>`${esc(r.objeto)} #${esc(r.objeto_id)}`],
    ['Motivo','motivo'],
    ['Utilizador',r=>esc(r.utilizador||'—')],
    ['Resultado',r=>`<span class="pill ${r.resultado==='REJEITADA'?'red-pill':r.resultado==='EXECUTADA'?'green-pill':'orange-pill'}">${esc(r.resultado||'ABERTA')}</span>`],
    ['Data',r=>fmtDate(r.criado_em)]
   ]);
  } else body+=reportEmpty('Sem intervenções extraordinárias registadas.');
  $('#report').innerHTML=body;return;
 }

 if(!d?.length){ $('#report').innerHTML=head()+reportEmpty(); return; }

 if(tipo==='classificacao'){
  const rows=d.map((r,i)=>({...r,pos:i+1,dg:Number(r.golos_favor||0)-Number(r.golos_contra||0)}));
  body=head(`<span>${d.length} equipas</span>`)+
   (d.some(x=>x.provisoria)?'<div class="orange">Classificação provisória — existem resultados ainda não homologados.</div>':'')+
   table(rows,[
    ['Pos.','pos'],
    ['Equipa','nome'],
    ['J','jogos'],
    ['V','vitorias'],
    ['E','empates'],
    ['D','derrotas'],
    ['GM','golos_favor'],
    ['GS','golos_contra'],
    ['DG','dg'],
    ['Pontos',r=>`<strong>${esc(r.pontos)}</strong>`]
   ]);
 }
 else if(tipo==='resultados'){
  body=head(`<span>${d.length} jogos</span>`)+table(d,[
   ['Jornada',r=>`J${esc(r.jornada)}`],
   ['Data / hora',r=>fmtDate(r.inicio)],
   ['Casa','casa'],
   ['Resultado',r=>{const show=['EM_CURSO','INTERROMPIDO','FINALIZADO','HOMOLOGADO'].includes(r.estado);return show?`<strong>${esc(r.golos_casa)} – ${esc(r.golos_fora)}</strong>`:'VS';}],
   ['Visitante','fora'],
   ['Recinto',r=>esc(r.recinto||'Por definir')],
   ['Estado',r=>statePill(r.estado)]
  ]);
 }
 else if(tipo==='golos'){
  const rows=d.map((r,i)=>({...r,pos:i+1}));
  body=head(`<span>${d.length} jogadores</span>`)+table(rows,[
   ['Pos.','pos'],
   ['Jogador','jogador'],
   ['Golos',r=>`<strong>${esc(r.golos)}</strong>`]
  ]);
 }
 else if(tipo==='cartoes'){
  body=head(`<span>${d.length} registos</span>`)+table(d,[
   ['Jogo',r=>'#'+esc(r.jogo_id)],
   ['Tempo','tempo'],
   ['Jogador','jogador'],
   ['Disciplina',r=>`<span class="pill ${String(r.tipo).includes('VERMELHO')||String(r.tipo).includes('EXPULSAO')?'red-pill':'orange-pill'}">${esc(String(r.tipo).replaceAll('_',' '))}</span>`]
  ]);
 }
 else if(tipo==='faltas'){
  body=head(`<span>${d.length} registos</span>`)+table(d,[
   ['Jogo',r=>'#'+esc(r.jogo_id)],
   ['Período',r=>`${esc(r.periodo)}.º`],
   ['Equipa','equipa'],
   ['Diretas','acumuladas'],
   ['Indiretas','indiretas']
  ]);
 }
 else if(tipo==='arbitragem'){
  const rows=[];
  for(const r of d){
   if((r.oficiais||[]).length){
    for(const o of r.oficiais)rows.push({
     jornada:r.jornada,jogo_id:r.jogo_id,casa:r.casa,fora:r.fora,inicio:r.inicio,
     funcao:String(o.funcao||'').replaceAll('_',' '),nome:o.nome
    });
   }else rows.push({
    jornada:r.jornada,jogo_id:r.jogo_id,casa:r.casa,fora:r.fora,inicio:r.inicio,
    funcao:'—',nome:'Por nomear'
   });
  }
  body=head(`<span>${d.length} jogos</span>`)+table(rows,[
   ['Jornada',r=>`J${esc(r.jornada)}`],
   ['Jogo',r=>'#'+esc(r.jogo_id)],
   ['Encontro',r=>`${esc(r.casa)} × ${esc(r.fora)}`],
   ['Data / hora',r=>fmtDate(r.inicio)],
   ['Função','funcao'],
   ['Oficial','nome']
  ]);
 }
 else if(tipo==='seguranca'){
  body=head(`<span>${d.length} operações</span>`)+table(d,[
   ['Jornada',r=>`J${esc(r.jornada)}`],
   ['Jogo',r=>'#'+esc(r.jogo_id)],
   ['Encontro',r=>`${esc(r.casa)} × ${esc(r.fora)}`],
   ['Estado',r=>statePill(r.estado)],
   ['Responsável',r=>esc(r.responsavel||'Por definir')],
   ['Efetivos',r=>esc(r.efetivos||0)],
   ['Ocorrências',r=>esc(r.ocorrencias||0)],
   ['Feridos',r=>esc(r.feridos||0)],
   ['Uso força',r=>esc(r.uso_forca||0)],
   ['Avaliação',r=>esc(r.avaliacao||'Pendente')]
  ]);
 }

 $('#report').innerHTML=body;
}

async function loadGame(id){
 game=await api('jogo?jogo_id='+id);const j=game.jogo;
 const venueChanged=j.recinto_id&&j.recinto_id!==j.recinto_esperado;
 const dt=j.inicio?new Date(j.inicio).toLocaleString('pt-PT'):'Por agendar';
 $('#contextTitle').textContent=`Jogo #${j.id}`;
 $('#content').innerHTML=`<div class="game-shell">
  <section class="game-hero">
   <div class="game-hero-main">
    <div class="team-block"><div class="team-badge">${teamInitial(j.casa)}</div><div><div class="team-name">${esc(j.casa)}</div><div class="team-side">Equipa da casa</div></div></div>
    <div class="score-center">${statePill(j.estado)}<div class="score-number">${j.golos_casa} – ${j.golos_fora}</div><div class="score-meta">Jornada ${j.jornada} · ${esc(dt)}</div><div class="venue-line ${venueChanged?'warning':''}">⌖ ${esc(j.recinto||'Recinto por definir')}${venueChanged?' · recinto alterado':''}</div></div>
    <div class="team-block away"><div><div class="team-name">${esc(j.fora)}</div><div class="team-side">Equipa visitante</div></div><div class="team-badge">${teamInitial(j.fora)}</div></div>
   </div>
  </section>
  <div class="game-tabs">${['JOGO','PLANTEIS','ARBITRAGEM','SEGURANCA','TIMELINE'].map(t=>`<button data-tab="${t}" class="${tab===t?'active':''}">${t==='PLANTEIS'?'⚽ PLANTÉIS':t==='SEGURANCA'?'🛡 SEGURANÇA':t==='ARBITRAGEM'?'♙ ARBITRAGEM':t==='TIMELINE'?'◷ TIMELINE':'◉ JOGO'}</button>`).join('')}</div>
  ${gameSignals()}
  <section id="cockpit"></section>
 </div>`;
 renderTab();
}
function renderTab(){
 const j=game.jogo;let html='';const open=writable()&&j.estado!=='HOMOLOGADO'&&game.epoca?.estado!=='FINALIZADA';
 if(tab==='JOGO'){
  const readiness=game.readiness.pronto||j.estado==='HOMOLOGADO',venueExpected=cat.recintos.find(x=>x.id===j.recinto_esperado)?.nome||'—';
  let actions='';
  if(open){
   if(['NAO_AGENDADO','ADIADO'].includes(j.estado))actions+=button('schedule','Agendar jogo');
   if(j.estado==='AGENDADO')actions+=button('start','Iniciar jogo')+button('simulate','Simular jogo completo')+button('simulate-round','Simular jornada')+button('postpone','Adiar','class="secondary"');
   if(['AGENDADO','ADIADO','EM_CURSO'].includes(j.estado))actions+=button('venue','Alterar recinto','class="secondary"');
   if(j.estado==='EM_CURSO'){if(j.intervalo)actions+=button('second','Iniciar 2.ª parte');else{actions+=button('event','Registar evento')+button('interrupt','Interromper','class="secondary"');actions+=j.periodo===1?button('half','Intervalo aos 20:00','class="secondary"'):button('finish','Finalizar aos 40:00');}}
   if(j.estado==='INTERROMPIDO')actions+=button('resume','Retomar em '+time(j));
   if(j.estado==='FINALIZADO')actions+=button('homologate','Homologar jogo');
  }
  if(j.estado==='HOMOLOGADO'&&admin())actions+=button('rectify-game','Entrar em retificação','class="secondary"');
  html=`<div class="cockpit-grid">
   <section class="cockpit-card"><h3>Dados do jogo</h3><div class="data-list">
    <div class="data-row"><span>Jornada</span><strong>${esc(j.jornada)}</strong></div>
    <div class="data-row"><span>Data / hora</span><strong>${j.inicio?esc(new Date(j.inicio).toLocaleString('pt-PT')):'Por agendar'}</strong></div>
    <div class="data-row"><span>Estado</span><strong>${statePill(j.estado)}</strong></div>
    <div class="data-row"><span>Relógio</span><strong>${time(j)} · ${j.periodo}.º período${j.intervalo?' · Intervalo':''}</strong></div>
    <div class="data-row"><span>Recinto previsto</span><strong>${esc(venueExpected)}</strong></div>
    <div class="data-row"><span>Recinto utilizado</span><strong>${esc(j.recinto||'Por definir')}</strong></div>
    ${j.recinto_id&&j.recinto_id!==j.recinto_esperado?`<div class="orange">Recinto diferente do previsto. Alteração registada e auditável.</div>`:''}
   </div></section>
   <section class="cockpit-card"><h3>Resumo</h3><div class="summary-stats">
    <div class="stat-mini"><b>${j.golos_casa}</b><span>Golos · Casa</span></div><div class="stat-mini"><b>${j.golos_fora}</b><span>Golos · Visitante</span></div>
    <div class="stat-mini"><b>${game.eventos.filter(e=>e.tipo==='AMARELO'&&e.valido).length}</b><span>Cartões amarelos</span></div><div class="stat-mini"><b>${game.eventos.filter(e=>['VERMELHO_DIRETO','EXPULSAO_SEGUNDO_AMARELO'].includes(e.tipo)&&e.valido).length}</b><span>Expulsões</span></div>
   </div><h3>Estado da segurança</h3><div class="data-list"><button type="button" class="data-row security-jump" data-tab="SEGURANCA"><span>Operação</span><strong>${esc(game.seguranca?.estado||'PLANEADA')} →</strong></button><div class="data-row"><span>Ocorrências</span><strong>${game.ocorrencias.length}</strong></div><div class="data-row"><span>Efetivos</span><strong>${game.efetivos.length}</strong></div></div></section>
   <section class="cockpit-card readiness-card ${readiness?'':'not-ready'}"><div class="ready-head"><span class="ready-icon">${readiness?'✓':'!'}</span><span>${readiness?'Pronto para Homologação':'Pendências operacionais'}</span></div><p>${j.estado==='HOMOLOGADO'?'Jogo homologado.':game.readiness.pronto?'Todas as condições estão cumpridas.':esc(game.readiness.motivos.join(' · ')||'Preparação em curso.')}</p><div class="action-stack">${actions||'<span class="muted">Sem ações disponíveis neste estado.</span>'}</div></section>
  </div>`;
  if(game.resultados.length)html+=`<section class="panel"><h3>Versões oficiais</h3>${table(game.resultados,[['Versão','versao'],['Casa','casa'],['Fora','fora'],['Motivo','motivo']])}</section>`;
  if(game.reducoes.length)html+=`<section class="panel"><h3>Inferioridade numérica</h3>${table(game.reducoes,[['Equipa',r=>esc(cat.equipas.find(x=>x.id===r.equipa_id)?.nome)],['Início (segundos)','inicio'],['Libertação (segundos)','libertada_em'],['Causa','causa'],['Reposição',r=>r.entrada_evento?'Substituto entrou':r.libertada_em!==null?'Entrada autorizável':'Em cumprimento']])}</section>`;
 }
 if(tab==='PLANTEIS'){html=`<section class="panel"><div class="season-head"><div><span class="eyebrow">JOGO #${j.id}</span><h2>${['FINALIZADO','HOMOLOGADO'].includes(j.estado)?'Plantéis no fecho':'Convocatórias do jogo'}</h2></div>${open&&j.estado==='AGENDADO'?button('callup','Preparar convocatórias'):''}</div><div class="roster-columns">${rosterTeam(j.casa_id,'Casa')}${rosterTeam(j.fora_id,'Visitante')}</div></section>`;}
 if(tab==='ARBITRAGEM'){html=`<section class="panel"><div class="season-head"><h2>Equipa de arbitragem</h2>${open?button('referee','Associar oficial'):''}</div>${table(game.arbitragem,[['Oficial','nome'],['Função','funcao']])}</section>`;}
 if(tab==='SEGURANCA'){const o=game.seguranca;html=`<section class="panel"><div class="season-head"><div><span class="eyebrow">SEGURANÇA</span><h2>Operação ${esc(o.estado)}</h2></div>${statePill(o.estado==='FINALIZADA'?'HOMOLOGADO':o.estado==='EM_CURSO'?'EM_CURSO':'NAO_AGENDADO')}</div><p>O fim do jogo não fecha automaticamente a operação de segurança.</p><p>${esc(o.avaliacao||'Avaliação posterior pendente')}</p><div class="actions">`;if(writable()){if(game.epoca?.estado!=='FINALIZADA'&&o.estado==='PLANEADA')html+=button('security-plan','Preparar operação')+button('security-start','Iniciar operação');if(game.epoca?.estado!=='FINALIZADA'&&o.estado==='EM_CURSO'){html+=button('incident','Registar ocorrência');if(game.jogo.estado==='FINALIZADO')html+=button('security-finish','Finalizar operação');else html+=`<button type="button" class="secondary" disabled title="Disponível apenas após o FIM do jogo">Finalizar operação · aguarda FIM do jogo</button>`;}if(o.estado==='FINALIZADA'&&admin())html+=button('rectify-security','Retificar operação finalizada','class="secondary"');}html+=`</div><h3>Efetivos</h3>${table(game.efetivos,[['Efetivo','nome']])}<h3>Ocorrências</h3>${table(game.ocorrencias,[['Descrição','descricao'],['Instante','instante'],['Envolvidos','envolvidos'],['Evidência','evidencia'],['Feridos','feridos'],['Assistência','assistencia'],['Uso da força',r=>r.uso_forca?'Sim — '+esc(r.justificacao_forca):'Não']])}<h3>Adendas</h3>${table(game.correcoes_seguranca,[['Texto','texto'],['Registo','criado_em']])}</section>`;}
 if(tab==='TIMELINE')html=`<section class="panel"><h2>Timeline do jogo</h2><div class="timeline">${game.eventos.map(e=>`<article><b>${esc(e.tempo)}</b><small>${e.periodo}.º período · sequência ${e.seq}</small><p>${esc(e.tipo.replaceAll('_',' '))} ${esc(e.jogador||'')}${e.entra?' → '+esc(e.entra):''}${e.valido?'':' · ANULADO (histórico preservado)'}</p></article>`).join('')||'<p class="muted">Ainda sem eventos.</p>'}</div></section>`;
 $('#cockpit').innerHTML=html;
}
const event=(tipo,periodo=game.jogo.periodo,segundos=game.jogo.segundos)=>command('EVENTO',{jogo_id:game.jogo.id,tipo,periodo,segundos});
async function action(name,el){const j=game?.jogo,base={jogo_id:j?.id};
 if(name==='print-report'){window.print();return;}
 if(name==='clear-round'){$('#round').value='';updateContextHint();await refresh();return;}
 switch(name){
 case 'close-season':return form('Finalizar Liga','<p>A classificação e o campeão ficam guardados; a operação normal será bloqueada.</p>',()=>command('FINALIZAR_EPOCA',{epoca_id:season()}));
 case 'close':if(pendingIntent){await command('CANCELAR_RETIFICACAO',{intencao_id:pendingIntent});pendingIntent=null;}$('#modal').close();return;
 case 'clear-filter':filter='';return refresh();
 case 'start':await event('INICIO',1,0);break;case 'half':await event('INTERVALO',1,1200);break;case 'second':await event('SEGUNDA_PARTE',2,0);break;case 'finish':await event('FIM',2,1200);break;case 'resume':await event('RETOMA');break;
 case 'simulate':await command('SIMULAR',base);break;case 'simulate-round':await command('SIMULAR_JORNADA',base);break;case 'homologate':await command('HOMOLOGAR',base);break;case 'postpone':await command('ADIAR',base);break;
 case 'security-start':await command('INICIAR_SEGURANCA',base);break;
 case 'remove-player':await command('REMOVER_CONVOCADO',{...base,id:Number(el.dataset.id)});break;
 case 'schedule':{
  const casa=cat.equipas.find(x=>x.id===j.casa_id)?.nome||'Equipa da casa',fora=cat.equipas.find(x=>x.id===j.fora_id)?.nome||'Equipa visitante';
  const expected=Number(j.recinto_esperado),expectedName=cat.recintos.find(x=>x.id===expected)?.nome||'Recinto da equipa da casa';
  const fixture=`<div class="fixture-lock"><div><small>CASA</small><strong>${esc(casa)}</strong></div><span>VS</span><div><small>VISITANTE</small><strong>${esc(fora)}</strong></div><p>Emparelhamento definido pela jornada. As equipas não são alteráveis no agendamento.</p></div>`;
  const venueOptions=opt(cat.recintos,'id','nome',expected)+`<option value="__OUTRO__">＋ Outro recinto (não está na lista)</option>`;
  $('#modalBody').innerHTML=`<h2>Agendar jogo</h2><form id="dialogForm">${fixture}${input('inicio','Data e hora','datetime-local','','required')}${select('recinto_id','Recinto',venueOptions)}<p class="venue-choice-note">Recinto previsto: <strong>${esc(expectedName)}</strong>. Podes escolher outro recinto; se não existir na lista, cria-o aqui sem sair do agendamento.</p><div id="newVenue" hidden><div class="venue-new-grid">${input('novo_recinto_nome','Nome do novo recinto','text','','minlength="3"')}${input('novo_recinto_cidade','Cidade','text','','minlength="2"')}${input('novo_recinto_capacidade','Capacidade','number','','min="1"')}</div></div><div id="venueReason" hidden>${input('motivo','Motivo da alteração do recinto','text','','minlength="5"')}</div><div class="actions"><button>Guardar agendamento</button><button type="button" data-action="close" class="secondary">Cancelar</button></div></form>`;
  $('#modal').showModal();
  const f=$('#dialogForm'),reason=$('#venueReason'),newVenue=$('#newVenue'),sync=()=>{const isNew=f.recinto_id.value==='__OUTRO__';const changed=isNew||Number(f.recinto_id.value)!==expected;reason.hidden=!changed;f.motivo.required=changed;newVenue.hidden=!isNew;for(const n of ['novo_recinto_nome','novo_recinto_cidade','novo_recinto_capacidade'])f[n].required=isNew;if(!changed)f.motivo.value='';};f.recinto_id.onchange=sync;sync();
  f.onsubmit=async e=>{e.preventDefault();const d=Object.fromEntries(new FormData(f));try{let recintoId;if(d.recinto_id==='__OUTRO__'){const created=await command('CRIAR_RECINTO',{nome:d.novo_recinto_nome,cidade:d.novo_recinto_cidade,capacidade:Number(d.novo_recinto_capacidade)});recintoId=Number(created.id);cat.recintos.push({id:recintoId,nome:created.nome,cidade:created.cidade,capacidade:created.capacidade});}else recintoId=Number(d.recinto_id);await command('AGENDAR',{...base,inicio:d.inicio,recinto_id:recintoId,motivo:d.motivo||null});$('#modal').close();notice('Jogo agendado');await refresh();}catch(err){notice(err.message);}};return;
 }
 case 'venue':{
  const options=opt(cat.recintos,'id','nome',j.recinto_id)+`<option value="__OUTRO__">＋ Outro recinto (não está na lista)</option>`;
  $('#modalBody').innerHTML=`<h2>Alterar recinto</h2><form id="dialogForm">${select('recinto_id','Recinto utilizado',options)}<div id="newVenue" hidden><div class="venue-new-grid">${input('novo_recinto_nome','Nome do novo recinto','text','','minlength="3"')}${input('novo_recinto_cidade','Cidade','text','','minlength="2"')}${input('novo_recinto_capacidade','Capacidade','number','','min="1"')}</div></div>${input('motivo','Motivo','text','','required minlength="5"')}<div class="actions"><button>Guardar</button><button type="button" data-action="close" class="secondary">Cancelar</button></div></form>`;$('#modal').showModal();const f=$('#dialogForm'),nv=$('#newVenue'),sync=()=>{const on=f.recinto_id.value==='__OUTRO__';nv.hidden=!on;for(const n of ['novo_recinto_nome','novo_recinto_cidade','novo_recinto_capacidade'])f[n].required=on;};f.recinto_id.onchange=sync;sync();f.onsubmit=async e=>{e.preventDefault();const d=Object.fromEntries(new FormData(f));try{let rid;if(d.recinto_id==='__OUTRO__'){const created=await command('CRIAR_RECINTO',{nome:d.novo_recinto_nome,cidade:d.novo_recinto_cidade,capacidade:Number(d.novo_recinto_capacidade)});rid=Number(created.id);cat.recintos.push({id:rid,nome:created.nome,cidade:created.cidade,capacidade:created.capacidade});}else rid=Number(d.recinto_id);await command('RECINTO',{...base,recinto_id:rid,motivo:d.motivo});$('#modal').close();notice('Recinto atualizado');await refresh();}catch(err){notice(err.message);}};return;
 }
 case 'referee':return form('Nomear arbitragem',select('pessoa_id','Oficial',opt(cat.arbitros))+select('funcao','Função',['ARBITRO','SEGUNDO_ARBITRO','CRONOMETRISTA','TERCEIRO_ARBITRO'].map(x=>`<option>${x}</option>`).join('')),d=>command('ARBITRAGEM',{...base,...d}));
 case 'security-plan':return form('Preparar operação',select('responsavel_id','Responsável',opt(cat.agentes))+cat.agentes.map(a=>`<label><input type="checkbox" name="agente_${a.id}">${esc(a.nome)} · ${esc(a.entidade)}</label>`).join(''),d=>command('PREPARAR_SEGURANCA',{...base,responsavel_id:Number(d.responsavel_id),agentes:Object.keys(d).filter(k=>k.startsWith('agente_')).map(k=>Number(k.slice(7)))}));
 case 'security-finish':return form('Finalizar operação',input('avaliacao','Avaliação posterior','text','','required minlength="5"'),d=>command('FINALIZAR_SEGURANCA',{...base,...d}));
 case 'callup':{
  $('#modalBody').innerHTML=`<h2>Preparar convocatórias</h2><p class="muted">Casa e Visitante estão separados. Escolhe um único guarda-redes titular por equipa; nas linhas dos jogadores ficam apenas Convocar e Titular.</p><form id="dialogForm"><div class="callup-teams">${callupTeam(j.casa_id,'Casa')}${callupTeam(j.fora_id,'Visitante')}</div><div class="actions"><button>Guardar convocatórias</button><button type="button" data-action="close" class="secondary">Cancelar</button></div></form>`;
  $('#modal').showModal();const f=$('#dialogForm');
  const syncKeeper=teamId=>{const keeper=f[`keeper_${teamId}`];if(!keeper)return;const kid=String(keeper.value),players=game.elegiveis.filter(p=>Number(p.equipa_id)===Number(teamId));const target=f[`starter_${kid}`];if(target)target.checked=true;let checked=players.filter(p=>f[`starter_${p.camisola_id}`]?.checked);if(checked.length>5){for(const p of [...checked].reverse()){if(String(p.camisola_id)!==kid){f[`starter_${p.camisola_id}`].checked=false;checked=checked.filter(x=>x.camisola_id!==p.camisola_id);if(checked.length<=5)break;}}}};
  for(const tid of [j.casa_id,j.fora_id]){const sel=f[`keeper_${tid}`];if(sel){sel.onchange=()=>syncKeeper(tid);syncKeeper(tid);}}
  f.onsubmit=async e=>{e.preventDefault();const d=Object.fromEntries(new FormData(f));try{const jogadores=game.elegiveis.filter(p=>d['call_'+p.camisola_id]).map(p=>{const keeper=String(d['keeper_'+p.equipa_id]||'')===String(p.camisola_id);return {vinculo_id:p.vinculo_id,camisola_id:p.camisola_id,titular:keeper||!!d['starter_'+p.camisola_id],goleiro:keeper};});await command('GUARDAR_CONVOCATORIA',{...base,jogadores});$('#modal').close();notice('Convocatórias guardadas');await refresh();}catch(err){notice(err.message);}};return;
 }
 case 'interrupt':return form('Interromper jogo',input('tempo','Instante MM:SS','text',time(j),'required pattern="[0-9]{2}:[0-5][0-9]"'),d=>{const [m,s]=d.tempo.split(':').map(Number);return command('EVENTO',{...base,tipo:'INTERRUPCAO',periodo:j.periodo,segundos:m*60+s-(j.periodo-1)*1200});});
 case 'event':{
 form('Registar evento',select('tipo','Evento',['GOLO','FALTA','AMARELO','VERMELHO_DIRETO','SUBSTITUICAO','REPOSICAO','RELOGIO'].map(t=>`<option>${t}</option>`).join(''))+input('tempo','Relógio MM:SS','text',time(j),'required pattern="[0-9]{2}:[0-5][0-9]"')+select('equipa_id','Equipa',opt(cat.equipas.filter(e=>[j.casa_id,j.fora_id].includes(e.id))))+'<div id="eventFields"></div>',d=>{const [m,s]=d.tempo.split(':').map(Number);return command('EVENTO',{...base,tipo:d.tipo,periodo:j.periodo,segundos:m*60+s-(j.periodo-1)*1200,equipa_id:d.tipo==='RELOGIO'?null:Number(d.equipa_id),jogador_id:d.jogador_id?Number(d.jogador_id):null,entra_id:d.entra_id?Number(d.entra_id):null,detalhe:{classe:d.classe,autorizado_por:d.autorizado_por}});});
 const fields=()=>{const f=$('#dialogForm'),tipo=f.tipo.value,team=Number(f.equipa_id.value),ps=game.convocados.filter(x=>x.equipa_id===team&&x.estado!=='EXPULSO');let h='';if(!['RELOGIO','REPOSICAO'].includes(tipo))h+=select('jogador_id',tipo==='SUBSTITUICAO'?'Sai':'Jogador',opt(ps.filter(x=>['AMARELO','VERMELHO_DIRETO'].includes(tipo)||x.estado==='EM_CAMPO')));if(['REPOSICAO','SUBSTITUICAO'].includes(tipo))h+=select('entra_id','Entra',opt(ps.filter(x=>x.estado==='BANCO')));if(tipo==='FALTA')h+=select('classe','Livre decorrente','<option>DIRETO</option><option>INDIRETO</option>');if(tipo==='REPOSICAO')h+=select('autorizado_por','Autorização de entrada','<option>CRONOMETRISTA</option><option>TERCEIRO_ARBITRO</option>');$('#eventFields').innerHTML=h;};$('#dialogForm').tipo.onchange=fields;$('#dialogForm').equipa_id.onchange=fields;fields();return;}
 case 'incident':{
  $('#modalBody').innerHTML=`<h2>Registar ocorrência de segurança</h2><p class="muted">Regista o essencial do incidente. Os campos adicionais só aparecem quando são necessários.</p><form id="dialogForm" autocomplete="off"><label>Descrição<textarea name="descricao" required minlength="5" placeholder="Ex.: desacatos junto à bancada norte"></textarea><span>Mínimo 5 caracteres.</span></label>${input('envolvidos','Envolvidos','text','','required minlength="2" placeholder="Sócios, adeptos, equipa..."')}${input('evidencia','N.º do auto / referência','text','','required placeholder="Ex.: 212 ou Auto PSP 212"')}${input('feridos','Feridos','number','0','required min="0" step="1"')}<div id="assistWrap" hidden>${input('assistencia','Assistência prestada','text','','placeholder="Ex.: INEM no local"')}</div>${select('uso_forca','Uso da força','<option value="false">Não</option><option value="true">Sim</option>')}<div id="forceWrap" hidden>${input('justificacao_forca','Justificação e meios utilizados','text','','placeholder="Descrever motivo e meios utilizados"')}</div><div class="actions"><button>Guardar ocorrência</button><button type="button" data-action="close" class="secondary">Cancelar</button></div></form>`;
  $('#modal').showModal();const f=$('#dialogForm'),assist=$('#assistWrap'),force=$('#forceWrap');
  const sync=()=>{const injured=Number(f.feridos.value)>0;assist.hidden=!injured;f.assistencia.required=injured;f.assistencia.minLength=injured?3:0;const used=f.uso_forca.value==='true';force.hidden=!used;f.justificacao_forca.required=used;f.justificacao_forca.minLength=used?5:0;};f.feridos.oninput=sync;f.uso_forca.onchange=sync;sync();
  f.onsubmit=async e=>{e.preventDefault();const d=Object.fromEntries(new FormData(f));try{await command('OCORRENCIA',{...base,...d,descricao:d.descricao.trim(),envolvidos:d.envolvidos.trim(),evidencia:d.evidencia.trim(),feridos:Number(d.feridos),assistencia:Number(d.feridos)>0?d.assistencia.trim():null,uso_forca:d.uso_forca==='true',justificacao_forca:d.uso_forca==='true'?d.justificacao_forca.trim():null});$('#modal').close();notice('Ocorrência registada');await refresh();}catch(err){notice(err.message);}};return;
 }
 case 'rectify-game':case 'rectify-security':{
 const obj=name==='rectify-game'?'JOGO':'SEGURANCA',id=obj==='JOGO'?j.id:game.seguranca.id;
 return form('Registar intenção de retificação',input('motivo','Motivo','text','','required minlength="5"'),async d=>{const r=await command('INTENCAO',{objeto:obj,objeto_id:id,motivo:d.motivo});pendingIntent=r.id;setTimeout(()=>rectification(obj),0);});}
 case 'drill':{const d=await api('super/detalhe?id='+encodeURIComponent(el.dataset.id)),i=d.intencao||{},o=d.desfecho||{},req=o.detalhe?.pedido||{},integ=d.integridade||{};$('#modalBody').innerHTML=`<div class="evidence-head"><span class="evidence-icon">◎</span><div><span class="eyebrow">EVIDÊNCIA AUDITÁVEL</span><h2>${esc(i.objeto||'Objeto')} #${esc(i.objeto_id||'')}</h2><p>${esc(i.motivo||'Intervenção registada')}</p></div><span class="pill ${o.resultado==='REJEITADA'?'red-pill':o.resultado==='EXECUTADA'?'green-pill':'orange-pill'}">${esc(o.resultado||'ABERTA')}</span></div><div class="evidence-grid"><article><small>Registo</small><b>${fmtDate(i.criado_em)}</b></article><article><small>Rasto operacional</small><b>${(d.auditoria||[]).length} entradas</b></article><article><small>Provas forenses</small><b>${(d.forense||[]).length} registos</b></article><article><small>Integridade</small><b>${integ.integra?'Íntegra':'Divergente'}</b></article></div><section class="evidence-section"><h3>Pedido registado</h3>${Object.keys(req).length?`<div class="evidence-fields">${Object.entries(req).filter(([k])=>!['password','nova'].includes(k)).map(([k,v])=>`<div><span>${esc(k.replaceAll('_',' '))}</span><strong>${esc(typeof v==='object'?JSON.stringify(v):v)}</strong></div>`).join('')}</div>`:'<p class="muted">Sem dados adicionais no pedido.</p>'}</section><details class="technical-details"><summary>Ver detalhes técnicos / JSON</summary><pre>${esc(JSON.stringify(d,null,2))}</pre></details><div class="actions">${button('close','Fechar')}</div>`;$('#modal').showModal();return;}
 case 'add-player':{
  if(seasonClosed())throw Error('Época FINALIZADA: plantel histórico em modo de leitura');const rows=await api(`planteis?epoca_id=${season()}`),clubs=clubCatalog(rows),initialClub=Number(selectedClubId||clubs[0]?.id),initialTeam=Number(el.dataset.teamId||selectedTeamId||clubs.find(c=>c.id===initialClub)?.equipas[0]?.id);
  $('#modalBody').innerHTML=`<h2>Adicionar jogador ao plantel</h2><p class="muted">Escolhe primeiro o clube e depois a equipa. O vínculo e o dorsal ficam associados à equipa selecionada.</p><form id="dialogForm" autocomplete="off"><div class="form-step"><span>1</span><label>Clube<select name="clube_id">${clubs.map(c=>`<option value="${c.id}" ${c.id===initialClub?'selected':''}>${esc(c.nome)}</option>`).join('')}</select></label></div><div class="form-step"><span>2</span><label>Equipa<select name="equipa_id"></select></label></div><div class="grid">${input('nome','Nome','text','','required')}${input('nif','NIF fictício','text','','pattern="[0-9]{9}"')}${input('email','Email','email')}${input('telefone','Telefone')}${input('numero','Camisola','number','','required min="1" max="99"')}${input('inicio','Início do vínculo','date',new Date().toISOString().slice(0,10),'required')}${input('fim','Fim do vínculo (opcional)','date')}</div><div class="actions"><button>Adicionar ao plantel</button><button type="button" data-action="close" class="secondary">Cancelar</button></div></form>`;$('#modal').showModal();const f=$('#dialogForm'),syncTeams=()=>{const cid=Number(f.clube_id.value),teams=cat.equipas.filter(t=>Number(t.clube_id)===cid);f.equipa_id.innerHTML=teams.map(t=>`<option value="${t.id}" ${Number(t.id)===initialTeam?'selected':''}>${esc(t.nome)} · ${esc(t.categoria||'Sénior')}</option>`).join('');};f.clube_id.onchange=syncTeams;syncTeams();f.onsubmit=async e=>{e.preventDefault();const d=Object.fromEntries(new FormData(f));try{selectedClubId=Number(d.clube_id);selectedTeamId=Number(d.equipa_id);delete d.clube_id;d.equipa_id=Number(d.equipa_id);d.epoca_id=season();await command('ADICIONAR_JOGADOR',d);$('#modal').close();notice('Jogador adicionado ao plantel');await refresh();}catch(err){notice(err.message);}};return;
 }
 case 'edit-person':return form('Editar dados da pessoa',input('nome','Nome','text',el.dataset.name,'required')+input('email','Email','email')+input('telefone','Telefone'),d=>command('PESSOA',{...d,pessoa_id:Number(el.dataset.person),epoca_id:season()}));
 case 'number':return form('Atribuir novo número',input('numero','Número','number','','required min="1" max="99"')+input('inicio','A partir de','date','','required'),d=>command('NUMERO',{...d,vinculo_id:Number(el.dataset.vinculo),epoca_id:season()}));
 case 'end-link':return form('Terminar vínculo preservando histórico',input('fim','Último dia','date','','required'),d=>command('TERMINAR_VINCULO',{...d,vinculo_id:Number(el.dataset.vinculo),epoca_id:season()}));
 case 'new-user':return form('Criar utilizador',input('nome','Nome','text','','required')+input('email','Email','email','','required')+input('password','Password temporária','password','','required minlength="12"')+select('role','Role','<option>LEITOR</option><option>OPERADOR</option><option>ADMIN</option>'),d=>command('CRIAR_UTILIZADOR',d));
 }
 await refresh();notice('Operação concluída');
}
function rectification(obj){
 const events=game.eventos.filter(e=>e.tipo==='GOLO'||(me.roles.includes('SUPER_AUDITOR')&&['VERMELHO_DIRETO','EXPULSAO_SEGUNDO_AMARELO'].includes(e.tipo)));
 const fields=obj==='JOGO'?'<p>O evento original é preservado. A revisão do vermelho é uma decisão posterior: não altera o que ocorreu em campo. Numa Liga FINALIZADA, alterações ao resultado são bloqueadas e auditadas.</p>'+select('evento_id','Evento a retificar',events.map(e=>'<option value="'+e.id+'">'+esc(e.tipo)+' · '+esc(e.tempo)+' · '+esc(e.jogador)+' · '+(e.valido?'Válido':'Anulado')+'</option>').join(''))+select('valido','Novo estado','<option value="false">Anulado</option><option value="true">Válido</option>'):input('texto','Adenda à operação finalizada','text','','required minlength="5"');
 form('Retificação em curso',fields,async d=>{try{await command('RETIFICAR',{intencao_id:pendingIntent,...d,tipo:events.find(e=>String(e.id)===d.evento_id)?.tipo==='GOLO'?'GOLO':'CARTAO_VERMELHO',valido:d.valido==='true'});}catch(err){$('#modal').close();await refresh();throw err;}finally{pendingIntent=null;}});
}

document.addEventListener('click',async e=>{const el=e.target.closest('button');if(!el)return;try{if(el.dataset.view){view=el.dataset.view;filter='';await refresh();}else if(el.dataset.club){selectedClubId=Number(el.dataset.club);selectedTeamId=null;await refresh();}else if(el.dataset.team){selectedTeamId=Number(el.dataset.team);await refresh();}else if(el.dataset.report){activeReport=el.dataset.report;$('#content').innerHTML=reportCenter();await renderReport();}else if(el.dataset.filter){filter=el.dataset.filter;view='jogos';await refresh();}else if(el.dataset.game){view='jogo';tab='JOGO';await loadGame(Number(el.dataset.game));}else if(el.dataset.securityGame){view='jogo';tab='SEGURANCA';await loadGame(Number(el.dataset.securityGame));}else if(el.dataset.tab){tab=el.dataset.tab;await loadGame(game.jogo.id);}else if(el.dataset.action){el.disabled=true;try{await action(el.dataset.action,el);}finally{el.disabled=false;}}}catch(err){notice(err.message);}});
$('#modal').addEventListener('cancel',e=>{if(pendingIntent){e.preventDefault();action('close').catch(e=>notice(e.message));}});
$('#login').onsubmit=async e=>{e.preventDefault();try{await api('login',Object.fromEntries(new FormData(e.target)));await boot();}catch(err){notice(err.message);}};
$('#logout').onclick=async()=>{await command('LOGOUT');location.reload();};$('#season').onchange=()=>{view='dashboard';filter='';selectedClubId=null;selectedTeamId=null;updateRounds();updateContextHint();refresh().catch(e=>notice(e.message));};$('#round').onchange=()=>{filter='';updateContextHint();refresh().catch(e=>notice(e.message));};
boot().catch(()=>{});
