import {chromium} from 'playwright';
import {createServer} from 'node:http';
import {readFile} from 'node:fs/promises';
import {resolve, extname, sep} from 'node:path';
const root = resolve('build/web');
const mime = {'.html':'text/html','.js':'text/javascript','.mjs':'text/javascript','.wasm':'application/wasm','.json':'application/json'};
const server = createServer(async (req,res) => {
  const path = resolve(root, '.' + new URL(req.url,'http://localhost').pathname);
  if (!path.startsWith(root + sep) && path !== root) {res.writeHead(403).end();return;}
  try { const target=path === root ? resolve(root,'index.html') : path; const bytes = await readFile(target); res.writeHead(200,{'Content-Type':mime[extname(target)] || 'application/octet-stream'});res.end(bytes); }
  catch {res.writeHead(404).end();}
});
await new Promise(r=>server.listen(0,'127.0.0.1',r));
const origin = `http://127.0.0.1:${server.address().port}`;
const browser = await chromium.launch();
try {
  const page = await browser.newPage();
  const failures=[];
  page.on('pageerror',e=>failures.push(e.message));
  await page.route('**/*', route => route.request().url().startsWith(origin) ? route.continue() : route.abort());
  await page.goto(origin);
  await page.waitForFunction(()=>globalThis.pdfjsLib && document.querySelector('flutter-view'),{timeout:60000});
  await page.evaluate(async () => {
    const text='%PDF-1.4\n1 0 obj <</Type /Catalog /Pages 2 0 R>> endobj\n2 0 obj <</Type /Pages /Kids [3 0 R] /Count 1>> endobj\n3 0 obj <</Type /Page /Parent 2 0 R /MediaBox [0 0 100 100] /Contents 4 0 R>> endobj\n4 0 obj <</Length 0>> stream\n\nendstream endobj\ntrailer <</Root 1 0 R>>\n%%EOF';
    const task=pdfjsLib.getDocument({data:new TextEncoder().encode(text)});
    const pdf=await task.promise;
    if(pdf.numPages!==1) throw Error('Missing PDF page');
    const page=await pdf.getPage(1), viewport=page.getViewport({scale:1});
    const canvas=document.createElement('canvas'); canvas.width=100;canvas.height=100;
    await page.render({canvasContext:canvas.getContext('2d'),viewport}).promise;
    await pdf.destroy();
  });
  await page.evaluate(async () => {
    const db=await new Promise((resolve,reject)=>{
      const request=indexedDB.open('osipp-critical-v2',2);
      request.onsuccess=()=>resolve(request.result);request.onerror=()=>reject(request.error);
    });
    if(!db.objectStoreNames.contains('data')) throw Error('Missing durable app archive');
    const read=key=>new Promise((resolve,reject)=>{
      const request=db.transaction('data','readonly').objectStore('data').get(key);
      request.onsuccess=()=>resolve(request.result);request.onerror=()=>reject(request.error);
    });
    const state=JSON.parse(await read('state'));
    if(!Array.isArray(state.recentFiles)) throw Error('Library migration did not commit in IndexedDB');
    await new Promise((resolve,reject)=>{
      const tx=db.transaction('data','readwrite');
      tx.oncomplete=resolve;tx.onabort=()=>reject(tx.error);
      tx.objectStore('data').put(new Uint8Array([1,2,3]),'smoke-blob');
    });
    db.close();
  });
  await page.reload();
  await page.waitForFunction(()=>document.querySelector('flutter-view'),{timeout:60000});
  await page.evaluate(async()=>{
    const db=await new Promise((resolve,reject)=>{const r=indexedDB.open('osipp-critical-v2',2);r.onsuccess=()=>resolve(r.result);r.onerror=()=>reject(r.error);});
    const bytes=await new Promise((resolve,reject)=>{const r=db.transaction('data','readonly').objectStore('data').get('smoke-blob');r.onsuccess=()=>resolve(r.result);r.onerror=()=>reject(r.error);});
    if(!(bytes instanceof Uint8Array) || bytes.join(',')!=='1,2,3')throw Error('Durable binary archive failed after reload');
    db.close();
  });
  if(failures.length) throw Error(failures.join('\n'));
  // Simulate another tab holding the previous schema open during app startup.
  const blockedContext = await browser.newContext();
  try {
    await blockedContext.route('**/*', route => route.request().url().startsWith(origin) ? route.continue() : route.abort());
    const holder = await blockedContext.newPage();
    await holder.goto(origin + '/smoke-blank');
    await holder.evaluate(async () => {
      globalThis.heldDatabase = await new Promise((resolve,reject) => {
        const request = indexedDB.open('osipp-critical-v2',1);
        request.onsuccess = () => resolve(request.result);
        request.onerror = () => reject(request.error);
      });
      heldDatabase.onversionchange = () => { globalThis.upgradeRequested = true; };
    });
    const blockedPage = await blockedContext.newPage();
    blockedPage.on('pageerror', e => failures.push(e.message));
    blockedPage.on('console', message => {
      if (message.type() === 'error' && /Future already completed/i.test(message.text())) failures.push(message.text());
    });
    await blockedPage.goto(origin);
    await holder.waitForFunction(() => globalThis.upgradeRequested, null, {timeout:60000});
    await blockedPage.waitForFunction(() => document.querySelector('flutter-view'), null, {timeout:60000});
    await holder.evaluate(() => heldDatabase.close());
    // Await the previously blocked upgrade, then retry the app's library read.
    await blockedPage.evaluate(async () => {
      await new Promise((resolve,reject) => {
        const request = indexedDB.open('osipp-critical-v2',2);
        request.onsuccess = () => { request.result.close(); resolve(); };
        request.onerror = () => reject(request.error);
      });
    });
    await blockedPage.reload();
    await blockedPage.waitForFunction(() => document.querySelector('flutter-view'), null, {timeout:60000});
    await blockedPage.waitForFunction(async () => {
      const db = await new Promise((resolve,reject) => {
        const request = indexedDB.open('osipp-critical-v2',2);
        request.onsuccess = () => resolve(request.result);
        request.onerror = () => reject(request.error);
      });
      try {
        return await new Promise((resolve,reject) => {
          const request = db.transaction('data','readonly').objectStore('data').get('state');
          request.onsuccess = () => resolve(typeof request.result === 'string' && Array.isArray(JSON.parse(request.result).recentFiles));
          request.onerror = () => reject(request.error);
        });
      } finally { db.close(); }
    }, null, {timeout:60000});
    if(failures.length) throw Error(failures.join('\n'));
  } finally { await blockedContext.close(); }
  console.log('Built app starts, renders a PDF, restores IndexedDB state/binary data after reload, and handles a blocked schema upgrade without external resources');
} finally {await browser.close();await new Promise(r=>server.close(r));}
