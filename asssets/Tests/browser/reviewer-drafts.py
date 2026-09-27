#!/usr/bin/env python3
"""Run real offline-gallery Chrome interactions and save its downloaded-JSON payloads for native import tests.
Usage: reviewer-drafts.py index.html output-directory [chrome-executable]
"""
import json, pathlib, re, subprocess, sys, tempfile

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
    for mode in ('drafts', 'legacy-continue', 'legacy-fresh'):
        seed = ''
        if mode.startswith('legacy'):
            seed = f'''<script>localStorage.setItem('asssets-review-'+{json.dumps(manifest['gallery'])},JSON.stringify({{reviewer:'Old Name',items:{{{json.dumps(item)}:{{favorite:true,note:'Older note',status:'approved'}}}}}}));</script>'''
        flow = r'''<script>
(async()=>{
let results=[], blobs=[];const old=URL.createObjectURL;URL.createObjectURL=b=>{blobs.push(b);return old.call(URL,b)};
const assert=(ok,msg)=>{if(!ok)throw Error(msg);results.push(msg)};
const click=id=>document.getElementById(id).click();
const type=(id,v)=>{const x=document.getElementById(id);x.value=v;x.dispatchEvent(new Event('input',{bubbles:true}))};
const download=async()=>{click('download');assert(blobs.length>0,'download button created a Blob');return JSON.parse(await blobs.pop().text())};
try{
if(MODE==='drafts'){
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
        html = original.replace('<script>\nconst M=', seed+'<script>\nconst M=',1).replace('</body>', '<pre id="results"></pre>'+flow+'</body>')
        test_page.write_text(html)
        with tempfile.TemporaryDirectory() as profile:
            p = subprocess.run([chrome,'--headless=new','--no-sandbox','--disable-gpu','--disable-extensions',f'--user-data-dir={profile}','--allow-file-access-from-files','--virtual-time-budget=5000','--dump-dom',test_page.as_uri()],capture_output=True,text=True,timeout=40)
        match=re.search(r'<pre id="results">(.*?)</pre>',p.stdout,re.S)
        if not match: raise RuntimeError(f'{mode}: no browser result; exit {p.returncode}: {p.stderr[-1200:]}')
        from html import unescape
        result=json.loads(unescape(match.group(1)))
        if 'error' in result: raise RuntimeError(f'{mode}: {result}')
        for i, download in enumerate(result['downloads']):
            (out / f'{mode}-{i}.json').write_text(json.dumps(download,indent=2)+'\n')
        print(mode, ', '.join(result['results']))
    (out / 'manifest.json').write_text(json.dumps(manifest,indent=2)+'\n')
finally:
    test_page.unlink(missing_ok=True)
