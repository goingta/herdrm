// Controlled external API boundary for the unmodified reference frontend build.
// Usage: node reference-capture.mjs /path/to/reference /path/to/output
import http from 'node:http';
import crypto from 'node:crypto';
import fs from 'node:fs';
import path from 'node:path';
import { createRequire } from 'node:module';
const [reference, output] = process.argv.slice(2);
if (!reference || !output) throw Error('Provide reference checkout and isolated output directory');
const require = createRequire(path.join(reference, 'package.json'));
const { chromium } = require('playwright-core');
const scene = JSON.parse(fs.readFileSync(new URL('./scene.json', import.meta.url)));
const snapshot = structuredClone(scene.snapshot);
snapshot.protocol = 22; snapshot.version = '0.9.1'; snapshot.layouts = [];
snapshot.focused_tab_id = 'read-tab';
snapshot.panes = [...snapshot.panes, ...snapshot.agents].map(p => ({ ...p, label: p.name ?? p.terminal_title, terminal_id: p.terminal_id ?? `terminal-${p.pane_id}`, focused: p.pane_id === 'done-read', revision: 1, agent_status: p.agent_status ?? 'idle' }));
snapshot.tabs = snapshot.tabs.map(t => ({ ...t, focused: t.tab_id === 'read-tab', pane_count: snapshot.panes.filter(p => p.tab_id === t.tab_id).length, agent_status: 'done' }));
snapshot.workspaces = snapshot.workspaces.map(w => ({ ...w, focused: w.workspace_id === 'visual-workspace', pane_count: snapshot.panes.filter(p => p.workspace_id === w.workspace_id).length, tab_count: snapshot.tabs.filter(t => t.workspace_id === w.workspace_id).length, agent_status: 'done' }));
const machine = { id:'local', name:scene.deviceName, kind:'local', enabled:true, state:'connected', error:null, snapshot, herdr:{version:'0.9.1',protocol:22,terminal_attach:true} };
const health = {ok:true,auth:{required:false,authenticated:true,via:'none'},herdr:machine.herdr,bridge_protocol:1,web_ui:{revision:'controlled-reference',boot_id:'fixture'}};
const types = { '.html':'text/html', '.js':'text/javascript', '.css':'text/css', '.woff2':'font/woff2', '.svg':'image/svg+xml', '.png':'image/png', '.ico':'image/x-icon', '.webmanifest':'application/manifest+json' };
const server = http.createServer((req,res) => {
 const pathname = new URL(req.url,'http://localhost').pathname;
 if (pathname === '/api/machines/events') { res.writeHead(200,{'Content-Type':'text/event-stream'});res.write(`data: ${JSON.stringify({type:'machines',machines:[machine]})}\n\n`);return; }
 if (pathname.startsWith('/api/')) {
  let body; let status=200;
  if (pathname.endsWith('/health')) body=health;
  else if (pathname === '/api/machines') body={machines:[machine]};
  else if (pathname.endsWith('/session')) body={snapshot};
  else if (pathname.endsWith('/pane/conversation')) body=scene.conversation;
  else if (pathname.endsWith('/pane/prompt')) body={prompt:null,suggestion:null};
  else if (pathname.endsWith('/pane/read')) body={read:{text:scene.terminal}};
  else if (pathname === '/api/updates') body={available:false,current:'0.4.5',latest:'0.4.5',state:'idle'};
  else if (pathname === '/api/push') body={enabled:false,key:null};
  else { status=404;body={error:{code:'not_found',message:'Controlled fixture endpoint unavailable'}}; }
  res.writeHead(status,{'Content-Type':'application/json','ETag':'"visual-v1"'});res.end(JSON.stringify(body));return;
 }
 let file = path.join(reference,'dist',pathname === '/' ? 'index.html' : pathname);
 if (!file.startsWith(path.join(reference,'dist')) || !fs.existsSync(file)) {res.writeHead(404);res.end();return;}
 res.writeHead(200,{'Content-Type':types[path.extname(file)] ?? 'application/octet-stream'});fs.createReadStream(file).pipe(res);
});
function frame(value) { const data=Buffer.from(JSON.stringify(value)); const header=Buffer.alloc(data.length<126?2:4);header[0]=129;header[1]=data.length<126?data.length:126;if(data.length>=126)header.writeUInt16BE(data.length,2);return Buffer.concat([header,data]); }
server.on('upgrade',(req,socket)=>{
 const accept=crypto.createHash('sha1').update(req.headers['sec-websocket-key']+'258EAFA5-E914-47DA-95CA-C5AB0DC85B11').digest('base64');
 socket.write(`HTTP/1.1 101 Switching Protocols\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Accept: ${accept}\r\n\r\n`);
 socket.write(frame({type:'snapshot',snapshot}));socket.write(frame({type:'role-ack',mode:'interact'}));
 socket.on('error',()=>{}); socket.on('data',()=>{});
});
await new Promise(resolve=>server.listen(0,'127.0.0.1',resolve));
fs.mkdirSync(output,{recursive:true});
const browser = await chromium.launch({executablePath:'/Applications/Google Chrome.app/Contents/MacOS/Google Chrome',headless:true});
try {
 for (const language of ['en','zh']) for (const theme of ['light','dark']) {
  const context=await browser.newContext({viewport:{width:390,height:750},deviceScaleFactor:3,isMobile:true,hasTouch:true,locale:language==='zh'?'zh-CN':'en-US'});
  await context.addInitScript(({language,theme})=>{localStorage.setItem('herdr-web-ui:settings',JSON.stringify({language,theme,defaultView:'chat'}));localStorage.setItem('herdr-web-ui:view:done-read','chat');},{language,theme});
  const page=await context.newPage();const errors=[];page.on('pageerror',e=>errors.push(e.message));
  await page.goto(`http://127.0.0.1:${server.address().port}/?pane=done-read&machine=local`);
  await page.getByRole('heading',{name:'SAME_CHAT_FIXTURE_RESULT'}).waitFor({timeout:15000});
  await page.screenshot({path:path.join(output,`reference-${language}-${theme}-chat.png`)});
  fs.writeFileSync(path.join(output,`reference-${language}-${theme}-dom.txt`),await page.locator('body').innerText());
  const toggle=page.getByRole('button',{name:language==='zh'?'打开工作区列表':'Open workspace list',exact:true});
  if (await toggle.count()) { await toggle.click();await page.waitForFunction(()=>document.querySelector('#workspace-drawer')?.getBoundingClientRect().x >= -1);await page.screenshot({path:path.join(output,`reference-${language}-${theme}-sidebar.png`)}); }
  fs.writeFileSync(path.join(output,`reference-${language}-${theme}-errors.json`),JSON.stringify(errors));
  await context.close();
 }
} finally {await browser.close();server.closeAllConnections();server.close();}
