// Optional host UI smoke check. Requires Node 22+ and Chromium; no live game imports.
import {spawn} from 'node:child_process';
import {writeFileSync,readFileSync,mkdtempSync,rmSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {join,dirname,resolve} from 'node:path';
import {fileURLToPath} from 'node:url';
const root=resolve(dirname(fileURLToPath(import.meta.url)),'..');
const profile=mkdtempSync(join(tmpdir(),'cc-concept-chromium-'));
const port=Number(process.argv[2]||9234);
import {setTimeout as delay} from 'node:timers/promises';
const browser=spawn('/usr/bin/chromium',['--headless','--no-sandbox','--disable-dev-shm-usage','--remote-debugging-port='+port,'--user-data-dir='+profile,'--window-size=1360,1000','about:blank'],{stdio:'ignore'});
let socket;
try {
 let pages;
 for(let i=0;i<40;i++){try{pages=await(await fetch('http://127.0.0.1:'+port+'/json/list')).json();if(pages.some(p=>p.type==='page'&&p.url==='about:blank'))break;}catch{}await delay(150);}
 const page=pages.find(p=>p.type==='page'&&p.url==='about:blank');if(!page)throw Error(JSON.stringify(pages));socket=new WebSocket(page.webSocketDebuggerUrl);
 await new Promise((r,j)=>{socket.onopen=r;socket.onerror=j;});
 let counter=0;const pending=new Map();socket.onmessage=e=>{const d=JSON.parse(e.data);if(pending.has(d.id)){pending.get(d.id)(d);pending.delete(d.id);}};
 const send=(method,params={})=>new Promise(r=>{const id=++counter;pending.set(id,r);socket.send(JSON.stringify({id,method,params}));});
 await send('Runtime.enable');const tree=await send('Page.getFrameTree');await send('Page.setDocumentContent',{frameId:tree.result.frameTree.frame.id,html:readFileSync(join(root,'previews/review.html'),'utf8')});await delay(700);
 const r=await send('Runtime.evaluate',{awaitPromise:true,returnByValue:true,expression:`(async()=>{
  const assert=(ok,msg)=>{if(!ok)throw Error(msg)};
  const wait=()=>new Promise(r=>setTimeout(r,150));
  const articles=[...document.querySelectorAll('article')];assert(articles.length===3,'Missing concept card');
  const firstSelect=articles[0].querySelector('select');firstSelect.value='movement';firstSelect.dispatchEvent(new Event('change'));await wait();const movingSource=articles[0].querySelector('img').src;await new Promise(r=>setTimeout(r,300));assert(articles[0].querySelector('img').src!==movingSource,'Animation did not advance');
  document.querySelector('#play').click();assert(document.querySelector('#play').textContent==='Abspielen','Pause failed');
  const details=[];
  for(const a of articles){const select=a.querySelector('select');assert(select.options.length===6,'Missing actions');select.value='attack_fx';select.dispatchEvent(new Event('change'));await wait();const slider=a.querySelector('input');const old=a.querySelector('img').src;slider.value=2;slider.dispatchEvent(new Event('input'));await wait();const img=a.querySelector('img');assert(img.complete&&img.naturalWidth>0,'Image not decoded');assert(img.src!==old,'Frame slider failed');assert(parseFloat(img.style.width)===img.naturalWidth*6,'Non-integer sprite scale');details.push({name:a.querySelector('h2').textContent,actions:select.options.length,frame:a.querySelector('small').textContent,nativeWidth:img.naturalWidth,scale:6});}
  document.querySelector('#reset').click();assert(articles.every(a=>a.querySelector('input').value==='0'),'Restart failed');
  const s=articles[0].querySelector('select');s.value='death';s.dispatchEvent(new Event('change'));const slider=articles[0].querySelector('input');slider.value=slider.max;slider.dispatchEvent(new Event('input'));await wait();assert(articles[0].querySelector('small').textContent.startsWith('removed'),'Death did not end in removal');
  document.querySelector('#speed').value='0.5';document.querySelector('#speed').dispatchEvent(new Event('input'));assert(document.querySelector('#speedvalue').textContent==='0.5×','Speed control failed');
  return {status:'PASS',browser:'Chromium headless',loadMode:'Exact standalone HTML via Page.setDocumentContent',checks:['three cards','six selectable actions per card','automatic animation advance','pause','frame scrub','image decoding','integer 6x scaling','restart','death removal','speed'],cards:details};})()`});
 if(r.result.exceptionDetails)throw Error(JSON.stringify(r.result.exceptionDetails));
 const result=r.result.result.value;console.log(JSON.stringify(result));writeFileSync(join(root,'evidence/browser_check.json'),JSON.stringify(result,null,2)+'\n');

} finally {socket?.close();browser.kill('SIGTERM');await delay(300);rmSync(profile,{recursive:true,force:true});}
