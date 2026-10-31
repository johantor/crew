const { chromium } = require('playwright');
const fs = require('fs');
const OUT = __dirname;
const C = { bg:'#F5EFE3', ink:'#22201C', mute:'#7D776B', red:'#C8472B', sage:'#5E7F63', mustard:'#D99A2B', card:'#FFFDF8', line:'#D9D0BE', steel:'#D7DADD', steelD:'#8C9196', wood:'#5A3B2A' };
const W=1920,H=1080;
const esc=s=>s.replace(/&/g,'&amp;').replace(/</g,'&lt;');
const T=(x,y,s,o={})=>`<text x="${x}" y="${y}" font-family="${o.f||'Inter'}" font-size="${o.size||32}" font-weight="${o.w||400}" fill="${o.c||C.ink}" text-anchor="${o.a||'start'}" ${o.extra||''}>${esc(s)}</text>`;
const title=(t,sub)=>T(120,150,t,{f:'Inter Display',size:76,w:700})+(sub?T(120,215,sub,{size:34,c:C.mute}):'');
const footer=n=>T(120,1020,'My Knives',{size:24,w:600,c:C.mute})+T(1800,1020,String(n),{size:24,c:C.mute,a:'end'});
const hat=(x,y,s,col=C.card)=>`<g transform="translate(${x},${y}) scale(${s})" stroke="${C.ink}" stroke-width="3"><circle cx="-24" cy="-14" r="20" fill="${col}"/><circle cx="24" cy="-14" r="20" fill="${col}"/><circle cx="0" cy="-28" r="25" fill="${col}"/><rect x="-30" y="-14" width="60" height="34" fill="${col}" stroke="none"/><path d="M-30,-10 L-30,20 M30,-10 L30,20" fill="none"/><rect x="-32" y="18" width="64" height="14" rx="3" fill="${col}"/></g>`;
const knife=(x,y,len,label,rot=0,col=C.red)=>`<g transform="translate(${x},${y}) rotate(${rot})">
 <rect x="-170" y="-12" width="170" height="36" rx="12" fill="${C.wood}"/><circle cx="-130" cy="6" r="5" fill="${C.steel}"/><circle cx="-85" cy="6" r="5" fill="${C.steel}"/><circle cx="-40" cy="6" r="5" fill="${C.steel}"/>
 <rect x="-6" y="-16" width="14" height="44" rx="3" fill="${C.steelD}"/>
 <path d="M8,-16 L${len},-16 Q${len+40},-16 ${len+70},-10 Q${len+30},34 ${len-50},34 L8,34 Z" fill="${C.steel}" stroke="${C.steelD}" stroke-width="2"/>
 <path d="M8,26 L${len-50},26" stroke="#FFFFFF" stroke-width="3" opacity=".7"/>
 ${label?`<rect x="${len*0.25}" y="-6" width="${len*0.5}" height="30" rx="15" fill="${col}"/>`+T(len*0.5,16,label,{f:'JetBrains Mono',size:20,w:600,c:'#fff',a:'middle'}):''}
</g>`;
const card=(x,y,w,h,extra='')=>`<rect x="${x}" y="${y}" width="${w}" height="${h}" rx="18" fill="${C.card}" stroke="${C.line}" stroke-width="2" ${extra}/>`;
const chip=(x,y,s,col)=>{const w=s.length*12.5+36;return `<rect x="${x}" y="${y}" width="${w}" height="44" rx="22" fill="${col}"/>`+T(x+w/2,y+29,s,{f:'JetBrains Mono',size:20,w:600,c:'#fff',a:'middle'});};
const arrow=(x1,y1,x2,y2,c=C.ink)=>`<line x1="${x1}" y1="${y1}" x2="${x2}" y2="${y2}" stroke="${c}" stroke-width="4" marker-end="url(#ah)"/>`;
const defs=`<defs><marker id="ah" viewBox="0 0 10 10" refX="8" refY="5" markerWidth="5" markerHeight="5" orient="auto"><path d="M0,0 L10,5 L0,10 z" fill="${C.ink}"/></marker></defs>`;
const svg=b=>`<svg xmlns="http://www.w3.org/2000/svg" width="${W}" height="${H}" viewBox="0 0 ${W} ${H}">${defs}<rect width="${W}" height="${H}" fill="${C.bg}"/>${b}</svg>`;

const imgs={};
// 1 title
imgs['01-title']=svg(`
${T(120,420,'My Knives',{f:'Inter Display',size:150,w:800})}
${T(126,500,'A personal toolkit for agent development',{size:40,c:C.mute})}
<rect x="126" y="560" width="120" height="8" fill="${C.red}"/>
${T(126,640,'You can copy the knives.',{size:36})}
${T(126,690,"You won't cook like the chef.",{size:36,w:600})}
<g transform="translate(980,170)"><rect width="820" height="740" rx="30" fill="#7A5236"/><rect x="24" y="24" width="772" height="692" rx="20" fill="#8E6141"/>
${[0,1,2,3,4].map(i=>`<rect x="40" y="${60+i*130}" width="740" height="96" rx="14" fill="#7A5236" opacity=".55"/>`).join('')}
${knife(260,90,400,'the plan')}${knife(260,220,330,'lead',0,C.ink)}${knife(260,350,430,'skills',0,C.sage)}${knife(260,480,300,'hooks',0,C.mustard)}${knife(260,610,370,'the gate')}
</g>`);
// 2 brigade
const groups=[['Before the plan',['analyst','architect','designer','copywriter'],C.mustard],['Build',['backend','frontend','unit-tests','e2e','generalist'],C.red],['Review',['security-review','web-review','visual-review'],C.sage],['After merge',['incident-triage','debt-scout'],C.ink]];
let g2='';const gx=[120,560,1000,1440],gw=380;
groups.forEach(([n,ws,col],i)=>{const x=gx[i];g2+=card(x,640,gw,340)+T(x+30,695,n,{size:30,w:700,c:col});ws.forEach((w,j)=>{g2+=chip(x+30,720+j*50,w,col)});g2+=`<path d="M960,560 L960,600 L${x+gw/2},600 L${x+gw/2},636" fill="none" stroke="${C.ink}" stroke-width="3"/>`;});
imgs['02-brigade']=svg(`${title('The kitchen','I am the chef. lead is my sous chef. The stations cut to my liking.')}
${hat(960,330,1.5)}${T(1060,320,'Chef',{size:40,w:700})}${T(1060,360,'me: sets the menu, tastes, sends the plate',{size:26,c:C.mute})}
<line x1="960" y1="390" x2="960" y2="430" stroke="${C.ink}" stroke-width="3"/>
${hat(960,490,1.1,'#EDE4D3')}${T(1050,480,'Sous chef: lead',{size:36,w:700})}${T(1050,518,'plans, delegates, verifies, commits. Writes no code.',{size:26,c:C.mute})}
<line x1="960" y1="530" x2="960" y2="560" stroke="${C.ink}" stroke-width="3"/>
${g2}`);
// 3 recipe
const rows=[['1','backend','API returns 201','done','a1f3c9e'],['2','unit-tests','covers 3 edge cases','done','7be20d4'],['3','frontend','form posts, shows state','in-progress',''],['4','e2e','signup flow green','pending','']];
let r3='';rows.forEach((r,i)=>{const y=520+i*80;const col=r[3]=='done'?C.sage:r[3]=='in-progress'?C.mustard:C.mute;
 r3+=`<line x1="200" y1="${y+30}" x2="1240" y2="${y+30}" stroke="${C.line}" stroke-width="2"/>`;
 r3+=(r[3]=='done'?`<rect x="210" y="${y-26}" width="34" height="34" rx="6" fill="${C.sage}"/><path d="M217,${y-9} L225,${y-1} L238,${y-18}" stroke="#fff" stroke-width="4" fill="none"/>`:`<rect x="210" y="${y-26}" width="34" height="34" rx="6" fill="none" stroke="${col}" stroke-width="3"/>`);
 r3+=T(270,y,r[1],{f:'JetBrains Mono',size:26,w:600})+T(500,y,r[2],{size:26})+T(900,y,r[3],{f:'JetBrains Mono',size:24,c:col,w:600})+T(1090,y,r[4]||'—',{f:'JetBrains Mono',size:24,c:r[4]?C.red:C.mute});});
imgs['03-recipe']=svg(`${title('The plan is a recipe','Who does what, when, the input and the outcome.')}
<g transform="rotate(-1.5 720 600)">${card(160,290,1120,560)}
${T(200,350,'plan-newsletter-signup.md',{f:'JetBrains Mono',size:30,w:700})}
${T(200,395,'base-branch: main   feature-branch: feat/newsletter',{f:'JetBrains Mono',size:22,c:C.mute})}
${T(270,465,'WORKER',{size:20,w:700,c:C.mute,extra:'letter-spacing="2"'})}${T(500,465,'ACCEPTANCE',{size:20,w:700,c:C.mute,extra:'letter-spacing="2"'})}${T(900,465,'STATUS',{size:20,w:700,c:C.mute,extra:'letter-spacing="2"'})}${T(1090,465,'EVIDENCE',{size:20,w:700,c:C.mute,extra:'letter-spacing="2"'})}
${r3}</g>
${T(1380,420,'Who',{size:40,w:700,c:C.red})}${T(1380,460,'one worker per step',{size:28,c:C.mute})}
${T(1380,560,'When',{size:40,w:700,c:C.red})}${T(1380,600,'depends-on',{size:28,c:C.mute,f:'JetBrains Mono'})}
${T(1380,700,'Outcome',{size:40,w:700,c:C.red})}${T(1380,740,'acceptance, checked',{size:28,c:C.mute})}
${T(1380,840,'Proof',{size:40,w:700,c:C.red})}${T(1380,880,'a commit SHA per step',{size:28,c:C.mute})}`);
// 4 kill and resume
const mini=(x,y,states)=>card(x,y,440,360)+T(x+30,y+56,'plan file',{f:'JetBrains Mono',size:26,w:700})+states.map((s,i)=>{const yy=y+120+i*60;const col=s=='done'?C.sage:s=='in-progress'?C.mustard:C.mute;return T(x+30,yy,`step ${i+1}`,{f:'JetBrains Mono',size:24})+T(x+180,yy,s,{f:'JetBrains Mono',size:24,w:600,c:col})}).join('');
imgs['04-kill-resume']=svg(`${title("Turn off the computer. Lose nothing.",'The plan and git hold the run, not the session.')}
${mini(120,340,['done','done','in-progress','pending'])}
${T(340,760,'Session 1',{size:30,w:700,a:'middle'})}
<g transform="translate(960,520)"><circle r="110" fill="${C.red}"/><path d="M-45,-40 A60,60 0 1,0 45,-40" stroke="#fff" stroke-width="16" fill="none" stroke-linecap="round"/><line x1="0" y1="-70" x2="0" y2="0" stroke="#fff" stroke-width="16" stroke-linecap="round"/></g>
${T(960,690,'killed mid-step',{size:30,w:600,a:'middle',c:C.red})}
${arrow(600,520,820,520)}${arrow(1100,520,1340,520)}
${mini(1360,340,['done','done','pending','pending'])}
${T(1580,760,'Session 2',{size:30,w:700,a:'middle'})}
${T(1580,800,'checks git, resets step 3, goes on',{size:24,c:C.mute,a:'middle'})}
${card(120,850,1680,110)}
${T(160,905,'git log',{f:'JetBrains Mono',size:24,w:700,c:C.mute})}${T(320,905,'7be20d4  step 2: unit tests for signup',{f:'JetBrains Mono',size:24})}${T(1000,905,'a1f3c9e  step 1: signup endpoint',{f:'JetBrains Mono',size:24})}
${T(320,940,'one verified commit per step',{size:22,c:C.mute})}`);
// 5 house style
const books=['engineering-principles','backend-dotnet','accessibility','seo','design-tokens','worker-contract'];
imgs['05-house-style']=svg(`${title('Written down once','I don\'t tell my staff how to cut. That is what a skill is.')}
<g transform="translate(140,320)"><path d="M0,30 Q330,-20 330,40 L330,600 Q330,560 0,600 Z" fill="${C.card}" stroke="${C.ink}" stroke-width="3"/><path d="M660,30 Q330,-20 330,40 L330,600 Q330,560 660,600 Z" fill="${C.card}" stroke="${C.ink}" stroke-width="3"/>
${T(40,110,'House style',{f:'DejaVu Serif',size:40,w:700})}${T(40,160,'skills, loaded on need',{size:24,c:C.mute})}
${books.map((b,i)=>T(355,110+i*70,'• '+b,{f:'JetBrains Mono',size:19})).join('')}
${T(40,260,'.claude/crew.md',{f:'JetBrains Mono',size:24,c:C.red,w:600})}${T(40,300,'my config, per project',{size:22,c:C.mute})}
${T(40,380,'CLAUDE.md',{f:'JetBrains Mono',size:24,c:C.red,w:600})}${T(40,420,'my conventions',{size:22,c:C.mute})}</g>
${arrow(840,620,1100,460)}${arrow(840,620,1100,620)}${arrow(840,620,1100,780)}
${[460,620,780].map((y,i)=>hat(1180,y+10,0.9)+T(1250,y+10,['backend','frontend','unit-tests'][i],{f:'JetBrains Mono',size:30,w:600})+T(1250,y+48,'cuts to my liking',{size:22,c:C.mute})).join('')}
${T(120,990,'Share the skills. Keep the knives.',{size:34,w:700,c:C.red})}`);
// 6 rhythm
const ph=[['Mise en place','~10 min','plan checkpoint',C.mustard,300],['Service','slow, methodical','one verified commit per step',C.red,560],['Taste','show and verify','the chef looks',C.sage,300],['The pass','harden','a11y · security · visual',C.ink,320],['Out','chef only','/crew:pr',C.red,200]];
let x6=120,r6='';ph.forEach(([n,a,b,col,w],i)=>{r6+=`<rect x="${x6}" y="420" width="${w-16}" height="150" rx="16" fill="${col}"/>`+T(x6+24,480,n,{size:34,w:700,c:'#fff'})+T(x6+24,525,a,{size:24,c:'#fff',extra:'opacity=".85"'})+T(x6+24,630,b,{size:24,c:C.ink});
 if(n=='Service'){for(let k=0;k<6;k++)r6+=`<circle cx="${x6+60+k*80}" cy="700" r="16" fill="${C.sage}"/><path d="M${x6+52+k*80},700 L${x6+58+k*80},706 L${x6+68+k*80},694" stroke="#fff" stroke-width="3" fill="none"/>`;r6+=T(x6+24,760,'each step: verify, then commit',{size:22,c:C.mute});}
 if(n=='The pass')r6+=T(x6+24,700,'GO / NO-GO',{f:'JetBrains Mono',size:28,w:700,c:C.red});
 x6+=w;});
imgs['06-rhythm']=svg(`${title('The rhythm','Plan briefly. Build slowly. Show. Then harden.')}
${r6}
${card(120,830,1680,120)}${T(160,903,'Requirements early. Verification late.',{size:38,w:700})}${T(960,903,'A11y and security come last: the process can still change.',{size:26,c:C.mute})}`);
// 7 quiet sous chef
const msgs=[['me','Add a newsletter signup.'],['lead','Plan ready. 4 steps, 4 workers. Go?'],['me','Go.'],['lead','Step 1 to backend. Running in the background.'],['lead','Step 1 done: a1f3c9e. Step 2 to unit-tests.'],['me','Make the button text shorter.'],['lead','Noted. Added to step 3, frontend.']];
let m7='';msgs.forEach(([who,s],i)=>{const y=290+i*96;const me=who=='me';const w=s.length*17+70;const x=me?1080-w:200;
 m7+=`<rect x="${x}" y="${y}" width="${w}" height="70" rx="35" fill="${me?C.red:C.card}" stroke="${me?'none':C.line}" stroke-width="2"/>`+T(x+35,y+45,s,{size:28,c:me?'#fff':C.ink});
 if(!me)m7+=T(180,y+45,'lead',{f:'JetBrains Mono',size:20,c:C.mute,a:'end'});});
imgs['07-quiet-sous-chef']=svg(`${title("A sous chef who doesn't talk much",'Direct answers. The work goes to a station on the next tick.')}
${m7}
${T(1260,360,'Background by default',{size:32,w:700})}${T(1260,400,'lead stays free to talk',{size:26,c:C.mute})}
${T(1260,500,'One tick, one handoff',{size:32,w:700})}${T(1260,540,'my word goes to the right station',{size:26,c:C.mute})}
${T(1260,640,'Plain words',{size:32,w:700})}${T(1260,680,'ASD-STE-100 to the operator',{size:26,c:C.mute})}
${T(1260,780,'Nothing leaves by itself',{size:32,w:700})}${T(1260,820,'/crew:pr, and I run it',{size:26,c:C.mute,f:'JetBrains Mono'})}`);
// 8 throw away
imgs['08-throw-away']=svg(`${title('My kitchen. I can change it.','Owning the tool means throwing parts away.')}
${card(140,330,620,180)}${T(180,400,'lane-guard.sh',{f:'JetBrains Mono',size:40,w:700})}${T(180,460,'−250 lines',{f:'JetBrains Mono',size:34,c:C.red,w:700})}
<line x1="160" y1="390" x2="560" y2="390" stroke="${C.red}" stroke-width="3"/>
${card(140,550,620,180)}${T(180,620,'lane-guard.test.sh',{f:'JetBrains Mono',size:40,w:700})}${T(180,680,'−480 lines',{f:'JetBrains Mono',size:34,c:C.red,w:700})}
<line x1="160" y1="610" x2="620" y2="610" stroke="${C.red}" stroke-width="3"/>
<g transform="translate(940,360)"><path d="M0,40 L240,40 L210,380 L30,380 Z" fill="${C.steelD}"/><rect x="-20" y="10" width="280" height="36" rx="8" fill="${C.ink}"/><rect x="90" y="-10" width="60" height="24" rx="6" fill="${C.ink}"/>${[70,120,170].map(x=>`<line x1="${x}" y1="90" x2="${x}" y2="340" stroke="${C.bg}" stroke-width="8" opacity=".5"/>`).join('')}</g>
${arrow(780,520,920,520)}
${T(1300,400,'Open up',{f:'Inter Display',size:64,w:800})}${T(1300,470,'before you lock down',{f:'Inter Display',size:44,w:600})}
${T(1300,580,'Safety fails closed:',{size:30,w:700,c:C.red})}${T(1300,620,'git, secrets, destructive commands.',{size:28})}
${T(1300,700,'Division of labour fails open:',{size:30,w:700,c:C.sage})}${T(1300,740,'the plan holds it, not a guard.',{size:28})}
${T(140,860,'PR #224: 100+ review threads taught me when to stop patching.',{size:30,c:C.mute})}`);

(async()=>{const b=await chromium.launch();const p=await b.newPage({viewport:{width:W,height:H}});
for(const [n,s] of Object.entries(imgs)){fs.writeFileSync(`${OUT}/${n}.svg`,s);await p.setContent(`<html><body style="margin:0">${s}</body></html>`);await p.waitForTimeout(150);await p.screenshot({path:`${OUT}/${n}.png`});}
await b.close();})();
