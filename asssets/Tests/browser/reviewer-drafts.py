#!/usr/bin/env python3
"""Run real offline-gallery Chrome interactions and save its downloaded-JSON payloads for native import tests.
Usage: reviewer-drafts.py index.html output-directory [chrome-executable]
"""
import base64, json, os, pathlib, re, socket, struct, subprocess, sys, tempfile, time, urllib.request

def chrome_result(chrome, url, screenshot=None):
    """Read the page result as soon as its DOM is ready via Chrome DevTools.

    --dump-dom waits for Chrome's virtual-time lifecycle; on macOS headless that
    wait can hang even after the page's JS finishes. DevTools does not wait for
    that lifecycle and checks the actual page result instead.
    """
    with tempfile.TemporaryDirectory(ignore_cleanup_errors=True) as profile:
        args = [chrome, '--headless=new', '--disable-gpu', '--disable-extensions',
                '--no-first-run', '--no-default-browser-check', '--remote-allow-origins=*',
                '--remote-debugging-port=0', f'--user-data-dir={profile}',
                '--allow-file-access-from-files', '--window-size=1024,855', url]
        stderr_log = pathlib.Path(profile) / 'chrome-stderr.txt'
        error_stream = stderr_log.open('wb')
        process = subprocess.Popen(args, stdout=subprocess.DEVNULL, stderr=error_stream)
        sock = None
        try:
            deadline = time.monotonic() + 35
            port_file = pathlib.Path(profile) / 'DevToolsActivePort'
            while not port_file.exists():
                if process.poll() is not None:
                    raise RuntimeError(f'Chrome exited {process.returncode}: {stderr_log.read_text(errors="replace")[-1500:]}')
                if time.monotonic() > deadline: raise TimeoutError('Chrome did not open DevTools')
                time.sleep(.1)
            port = int(port_file.read_text().splitlines()[0])
            target = None
            while not target:
                try:
                    pages = json.load(urllib.request.urlopen(f'http://127.0.0.1:{port}/json/list', timeout=2))
                    target = next((x for x in pages if x.get('type') == 'page' and x.get('url') == url), None)
                except (OSError, ValueError): pass
                if time.monotonic() > deadline: raise TimeoutError('Chrome did not open test page')
                if not target: time.sleep(.1)
            from urllib.parse import urlsplit
            ws = urlsplit(target['webSocketDebuggerUrl'])
            sock = socket.create_connection((ws.hostname, ws.port), timeout=3)
            key = base64.b64encode(os.urandom(16)).decode()
            sock.sendall((f'GET {ws.path} HTTP/1.1\r\nHost: {ws.hostname}:{ws.port}\r\n'
                          f'Upgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Key: {key}\r\n'
                          'Sec-WebSocket-Version: 13\r\nOrigin: http://localhost\r\n\r\n').encode())
            response = b''
            while b'\r\n\r\n' not in response: response += sock.recv(4096)
            if b' 101 ' not in response.split(b'\r\n', 1)[0]: raise RuntimeError(response[:500])
            buffer = response.split(b'\r\n\r\n', 1)[1]
            def receive(n):
                nonlocal buffer
                while len(buffer) < n: buffer += sock.recv(max(4096, n-len(buffer)))
                part, buffer = buffer[:n], buffer[n:]
                return part
            seq = 0
            def cdp(method, params):
                nonlocal seq
                seq += 1
                payload = json.dumps({'id':seq,'method':method,'params':params}).encode()
                mask=os.urandom(4); length=len(payload)
                header=bytes([0x81,0x80|(length if length<126 else 126)])
                if length>=126: header+=struct.pack('!H',length)
                sock.sendall(header+mask+bytes(b^mask[i%4] for i,b in enumerate(payload)))
                while True:
                    first,second=receive(2);length=second&127
                    if length==126:length=struct.unpack('!H',receive(2))[0]
                    elif length==127:length=struct.unpack('!Q',receive(8))[0]
                    mask=receive(4) if second&128 else None;body=receive(length)
                    if mask:body=bytes(b^mask[i%4] for i,b in enumerate(body))
                    if first&15!=1:continue
                    message=json.loads(body)
                    if message.get('id')==seq:
                        if 'error' in message:raise RuntimeError(message['error'])
                        return message.get('result',{})
            while time.monotonic() < deadline:
                try:
                    state=cdp('Runtime.evaluate',{'expression':'JSON.stringify({result:document.getElementById("results")?.textContent||"",action:window.cdpAction||null})','returnByValue':True})
                except RuntimeError as error:
                    if 'Inspected target navigated or closed' not in str(error): raise
                    time.sleep(.1); continue
                state=json.loads(state.get('result',{}).get('value','{}'))
                if state.get('action'):
                    action=state['action'];response=cdp(action['method'],action['params'])
                    if action.get('capture'): pathlib.Path(screenshot).with_name(action['capture']+'.png').write_bytes(base64.b64decode(response['data']))
                    cdp('Runtime.evaluate',{'expression':'window.cdpAction=null;window.cdpResolve()'})
                    continue
                if state.get('result'):
                    result=json.loads(state['result'])
                    if screenshot:
                        data=cdp('Page.captureScreenshot',{'format':'png','captureBeyondViewport':False})
                        pathlib.Path(screenshot).write_bytes(base64.b64decode(data['data']))
                    return result
                time.sleep(.02)
            raise TimeoutError('Review flow did not publish a DOM result')
        finally:
            if sock: sock.close()
            process.terminate()
            try: process.communicate(timeout=4)
            except subprocess.TimeoutExpired:
                process.kill(); process.communicate()
            error_stream.close()

page = pathlib.Path(sys.argv[1]).resolve()
out = pathlib.Path(sys.argv[2]).resolve(); out.mkdir(parents=True, exist_ok=True)
chrome = sys.argv[3] if len(sys.argv) > 3 else 'google-chrome'
original = page.read_text()
# Avoid changing the gallery supplied by a client's export; only a throwaway sibling is written.
manifest = json.loads(re.search(r'<script type="application/json" id="manifest">(.*?)</script>', original, re.S).group(1).replace('<\\/', '</'))
item = manifest['items'][0]['id']
# Use the real gallery HTML, its real storage code, and Chrome's DOM events, not a JS model of the workflow.
# Run a page copy next to the gallery so images and file:// origin are unchanged.
test_page = page.parent / '__reviewer-drafts-test.html'
try:
    for mode in ('drafts', 'legacy-continue', 'legacy-fresh', 'storage-denied', 'storage-quota', 'storage-partial', 'storage-readback', 'storage-warning', 'reload', 'recovery-json', 'recovery-shape', 'recovery-item', 'recovery-active', 'recovery-legacy', 'recovery-failed', 'recovery-warning', 'keyboard-grid', 'keyboard-board', 'keyboard-dialog', 'queue'):
        seed = ''
        mode_original = original
        if mode in ('keyboard-board','queue'):
            # The normal native demo exports a grid-only gallery. Give this
            # throwaway proof page a real local image and one normalized board
            # spot for the same asset; never alter the client export on disk.
            board_manifest = json.loads(json.dumps(manifest))
            board_manifest['board'] = {'image': manifest['items'][0]['image'],
                'spots': [{'id': item, 'x': 0, 'y': 0, 'w': 1, 'h': 1}]}
            board_json = json.dumps(board_manifest).replace('</', '<\\/')
            mode_original = re.sub(r'(<script type="application/json" id="manifest">).*?(</script>)',
                lambda match: match.group(1)+board_json+match.group(2), original, count=1, flags=re.S)

        if mode.startswith('legacy'):
            seed = f'''<script>localStorage.setItem('asssets-review-'+{json.dumps(manifest['gallery'])},JSON.stringify({{reviewer:'Old Name',items:{{{json.dumps(item)}:{{favorite:true,note:'Older note',status:'approved'}}}}}}));</script>'''
        if mode.startswith('recovery-'):
            key = 'asssets-review-'+manifest['gallery']
            valid = {'alex': {'reviewer':'Alex', 'items':{item:{'favorite':True,'note':'Recover original','status':'approved'}}}}
            values = {key+'-drafts-v2':json.dumps(valid),key+'-active-v2':json.dumps('alex')}
            if mode in ('recovery-json','recovery-failed', 'recovery-warning'): values[key+'-drafts-v2']='{broken json: keep exact bytes'
            if mode=='recovery-shape': values[key+'-drafts-v2']=json.dumps({'alex':{'reviewer':42,'items':{}}})
            if mode=='recovery-item': values[key+'-drafts-v2']=json.dumps({'alex':{'reviewer':'Alex','items':{item:{'note':42}}}})
            if mode=='recovery-active': values[key+'-active-v2']=json.dumps('missing')
            if mode=='recovery-legacy': values[key]='[unsupported legacy]'
            seed = '<script>window.expectedRaw='+json.dumps(values)+';if(!sessionStorage.getItem("recovery-stage"))for(const [k,v] of Object.entries(expectedRaw))localStorage.setItem(k,v);</script>'
        if mode.startswith('storage-'):
            failure = mode.split('-')[1]
            if failure == 'warning': failure = 'quota'
            seed = f'''<script>
const originalSet=Storage.prototype.setItem, originalGet=Storage.prototype.getItem;
window.testFailure={json.dumps(failure)};window.failureOn=true;
Storage.prototype.setItem=function(k,v){{
 if(window.failureOn && (window.testFailure==='denied' || window.testFailure==='quota' || k.endsWith('-active-v2'))){{
   if(window.testFailure==='readback')return;
   throw new DOMException(window.testFailure==='quota'?'full':'blocked',window.testFailure==='quota'?'QuotaExceededError':'SecurityError');
 }}return originalSet.call(this,k,v)}};
</script>'''
        flow = r'''<script>
(async()=>{
let results=JSON.parse(sessionStorage.getItem('proof-results')||'[]'), blobs=[];const old=URL.createObjectURL;URL.createObjectURL=b=>{blobs.push(b);return old.call(URL,b)};
const assert=(ok,msg)=>{if(!ok)throw Error(msg);results.push(msg);try{sessionStorage.setItem('proof-results',JSON.stringify(results))}catch(e){}};
window.confirm=()=>true;
const click=id=>document.getElementById(id).click();
const type=(id,v)=>{const x=document.getElementById(id);x.value=v;x.dispatchEvent(new Event('input',{bubbles:true}))};
const download=async()=>{click('download');assert(blobs.length>0,'download button created a Blob');return JSON.parse(await blobs.pop().text())};
try{
if(MODE==='queue'){
 const action=(method,params,capture)=>new Promise(resolve=>{window.cdpResolve=resolve;window.cdpAction={method,params,capture}});
 const shot=name=>action('Page.captureScreenshot',{format:'png',captureBeyondViewport:false},name);
 const key=async(k,code,v=0)=>{await action('Input.dispatchKeyEvent',{type:'keyDown',key:k,code,text:k==='Enter'?'\r':'',windowsVirtualKeyCode:v});await action('Input.dispatchKeyEvent',{type:'keyUp',key:k,code,windowsVirtualKeyCode:v})};
 const to=async predicate=>{for(let i=0;i<100&&!predicate(document.activeElement);i++)await key('Tab','Tab',9);assert(predicate(document.activeElement),'Tab reaches queue control')};
 const select=(v)=>{const x=document.getElementById('queueDecision');x.value=v;x.dispatchEvent(new Event('change',{bubbles:true}))};
 const rawDownload=async()=>{click('download');return await blobs.pop().text()};
 const ids=()=>[...document.querySelectorAll('#grid .thumb')].map(e=>e.dataset.reviewId);
 type('newReviewer','Queue Reviewer');document.querySelector('#reviewModalActions .primary').click();
 assert(M.items.length>=3,'queue proof requires at least three real exported assets');
 for(let i=0;i<3;i++){
  document.querySelectorAll('#grid .thumb')[i].click();click(i===1?'lbch':'lbap');if(i!==1)click('lbpick');type('lbnote','Queue note '+i);click('close');
 }
 const before=await rawDownload();
 select('approved');assert(ids().length===2&&ids()[0]===M.items[0].id&&ids()[1]===M.items[2].id,'Approved queue excludes Changes asset');
 assert(document.getElementById('queueCount').textContent.startsWith('2 of '),'visible match count is exact');
 await shot('queue-filtered');
 assert(!document.getElementById('board').classList.contains('on'),'board hidden while filtering');
 await to(e=>e.classList.contains('thumb'));await key('Enter','Enter',13);
 assert(cur===0,'filtered queue begins at first match');await key('ArrowLeft','ArrowLeft',37);assert(cur===2,'Prev at first wraps only to last match');
 await key('ArrowRight','ArrowRight',39);assert(cur===0,'Next at last wraps only to first match');await key('ArrowRight','ArrowRight',39);assert(cur===2,'Next skips filtered-out middle asset');
 await key('ArrowLeft','ArrowLeft',37);assert(cur===0,'Prev skips filtered-out middle asset');await key('Escape','Escape',27);
 const filtered=await rawDownload();assert(before===filtered,'full feedback download byte-identical with active filter');
 const decoded=JSON.parse(filtered);assert(decoded.items.length===3,'download includes hidden Changes feedback');
 type('queueSearch','__no_such_asset__');assert(ids().length===0&&!document.getElementById('queueEmpty').hidden,'zero-match queue has real empty state');
 open(0);assert(cur===-1&&!document.getElementById('lb').classList.contains('open'),'zero-match queue cannot open lightbox');await shot('queue-empty');
 click('queueEmptyReset');assert(ids().length===M.items.length,'empty state resets to full gallery');
 select('changes');assert(ids().length===1&&ids()[0]===M.items[1].id,'Changes filter exact');
 select('undecided');assert(ids().length===M.items.length-3,'No decision excludes all decided assets');
 select('approved');click('onlyPicks');assert(ids().length===2,'favorite and decision filters combine');
 click('switchReviewer');type('newReviewer','New Queue Reviewer');document.querySelector('#reviewModalActions .primary').click();
 assert(ids().length===0&&!document.getElementById('queueEmpty').hidden,'active filter evaluates new reviewer without leaking previous matches');
 const fresh=JSON.parse(await rawDownload());assert(fresh.reviewer==='New Queue Reviewer'&&fresh.items.length===0,'new reviewer download has no old state');
 click('switchReviewer');document.getElementById('knownReviewers').value='Queue Reviewer';document.querySelector('#reviewModalActions .primary').click();
 assert(ids().length===2,'switch back restores only original reviewer matches');click('queueReset');
 type('queueSearch',M.items[0].title);assert(ids().includes(M.items[0].id),'search finds title');click('queueReset');
 if(M.items[0].tags.length){type('queueSearch',M.items[0].tags[0]);assert(ids().includes(M.items[0].id),'search finds tags');click('queueReset')}
 const after=await rawDownload();assert(before===after,'filter reset leaves feedback byte-identical');
 await shot('queue-reset');
 // A decision edit may remove the open card from the visible queue. Keep
 // its note editable, then navigation must leave it or show the empty state.
 select('changes');document.querySelector('#grid .thumb').click();click('lbap');
 assert(cur===1,'editing current decision keeps the open note available');click('next');
 assert(cur===-1&&!document.getElementById('queueEmpty').hidden,'navigation closes lightbox when current edit empties queue');
 click('queueReset');document.querySelectorAll('#grid .thumb')[1].click();click('lbch');click('close');
 assert(before===await rawDownload(),'queue-edit round trip restores exact feedback');
 document.getElementById('results').textContent=JSON.stringify({results,downloads:[decoded,fresh]});
}else if(MODE.startsWith('keyboard-')){
 const action=(method,params,capture)=>new Promise(resolve=>{window.cdpResolve=resolve;window.cdpAction={method,params,capture}});
 const shot=name=>action('Page.captureScreenshot',{format:'png',captureBeyondViewport:false},name);
 const key=async(k,code,modifiers=0)=>{await action('Input.dispatchKeyEvent',{type:'keyDown',key:k,code,text:k==='Enter'?'\r':'',windowsVirtualKeyCode:k==='Tab'?9:k==='Enter'?13:k==='Escape'?27:0,modifiers});await action('Input.dispatchKeyEvent',{type:'keyUp',key:k,code,modifiers})};
 const tab=()=>key('Tab','Tab'),enter=()=>key('Enter','Enter'),esc=()=>key('Escape','Escape');
 const to=async predicate=>{for(let i=0;i<90&&!predicate(document.activeElement);i++)await tab();assert(predicate(document.activeElement),'Tab reached requested control')};
 assert(document.activeElement.id==='knownReviewers','opening dialog focuses saved drafts');await shot(MODE+'-open');
 await key('Tab','Tab',8);assert(document.activeElement.textContent==='Switch','Shift Tab trapped at dialog end');
 await tab();assert(document.activeElement.id==='knownReviewers','Tab trapped at dialog start');
 await tab();assert(document.activeElement.id==='newReviewer','Tab focuses new reviewer');
 await action('Input.insertText',{text:'Recovered Reviewer With A Much Longer Full Name That Wraps Onto Two Lines'});
 await tab();await enter();assert(document.getElementById('reviewer').textContent==='Recovered Reviewer With A Much Longer Full Name That Wraps Onto Two Lines','full reviewer name shown');
 if(MODE==='keyboard-dialog'){
  await to(e=>e.id==='renameReviewer');await enter();assert(document.activeElement.id==='renameInput','rename dialog receives focus');
  await esc();assert(document.activeElement.id==='renameReviewer','Escape restores invoking rename control');await shot(MODE+'-return');
  await enter();assert(document.activeElement.id==='renameInput','rename reopened with focus');
  document.getElementById('results').textContent=JSON.stringify({results,downloads:[]});
 }else{
  const board=MODE==='keyboard-board';
  if(board){
   const spot=document.querySelector('.spot'),image=document.querySelector('#bwrap img');
   assert(spot&&spot.dataset.reviewId===M.items[0].id,'board fixture contains matching asset spot');
   await image.decode();assert(image.naturalWidth>0&&image.naturalHeight>0&&spot.getBoundingClientRect().width>0&&spot.getBoundingClientRect().height>0,'board fixture image loaded and spot has visible bounds');
  }
  await to(e=>e.classList.contains(board?'spot':'thumb'));const id=document.activeElement.dataset.reviewId;
  await enter();assert(document.activeElement.id==='close','lightbox opening visibly focuses close');await shot(MODE+'-lightbox');
  await key('Tab','Tab',8);assert(document.activeElement.id==='next','Shift Tab trapped in lightbox');await tab();assert(document.activeElement.id==='close','Tab trapped in lightbox');
  await key('f','KeyF');await key('a','KeyA');
  await to(e=>e.id==='lbnote');await action('Input.insertText',{text:'Keyboard note with a c and f preserved'});
  await esc();assert(document.activeElement.dataset.reviewId===id&&document.activeElement.classList.contains(board?'spot':'thumb'),'lightbox Escape returns to invoking review target');await shot(MODE+'-return');
  await to(e=>e.id==='download');await enter();const d=JSON.parse(await blobs.pop().text());
  assert(d.items[0].favorite&&d.items[0].status==='approved'&&d.items[0].note==='Keyboard note with a c and f preserved','keyboard download contains exact picks decisions notes');
  document.getElementById('results').textContent=JSON.stringify({results,downloads:[d]});
 }
}else if(MODE.startsWith('recovery-')&&sessionStorage.getItem('recovery-stage')==='fresh'){
 assert(document.getElementById('reviewer').textContent==='Recovered Reviewer','new reviewer survives reload after recovery');
 const d=await download();assert(d.items[0].note==='New draft after recovery','new feedback survives reload after recovery');
 document.getElementById('results').textContent=JSON.stringify({results,downloads:[d]});
}else if(MODE.startsWith('recovery-')){
 const unchanged=()=>Object.entries(expectedRaw).every(([k,v])=>localStorage.getItem(k)===v);
 assert(document.getElementById('reviewModalTitle').textContent==='Stored drafts need recovery','recovery blocks startup');
 assert(unchanged(),'original raw bytes untouched on startup');
 assert(document.querySelector('#reviewModalActions .primary')===null,'replacement requires recovery download');
 assert(!put()&&unchanged(),'automatic save cannot overwrite unreadable storage');
 document.querySelector('#reviewModalActions button').click();
 const recovery=JSON.parse(await blobs.pop().text());
 assert(recovery.format==='asssets-review-storage-recovery'&&Object.entries(expectedRaw).every(([k,v])=>recovery.stored[k]===v),'recovery download contains exact original bytes');
 assert(unchanged(),'recovery download leaves storage unchanged');
 if(MODE==='recovery-warning'){document.getElementById('results').textContent=JSON.stringify({results,downloads:[],recovery});
 }else if(MODE==='recovery-failed'){
  const set=Storage.prototype.setItem;Storage.prototype.setItem=function(){throw new DOMException('blocked','SecurityError')};
  document.querySelector('#reviewModalActions .primary').click();
  assert(unchanged()&&document.getElementById('reviewModalTitle').textContent==='Stored drafts need recovery','failed fresh start stays blocked without data loss');
  Storage.prototype.setItem=set;
  document.getElementById('results').textContent=JSON.stringify({results,downloads:[],recovery});
 }else if(!sessionStorage.getItem('recovery-stage')){
  sessionStorage.setItem('recovery-stage','downloaded');
  // A second navigation must still detect the same stored bytes, not quietly clear them.
  location.reload();
 }else{
  assert(unchanged(),'reload preserves unresolved original storage');
  window.confirm=()=>false;document.querySelector('#reviewModalActions .primary').click();assert(unchanged(),'declined replacement keeps original bytes');window.confirm=()=>true;
  document.querySelector('#reviewModalActions .primary').click();
  assert(document.getElementById('reviewModalTitle').textContent==='Switch reviewer','explicit fresh start enables new draft');
  type('newReviewer','Recovered Reviewer');document.querySelector('#reviewModalActions .primary').click();
  document.querySelector('.heart').click();document.querySelector('.st .ap').click();document.querySelector('.thumb').click();type('lbnote','New draft after recovery');click('close');
  const d=await download();assert(d.reviewer==='Recovered Reviewer'&&d.items[0].note==='New draft after recovery','fresh feedback excludes unreadable stored contents');
  assert(JSON.parse(localStorage.getItem(DKEY))['recovered reviewer'].items[d.items[0].id].note==='New draft after recovery','new draft read back after recovery');
  sessionStorage.setItem('recovery-stage','fresh');location.reload();
 }
}else if(MODE==='drafts'){
 assert(document.getElementById('reviewModalTitle').textContent==='Switch reviewer','new gallery asks reviewer');
 type('newReviewer','Alex');document.querySelector('#reviewModalActions .primary').click();
 document.querySelector('.heart').click();document.querySelector('.st .ap').click();
 document.querySelector('.thumb').click();type('lbnote','Alex note');click('close');
 let a=await download();assert(a.reviewer==='Alex'&&a.items[0].favorite&&a.items[0].status==='approved'&&a.items[0].note==='Alex note','Alex download has Alex decisions');
 click('switchReviewer');type('newReviewer','Sam');document.querySelector('#reviewModalActions .primary').click();
 assert(!document.querySelector('.card').classList.contains('picked'),'new reviewer sees empty picks');
 document.querySelector('.st .ch').click();document.querySelector('.thumb').click();type('lbnote','Sam note');click('close');
 let b=await download();assert(b.reviewer==='Sam'&&b.items[0].note==='Sam note'&&b.items[0].status==='changes'&&!b.items[0].favorite,'Sam download excludes Alex decisions');
 click('switchReviewer');document.getElementById('knownReviewers').value='Alex';document.querySelector('#reviewModalActions .primary').click();
 assert(document.querySelector('.card').classList.contains('picked'),'switch restores Alex');
 document.getElementById('knownReviewers').value='';
 click('renameReviewer');type('renameInput','Alex Updated');document.querySelector('#reviewModalActions .primary').click();
 let c=await download();assert(c.reviewer==='Alex Updated'&&c.items[0].note==='Alex note','rename keeps Alex contents');
 click('switchReviewer');document.getElementById('knownReviewers').value='Sam';document.querySelector('#reviewModalActions .primary').click();
 let d=await download();assert(d.reviewer==='Sam'&&d.items[0].note==='Sam note','switch back restores Sam');
 click('switchReviewer');document.getElementById('knownReviewers').value='Alex Updated';document.querySelector('#reviewModalActions .primary').click();
 let e=await download();assert(e.reviewer==='Alex Updated'&&e.items[0].note==='Alex note','switch back restores renamed Alex');
 document.getElementById('results').textContent=JSON.stringify({results,downloads:[a,b,c,d,e],storage:JSON.parse(localStorage.getItem(DKEY))});
 }else if(MODE.startsWith('storage-')){
 assert(document.getElementById('reviewModalTitle').textContent==='Switch reviewer','initial draft choice displayed');
 type('newReviewer','Failed Draft');document.querySelector('#reviewModalActions .primary').click();
 document.querySelector('.heart').click();document.querySelector('.st .ap').click();
 document.querySelector('.thumb').click();type('lbnote','Keep this note');click('close');
 assert(document.getElementById('saveState').classList.contains('on'),'unsaved warning visible');
 click('switchReviewer');assert(document.getElementById('reviewModalTitle').textContent==='Draft not saved','unsafe switch blocked');
 assert(document.querySelector('#reviewModalActions .primary')===null,'no switch action offered');
 document.querySelector('#reviewModalActions button:last-child').click();
 const d=JSON.parse(await blobs.pop().text());assert(d.reviewer==='Failed Draft'&&d.items[0].note==='Keep this note'&&d.items[0].status==='approved'&&d.items[0].favorite,'download keeps unsaved draft');
 assert(document.getElementById('saveState').classList.contains('on'),'download does not falsely claim saved');
 if(MODE==='storage-partial')assert(localStorage.getItem(DKEY)===null && localStorage.getItem(ACTIVE)===null,'partial write rolled back');
 if(MODE==='storage-warning')assert(!document.getElementById('reviewModal').classList.contains('open'),'dialog closed after download');
 else {click('switchReviewer');assert(document.getElementById('reviewModalTitle').textContent==='Draft not saved','blocked dialog stays available')};
 document.getElementById('results').textContent=JSON.stringify({results,downloads:[d]});
 }else if(MODE==='reload'){
 if(sessionStorage.getItem('reload-stage')){
  assert(document.getElementById('reviewer').textContent==='Reloaded Draft','reviewer survived reload');
  assert(document.querySelector('.card').classList.contains('picked'),'pick survived reload');
  const d=await download();assert(d.items[0].note==='Saved before reload','note survived reload');
  document.getElementById('results').textContent=JSON.stringify({results,downloads:[d]});
 }else{
  type('newReviewer','Reloaded Draft');document.querySelector('#reviewModalActions .primary').click();
  document.querySelector('.heart').click();document.querySelector('.thumb').click();type('lbnote','Saved before reload');click('close');
  assert(!document.getElementById('saveState').classList.contains('on'),'both keys read back as saved');
  sessionStorage.setItem('reload-stage','1');location.reload();
 }
}else{
 assert(document.getElementById('reviewModalTitle').textContent==='Earlier draft found','legacy choice shown');
 if(MODE==='legacy-continue'){
  type('legacyInput','Renamed Legacy');document.querySelector('#reviewModalActions button').click();
  let d=await download();assert(d.reviewer==='Renamed Legacy'&&d.items[0].note==='Older note','continued legacy preserved');
  document.getElementById('results').textContent=JSON.stringify({results,downloads:[d]});
 }else{
  document.querySelector('#reviewModalActions .primary').click();
  type('newReviewer','New Person');document.querySelector('#reviewModalActions .primary').click();
  let d=await download();assert(d.reviewer==='New Person'&&d.items.length===0,'fresh does not inherit legacy');
  assert(localStorage.getItem(KEY).includes('Older note'),'fresh does not delete legacy');
  document.getElementById('results').textContent=JSON.stringify({results,downloads:[d]});
 }
}
}catch(e){document.getElementById('results').textContent=JSON.stringify({error:String(e),stack:e.stack,results})}
})();
</script>'''.replace('MODE', json.dumps(mode))
        # Seed older storage before gallery script starts. Result node is after gallery initialization.
        html = mode_original.replace('<script>\nconst M=', seed+'<script>\nconst M=',1).replace('</body>', '<pre id="results" hidden></pre>'+flow+'</body>')
        test_page.write_text(html)
        result = chrome_result(chrome, test_page.as_uri(), out / f'{mode}.png' if mode.startswith(('storage-', 'recovery-', 'keyboard-', 'queue')) else None)
        if 'error' in result: raise RuntimeError(f'{mode}: {result}')
        for i, download in enumerate(result['downloads']):
            (out / f'{mode}-{i}.json').write_text(json.dumps(download,indent=2)+'\n')
        if 'recovery' in result: (out / f'{mode}-raw.json').write_text(json.dumps(result['recovery'],indent=2)+'\n')
        print(mode, ', '.join(result['results']))
    (out / 'manifest.json').write_text(json.dumps(manifest,indent=2)+'\n')
finally:
    test_page.unlink(missing_ok=True)
