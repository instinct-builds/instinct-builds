import Foundation

// MARK: - Client review gallery: an offline HTML page out, a small feedback JSON back

public struct ClientNote: Codable, Hashable, Sendable {
    public var reviewer: String
    public var text: String
    public var gallery: String
    public init(reviewer: String, text: String, gallery: String) { self.reviewer = reviewer; self.text = text; self.gallery = gallery }
}

public enum ReviewGallery {
    public static let clientPickTag = "client-pick"
    public static let clientPicksName = "Client Picks"
    public static let format = "asssets-review-feedback"

    public struct Item: Codable, Equatable, Sendable {
        public var id: String            // asset UUID
        public var title: String
        public var kind: String
        public var resolution: String
        public var palette: [String]
        public var tags: [String]
        public var image: String         // relative path, e.g. "images/01.jpg"
        public var thumb: String
        public init(id: String, title: String, kind: String, resolution: String, palette: [String], tags: [String], image: String, thumb: String) {
            self.id = id; self.title = title; self.kind = kind; self.resolution = resolution; self.palette = palette; self.tags = tags; self.image = image; self.thumb = thumb
        }
    }

    public struct Manifest: Codable, Equatable, Sendable {
        public var gallery: String       // unique per export; keys the reviewer's local progress
        public var title: String
        public var created: String       // yyyy-MM-dd
        public var items: [Item]
        public init(gallery: String = UUID().uuidString, title: String, created: String, items: [Item]) {
            self.gallery = gallery; self.title = title; self.created = created; self.items = items
        }
    }

    /// What the gallery's "Download feedback" button saves. The page writes exactly this shape.
    public struct Feedback: Codable, Equatable, Sendable {
        public struct Entry: Codable, Equatable, Sendable {
            public var id: String
            public var favorite: Bool
            public var note: String
            public init(id: String, favorite: Bool, note: String) { self.id = id; self.favorite = favorite; self.note = note }
        }
        public var format: String
        public var gallery: String
        public var title: String
        public var reviewer: String
        public var items: [Entry]
        public init(gallery: String, title: String, reviewer: String, items: [Entry]) {
            self.format = ReviewGallery.format; self.gallery = gallery; self.title = title; self.reviewer = reviewer; self.items = items
        }
    }

    public static func decodeFeedback(_ data: Data) -> Feedback? {
        guard let f = try? JSONDecoder().decode(Feedback.self, from: data), f.format == format else { return nil }
        return f
    }

    /// Two-digit, then three-digit file stems in grid order: 01, 02 … 99, 100.
    public static func stem(_ index: Int, count: Int) -> String {
        String(format: "%0\(max(2, String(count).count))d", index + 1)
    }

    /// The whole gallery as one HTML file: styles, script and the manifest inline, images alongside.
    public static func html(_ m: Manifest) -> String {
        let data = (try? JSONEncoder().encode(m)) ?? Data("{}".utf8)
        // Inside <script>, "</" could end the tag early; "<\/" is the same JSON string.
        let json = String(decoding: data, as: UTF8.self).replacingOccurrences(of: "</", with: "<\\/")
        return template.replacingOccurrences(of: "__TITLE__", with: escape(m.title)).replacingOccurrences(of: "__MANIFEST__", with: json)
    }

    public static func escape(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;").replacingOccurrences(of: "\"", with: "&quot;")
    }

    static let template = #"""
<!doctype html>
<html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
<title>__TITLE__ · Review</title>
<style>
:root{--ink:#090a11;--panel:#0e0f17;--raised:rgba(255,255,255,.055);--line:rgba(255,255,255,.085);--text:#f2f2f7;--dim:rgba(242,242,247,.62);--faint:rgba(242,242,247,.38);--accent:#8c61ff;--pick:#ff5c8a}
*{box-sizing:border-box}html,body{margin:0;background:linear-gradient(#0b0d14,#130d1d) fixed;color:var(--text);font:14px/1.45 -apple-system,BlinkMacSystemFont,"SF Pro Text","Inter","Segoe UI",sans-serif}
header{position:sticky;top:0;z-index:5;display:flex;align-items:center;gap:18px;padding:18px 32px;background:rgba(9,10,17,.86);backdrop-filter:blur(14px);border-bottom:1px solid var(--line)}
.brand{font-weight:800;letter-spacing:.32em;font-size:12px;color:var(--accent)}h1{margin:0;font-size:22px;letter-spacing:-.01em}.sub{color:var(--dim);font-size:12.5px}
.spacer{flex:1}input.name{background:var(--raised);border:1px solid var(--line);color:var(--text);border-radius:8px;padding:8px 11px;width:190px;font:inherit}
button{font:inherit;cursor:pointer}.primary{background:var(--accent);color:#fff;border:0;border-radius:8px;padding:9px 14px;font-weight:600}
.filter{background:var(--raised);color:var(--dim);border:1px solid var(--line);border-radius:999px;padding:7px 12px}.filter.on{color:#fff;border-color:var(--pick);background:rgba(255,92,138,.14)}
main{display:grid;grid-template-columns:repeat(auto-fill,minmax(250px,1fr));gap:18px;padding:26px 32px 60px}
.card{background:var(--raised);border:1px solid var(--line);border-radius:14px;overflow:hidden;transition:transform .12s,border-color .12s}.card:hover{transform:translateY(-2px);border-color:rgba(140,97,255,.5)}
.card.picked{border-color:var(--pick);box-shadow:0 0 0 1px var(--pick)}
.thumb{position:relative;aspect-ratio:4/3;background:#07080c;cursor:zoom-in}.thumb img{width:100%;height:100%;object-fit:cover;display:block}
.heart{position:absolute;top:10px;right:10px;width:34px;height:34px;border-radius:50%;border:0;background:rgba(0,0,0,.55);color:#fff;font-size:17px;line-height:34px}
.picked .heart{background:var(--pick)}.noted{position:absolute;left:10px;top:10px;background:rgba(0,0,0,.6);border-radius:999px;padding:3px 9px;font-size:11px;font-weight:600}
.meta{padding:11px 13px 13px}.t{font-weight:650;white-space:nowrap;overflow:hidden;text-overflow:ellipsis}.r{color:var(--faint);font:11.5px ui-monospace,SFMono-Regular,Menlo,monospace;margin-top:2px}
.sw{display:flex;gap:3px;margin-top:9px}.sw i{flex:1;height:5px;border-radius:3px}
#lb{position:fixed;inset:0;z-index:10;background:rgba(4,4,8,.94);display:none;grid-template-columns:1fr 330px}#lb.open{display:grid}
#lb .stage{display:flex;align-items:center;justify-content:center;padding:34px;min-width:0}#lb .stage img{max-width:100%;max-height:calc(100vh - 68px);border-radius:10px;box-shadow:0 30px 80px rgba(0,0,0,.6)}
#lb aside{background:var(--panel);border-left:1px solid var(--line);padding:26px 22px;display:flex;flex-direction:column;gap:12px}
#lb h2{margin:0;font-size:19px}.lbl{font-size:10px;font-weight:700;letter-spacing:.14em;color:var(--faint);margin-top:6px}
.tags{display:flex;flex-wrap:wrap;gap:5px}.tags span{border:1px solid var(--line);background:var(--raised);border-radius:999px;padding:3px 9px;font-size:12px;color:var(--dim)}
textarea{background:var(--raised);border:1px solid var(--line);color:var(--text);border-radius:10px;padding:10px;min-height:120px;font:inherit;resize:vertical}
.pickbtn{border:1px solid var(--pick);color:var(--pick);background:transparent;border-radius:9px;padding:10px;font-weight:650}.pickbtn.on{background:var(--pick);color:#fff}
.nav{display:flex;gap:8px}.nav button{flex:1;background:var(--raised);border:1px solid var(--line);color:var(--text);border-radius:9px;padding:9px}
.close{position:absolute;top:16px;left:18px;background:rgba(255,255,255,.1);border:0;color:#fff;border-radius:50%;width:34px;height:34px;font-size:15px}
.hint{color:var(--faint);font-size:11.5px;margin-top:auto}footer{color:var(--faint);font-size:12px;text-align:center;padding:0 0 28px}
</style></head><body>
<header><div><div class="brand">ASSSETS</div><h1 id="title"></h1><div class="sub" id="sub"></div></div><div class="spacer"></div>
<button class="filter" id="onlyPicks">♥ Favorites only</button><input class="name" id="reviewer" placeholder="Your name" autocomplete="name">
<button class="primary" id="download">Download feedback</button></header>
<main id="grid"></main>
<div id="lb"><div class="stage"><button class="close" id="close" title="Close (Esc)">✕</button><img id="lbimg" alt=""></div>
<aside><h2 id="lbtitle"></h2><div class="r" id="lbres"></div><div class="sw" id="lbsw"></div>
<button class="pickbtn" id="lbpick">♥ Favorite</button><div class="lbl">NOTE</div><textarea id="lbnote" placeholder="What works, what to change…"></textarea>
<div class="lbl">TAGS</div><div class="tags" id="lbtags"></div><div class="nav"><button id="prev">← Prev</button><button id="next">Next →</button></div>
<div class="hint">← → browse · F favorite · Esc close. Your picks and notes stay in this browser until you download them.</div></aside></div>
<footer>Made with ASSSETS · send the downloaded feedback file back to the person who shared this gallery</footer>
<script type="application/json" id="manifest">__MANIFEST__</script>
<script>
const M=JSON.parse(document.getElementById('manifest').textContent);const KEY='asssets-review-'+M.gallery;
let S={reviewer:'',items:{}};try{S=Object.assign(S,JSON.parse(localStorage.getItem(KEY)||'{}'))}catch(e){}
const q=new URLSearchParams(location.search);
if(q.get('demo')){S.reviewer='Jordan (client)';M.items.forEach((it,i)=>{if(i%3===0)S.items[it.id]={favorite:true,note:i===0?'Love this one. Can we try it with the warmer backdrop?':''}})}
const save=()=>{try{localStorage.setItem(KEY,JSON.stringify(S))}catch(e){}};const st=id=>S.items[id]||(S.items[id]={favorite:false,note:''});
const $=id=>document.getElementById(id);let only=false,cur=-1;
$('title').textContent=M.title;document.title=M.title+' · Review';$('reviewer').value=S.reviewer;
$('reviewer').oninput=e=>{S.reviewer=e.target.value;save()};
function sub(){const f=M.items.filter(it=>st(it.id).favorite).length,n=M.items.filter(it=>st(it.id).note.trim()).length;$('sub').textContent=M.items.length+' assets · '+f+' favorites · '+n+' notes · shared '+M.created}
function swatches(el,p){el.innerHTML='';p.slice(0,5).forEach(h=>{const i=document.createElement('i');i.style.background=h;el.appendChild(i)})}
function render(){const g=$('grid');g.innerHTML='';M.items.forEach((it,i)=>{const s=st(it.id);if(only&&!s.favorite)return;
const c=document.createElement('div');c.className='card'+(s.favorite?' picked':'');
const th=document.createElement('div');th.className='thumb';const im=document.createElement('img');im.src=it.thumb;im.alt=it.title;im.loading='lazy';th.appendChild(im);th.onclick=()=>open(i);
const h=document.createElement('button');h.className='heart';h.textContent=s.favorite?'♥':'♡';h.title='Favorite';h.onclick=e=>{e.stopPropagation();s.favorite=!s.favorite;save();render()};th.appendChild(h);
if(s.note.trim()){const n=document.createElement('div');n.className='noted';n.textContent='✎ Note';th.appendChild(n)}
const m=document.createElement('div');m.className='meta';const t=document.createElement('div');t.className='t';t.textContent=it.title;const r=document.createElement('div');r.className='r';r.textContent=it.kind+' · '+it.resolution;
const sw=document.createElement('div');sw.className='sw';swatches(sw,it.palette);m.append(t,r,sw);c.append(th,m);g.appendChild(c)});sub()}
function open(i){cur=i;const it=M.items[i],s=st(it.id);$('lbimg').src=it.image;$('lbtitle').textContent=it.title;$('lbres').textContent=it.kind+' · '+it.resolution;swatches($('lbsw'),it.palette);
$('lbtags').innerHTML='';it.tags.slice(0,12).forEach(t=>{const s2=document.createElement('span');s2.textContent=t;$('lbtags').appendChild(s2)});
$('lbnote').value=s.note;$('lbpick').className='pickbtn'+(s.favorite?' on':'');$('lbpick').textContent=s.favorite?'♥ Favorited':'♥ Favorite';$('lb').classList.add('open')}
function close(){$('lb').classList.remove('open');cur=-1;render()}
function step(d){if(cur<0)return;open((cur+d+M.items.length)%M.items.length)}
$('lbpick').onclick=()=>{const s=st(M.items[cur].id);s.favorite=!s.favorite;save();open(cur)};$('lbnote').oninput=e=>{st(M.items[cur].id).note=e.target.value;save()};
$('close').onclick=close;$('prev').onclick=()=>step(-1);$('next').onclick=()=>step(1);
$('onlyPicks').onclick=()=>{only=!only;$('onlyPicks').classList.toggle('on',only);render()};
document.addEventListener('keydown',e=>{if(cur<0||e.target.tagName==='TEXTAREA')return;if(e.key==='Escape')close();else if(e.key==='ArrowRight')step(1);else if(e.key==='ArrowLeft')step(-1);else if(e.key==='f'){$('lbpick').click()}});
$('download').onclick=()=>{const out={format:'asssets-review-feedback',gallery:M.gallery,title:M.title,reviewer:S.reviewer.trim(),
items:M.items.map(it=>({id:it.id,favorite:!!st(it.id).favorite,note:(st(it.id).note||'').trim()})).filter(x=>x.favorite||x.note)};
const a=document.createElement('a');a.href=URL.createObjectURL(new Blob([JSON.stringify(out,null,2)],{type:'application/json'}));
a.download=(M.title+' feedback'+(out.reviewer?' - '+out.reviewer:'')).replace(/[\/:\\]/g,'-')+'.json';document.body.appendChild(a);a.click();a.remove()};
render();if(q.get('demo')==='lightbox')open(0);
</script></body></html>
"""#
}

extension StudioCatalog {
    public struct FeedbackResult: Equatable, Sendable {
        public var favorites = 0, notes = 0, unknown = 0
        public var smartCollection: UUID?
    }

    /// Applies a client's feedback: favorites get "client-pick", notes are stored per reviewer and gallery.
    /// Re-importing the same reviewer's file for the same gallery replaces their earlier note and picks.
    @discardableResult
    public mutating func applyFeedback(_ f: ReviewGallery.Feedback) -> FeedbackResult {
        var r = FeedbackResult()
        let reviewer = f.reviewer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Client" : f.reviewer.trimmingCharacters(in: .whitespacesAndNewlines)
        let index = Dictionary(uniqueKeysWithValues: assets.enumerated().map { ($1.id.uuidString.uppercased(), $0) })
        for e in f.items {
            guard let i = index[e.id.uppercased()] else { r.unknown += 1; continue }
            if e.favorite {
                r.favorites += 1
                if !assets[i].tags.contains(ReviewGallery.clientPickTag) { assets[i].tags.append(ReviewGallery.clientPickTag) }
            }
            assets[i].clientNotes.removeAll { $0.reviewer == reviewer && $0.gallery == f.gallery }
            let text = e.note.trimmingCharacters(in: .whitespacesAndNewlines)
            if !text.isEmpty { r.notes += 1; assets[i].clientNotes.append(ClientNote(reviewer: reviewer, text: String(text.prefix(4000)), gallery: f.gallery)) }
        }
        if r.favorites > 0 {
            let rules = SmartRules(requiredTags: [ReviewGallery.clientPickTag])
            if let s = smartCollections.first(where: { $0.rules == rules }) { r.smartCollection = s.id }
            else {
                let s = StudioSmartCollection(name: uniqueSmartName(ReviewGallery.clientPicksName), rules: rules, symbol: "heart.text.square")
                smartCollections.append(s); r.smartCollection = s.id
            }
        }
        return r
    }
}
