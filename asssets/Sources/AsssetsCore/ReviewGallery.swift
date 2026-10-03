import Foundation

// MARK: - Client review gallery: an offline HTML page out, a small feedback JSON back

public struct ClientNote: Codable, Hashable, Sendable {
    public var reviewer: String
    public var text: String
    public var gallery: String
    /// 1.81: the designer's local "done" tick. Never sent to the client; older catalogs decode as open.
    public var resolved: Bool
    public init(reviewer: String, text: String, gallery: String, resolved: Bool = false) {
        self.reviewer = reviewer; self.text = text; self.gallery = gallery; self.resolved = resolved
    }
    enum CodingKeys: String, CodingKey { case reviewer, text, gallery, resolved }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        reviewer = try c.decode(String.self, forKey: .reviewer)
        text = try c.decode(String.self, forKey: .text)
        gallery = try c.decode(String.self, forKey: .gallery)
        resolved = try c.decodeIfPresent(Bool.self, forKey: .resolved) ?? false
    }
    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(reviewer, forKey: .reviewer); try c.encode(text, forKey: .text); try c.encode(gallery, forKey: .gallery)
        if resolved { try c.encode(true, forKey: .resolved) }
    }
}

/// A client's Approve / Request changes decision on one asset in one review round (1.84).
public struct ClientDecision: Codable, Hashable, Sendable {
    public var reviewer: String
    public var gallery: String
    public var status: CardStatus
    public init(reviewer: String, gallery: String, status: CardStatus) { self.reviewer = reviewer; self.gallery = gallery; self.status = status }
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
        /// Credit line from the asset's usage rights (1.25).
        public var credit: String? = nil
        public init(id: String, title: String, kind: String, resolution: String, palette: [String], tags: [String], image: String, thumb: String) {
            self.id = id; self.title = title; self.kind = kind; self.resolution = resolution; self.palette = palette; self.tags = tags; self.image = image; self.thumb = thumb
        }
    }

    public struct Manifest: Codable, Equatable, Sendable {
        public var gallery: String       // unique per export; keys the reviewer's local progress
        public var title: String
        public var created: String       // yyyy-MM-dd
        public var items: [Item]
        /// Set when the gallery was shared from a moodboard (1.17): the board image with a clickable spot per asset.
        public var board: Board?
        /// Set when the round summary PDF ships alongside (1.22 Share Round): its file name in the folder.
        public var summary: String?
        /// Credits page (1.25): one line per credit with what it covers. nil or empty hides it.
        public var credits: [CreditLine]? = nil
        public init(gallery: String = UUID().uuidString, title: String, created: String, items: [Item], board: Board? = nil, summary: String? = nil) {
            self.gallery = gallery; self.title = title; self.created = created; self.items = items; self.board = board; self.summary = summary
        }
    }

    public struct Board: Codable, Equatable, Sendable {
        /// An asset's place on the board image, as fractions (0-1) of its width and height.
        public struct Spot: Codable, Equatable, Sendable {
            public var id: String
            public var x: Double, y: Double, w: Double, h: Double
            public init(id: String, x: Double, y: Double, w: Double, h: Double) { self.id = id; self.x = x; self.y = y; self.w = w; self.h = h }
        }
        public var image: String
        public var width: Int
        public var height: Int
        public var spots: [Spot]
        public init(image: String, width: Int, height: Int, spots: [Spot]) { self.image = image; self.width = width; self.height = height; self.spots = spots }
    }

    /// Spots for the asset cards whose assets made it into the gallery, back to front, measured against the export frame.
    public static func spots(for board: Moodboard, including ids: Set<UUID>) -> [Board.Spot] {
        let r = board.exportRect
        guard r.w > 0, r.h > 0 else { return [] }
        return board.layered.compactMap { it in
            guard it.kind == .asset, let a = it.assetID, ids.contains(a) else { return nil }
            return Board.Spot(id: a.uuidString, x: (it.x - r.x) / r.w, y: (it.y - r.y) / r.h, w: it.w / r.w, h: it.h / r.h)
        }
    }

    /// What the gallery's "Download feedback" button saves. The page writes exactly this shape.
    public struct Feedback: Codable, Equatable, Sendable {
        public struct Entry: Codable, Equatable, Sendable {
            public var id: String
            public var favorite: Bool
            public var note: String
            /// 1.23: "approved" or "changes" when the client pressed Approve / Request changes. Older files leave it out.
            public var status: String?
            public init(id: String, favorite: Bool, note: String, status: String? = nil) { self.id = id; self.favorite = favorite; self.note = note; self.status = status }
            /// The card status the client asked for; nil when they didn't choose (or wrote something unknown).
            public var cardStatus: CardStatus? {
                switch status?.lowercased() { case "approved": return .approved; case "changes": return .changes; default: return nil }
            }
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

    /// Read only the inert JSON manifest embedded in an original offline gallery page.
    public static func manifest(fromHTML html: String) -> Manifest? {
        let start = "<script type=\"application/json\" id=\"manifest\">"
        guard let first = html.range(of: start), let last = html.range(of: "</script>", range: first.upperBound..<html.endIndex),
              html.distance(from: first.upperBound, to: last.lowerBound) < 1_000_000 else { return nil }
        let encoded = String(html[first.upperBound..<last.lowerBound]).replacingOccurrences(of: "<\\/", with: "</")
        guard let m = try? JSONDecoder().decode(Manifest.self, from: Data(encoded.utf8)),
              !m.items.isEmpty,
              m.items.allSatisfy({ UUID(uuidString: $0.id) != nil }),
              Set(m.items.compactMap { UUID(uuidString: $0.id) }).count == m.items.count else { return nil }
        return m
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
header{position:sticky;top:0;z-index:5;display:flex;align-items:center;flex-wrap:wrap;gap:10px 16px;padding:14px 24px;background:rgba(9,10,17,.86);backdrop-filter:blur(14px);border-bottom:1px solid var(--line)}
.brand{font-weight:800;letter-spacing:.32em;font-size:12px;color:var(--accent)}h1{margin:0;font-size:22px;letter-spacing:-.01em}.sub{color:var(--dim);font-size:12.5px}
.spacer{flex:1}button.name{background:var(--raised);border:1px solid var(--line);color:var(--text);border-radius:8px;padding:8px 11px;min-width:150px;max-width:min(100%,360px);white-space:normal;overflow-wrap:anywhere;text-align:left;font:inherit}
.reviewer-tools{display:flex;gap:5px}.reviewer-tools button{border:1px solid var(--line);background:var(--raised);color:var(--dim);border-radius:8px;padding:7px 9px;font-size:12px}
.reviewer-tools button:hover{color:var(--text)}#download{margin-left:auto}
#saveState{width:100%;display:none;padding:9px 12px;border:1px solid #ff9f0a;border-radius:8px;background:#342311;color:#ffe0ac;font-size:12px}#saveState.on{display:block}#saveState button{margin-left:10px;padding:3px 9px;border:1px solid #ffbf65;border-radius:6px;color:#fff;background:transparent}
.review-modal{position:fixed;inset:0;z-index:20;background:rgba(0,0,0,.8);display:none;align-items:center;justify-content:center;padding:20px}.review-modal.open{display:flex}
.review-dialog{width:min(480px,100%);max-height:calc(100vh - 40px);overflow:auto;background:#171822;border:1px solid var(--line);border-radius:14px;padding:22px;box-shadow:0 30px 80px #0008}.review-dialog h2{margin:0 0 8px;font-size:19px}.review-dialog p{margin:0 0 16px;color:var(--dim);font-size:13px}.review-dialog select,.review-dialog input{width:100%;background:var(--raised);color:var(--text);border:1px solid var(--line);border-radius:8px;padding:9px;font:inherit}.review-dialog label{display:block;color:var(--dim);font-size:12px;margin:10px 0 5px}.review-actions{display:flex;justify-content:flex-end;flex-wrap:wrap;gap:8px;margin-top:18px}.review-actions button{background:var(--raised);border:1px solid var(--line);color:var(--text);border-radius:8px;padding:8px 12px}.review-actions .primary{background:var(--accent)}
button{font:inherit;cursor:pointer}:focus-visible{outline:3px solid #c7b4ff;outline-offset:3px}.primary{background:var(--accent);color:#fff;border:0;border-radius:8px;padding:9px 14px;font-weight:600}
.filter{background:var(--raised);color:var(--dim);border:1px solid var(--line);border-radius:999px;padding:7px 12px}.filter.on{color:#fff;border-color:var(--pick);background:rgba(255,92,138,.14)}a.filter{text-decoration:none;font-size:13px}a.filter[hidden]{display:none}
#queueTools{display:flex;flex-wrap:wrap;align-items:center;gap:8px 12px;padding:16px 32px 0}#queueTools label{font-size:12px;color:var(--dim)}#queueTools input,#queueTools select,#queueTools button,#queueEmpty button{border:1px solid var(--line);background:#191922;color:var(--text);border-radius:8px;padding:8px 10px;font:inherit}#queueSearch{width:240px;max-width:100%}#queueCount{font-size:12px;color:var(--dim)}#queueEmpty{margin:26px 32px;padding:24px;border:1px solid var(--line);border-radius:14px;background:var(--raised)}#queueEmpty h2{font-size:18px;margin:0 0 6px}#queueEmpty p{color:var(--dim)}
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
.hint{color:var(--faint);font-size:11.5px;margin-top:auto}
.st{display:flex;gap:6px;margin-top:10px}.st button{flex:1;border:1px solid var(--line);background:transparent;color:var(--dim);border-radius:8px;padding:6px 0;font-size:12px;font-weight:650}
.st button:hover{color:var(--text)}.st .ap.on{background:rgba(52,199,89,.18);border-color:#34c759;color:#8be9a6}.st .ch.on{background:rgba(255,159,10,.16);border-color:#ff9f0a;color:#ffc46b}
.st.big button{padding:10px 0;font-size:13px}.chip{position:absolute;left:10px;bottom:10px;border-radius:999px;padding:3px 10px;font-size:11px;font-weight:750}
.chip.approved{background:#34c759;color:#062510}.chip.changes{background:#ff9f0a;color:#2b1800}.card.approved{border-color:rgba(52,199,89,.55)}.card.changes{border-color:rgba(255,159,10,.55)}
.spot .chip{left:6px;bottom:6px;font-size:10px;padding:2px 8px;pointer-events:none}
#board{padding:26px 32px 0;display:none}#board.on{display:block}#board .lbl{margin:0 0 10px}
.bwrap{position:relative;border-radius:14px;overflow:hidden;border:1px solid var(--line);background:#0b0c12}.bwrap img{width:100%;display:block}
.spot{position:absolute;border:2px solid transparent;border-radius:10px;cursor:zoom-in;transition:border-color .12s,background .12s}.spot:hover{border-color:var(--accent);background:rgba(140,97,255,.12)}
.spot:focus-visible{outline-offset:-5px}.spot.picked{border-color:var(--pick)}.spot .heart{top:6px;right:6px;width:26px;height:26px;line-height:26px;font-size:13px;pointer-events:none}footer{color:var(--faint);font-size:12px;text-align:center;padding:0 0 28px}
#credits{display:none;margin:22px 32px 0;border:1px solid var(--line);border-radius:14px;background:var(--raised);padding:18px 22px}#credits.on{display:block}
#credits h2{margin:0 0 4px;font-size:17px}#credits .cs{color:var(--dim);font-size:12.5px;margin-bottom:12px}.cr{display:grid;grid-template-columns:minmax(180px,1fr) 130px 2fr;gap:14px;padding:10px 0;border-top:1px solid var(--line);font-size:13px}
.lf{display:block;margin-top:3px;font-size:11px;color:var(--accent,#a78bfa);text-decoration:none;word-break:break-word}a.lf:hover{text-decoration:underline}.cr b{font-weight:650}.cr .lic{color:var(--dim);font-size:12px}.cr .what{color:var(--dim)}.lbcredit{color:var(--dim);font-size:12px;margin-top:-4px}
</style></head><body>
<header><div><div class="brand">ASSSETS</div><h1 id="title"></h1><div class="sub" id="sub"></div></div><div class="spacer"></div>
<a class="filter" id="summary" target="_blank" hidden>Round summary (PDF)</a><button class="filter" id="creditsBtn" hidden>Credits</button><button class="filter" id="onlyPicks">♥ Favorites only</button><button class="name" id="reviewer" aria-label="Choose reviewer">Choose reviewer</button>
<span class="reviewer-tools"><button id="renameReviewer">Rename</button><button id="switchReviewer">Switch reviewer</button></span>
<button class="primary" id="download">Download feedback</button><div id="saveState" role="alert" aria-live="assertive"></div></header>
<section id="queueTools" aria-label="Review queue"><label for="queueSearch">Find assets</label><input id="queueSearch" type="search" placeholder="Title or tags"><label for="queueDecision">Decision</label><select id="queueDecision"><option value="">All decisions</option><option value="approved">Approved</option><option value="changes">Changes</option><option value="undecided">No decision</option></select><button id="queueReset">Reset filters</button><span id="queueCount" role="status" aria-live="polite"></span></section>
<div id="queueEmpty" hidden><h2>No assets match these filters</h2><p>Your picks, notes and decisions have not been removed. Reset filters to see the full gallery.</p><button id="queueEmptyReset">Show all assets</button></div>
<section id="credits"><h2>Credits</h2><div class="cs" id="creditsSub"></div><div id="creditRows"></div></section>
<section id="board"><div class="lbl">BOARD · CLICK ANY IMAGE TO REVIEW IT</div><div class="bwrap" id="bwrap"></div></section>
<main id="grid"></main>
<div id="lb" role="dialog" aria-modal="true" aria-labelledby="lbtitle"><div class="stage"><button class="close" id="close" title="Close (Esc)">✕</button><img id="lbimg" alt=""></div>
<aside><h2 id="lbtitle"></h2><div class="r" id="lbres"></div><div class="lbcredit" id="lbcredit"></div><div class="sw" id="lbsw"></div>
<button class="pickbtn" id="lbpick">♥ Favorite</button><div class="lbl">DECISION</div><div class="st big" id="lbst"><button class="ap" id="lbap">✓ Approve</button><button class="ch" id="lbch">↺ Request changes</button></div><div class="lbl">NOTE</div><textarea aria-label="Review note" id="lbnote" placeholder="What works, what to change…"></textarea>
<div class="lbl">TAGS</div><div class="tags" id="lbtags"></div><div class="nav"><button id="prev">← Prev</button><button id="next">Next →</button></div>
<div class="hint">← → browse · F favorite · A approve · C changes · Esc close. Picks and notes save in this browser only when storage succeeds. Download feedback to keep a separate copy.</div></aside></div>
<footer>Made with ASSSETS · send the downloaded feedback file back to the person who shared this gallery</footer>
<div class="review-modal" id="reviewModal" role="dialog" aria-modal="true" aria-labelledby="reviewModalTitle" aria-describedby="reviewModalText"><div class="review-dialog"><h2 id="reviewModalTitle"></h2><p id="reviewModalText"></p>
<div id="switchFields"><label for="knownReviewers">Saved drafts</label><select id="knownReviewers"></select><label for="newReviewer">Or start a new reviewer draft</label><input id="newReviewer" placeholder="Reviewer name"></div>
<div id="legacyFields"><label for="legacyInput">Name for this earlier draft (edit if needed)</label><input id="legacyInput" placeholder="Reviewer name"></div>
<div id="renameFields"><label for="renameInput">Name for this draft</label><input id="renameInput" placeholder="Reviewer name"></div>
<div class="review-actions" id="reviewModalActions"></div></div></div>
<script type="application/json" id="manifest">__MANIFEST__</script>
<script>
const M=JSON.parse(document.getElementById('manifest').textContent);const KEY='asssets-review-'+M.gallery;
const DKEY=KEY+'-drafts-v2',ACTIVE=KEY+'-active-v2';
const norm=n=>(n||'').trim().toLocaleLowerCase();const empty=n=>({reviewer:n,items:{}});
let storageProblem='',recoveryProblem='',recoveryDownloaded=false;
const rawStorage={},CHOICE=KEY+'-legacy-choice-v2';
const object=v=>v!==null&&typeof v==='object'&&!Array.isArray(v);
const validItem=v=>object(v)&&(v.favorite===undefined||typeof v.favorite==='boolean')&&(v.note===undefined||typeof v.note==='string')&&(v.status===undefined||['','approved','changes'].includes(v.status));
const validDraft=d=>object(d)&&typeof d.reviewer==='string'&&object(d.items)&&Object.values(d.items).every(validItem);
function read(k){try{const raw=localStorage.getItem(k);rawStorage[k]=raw;if(raw===null)return null;
try{return JSON.parse(raw)}catch(e){recoveryProblem='Stored draft data is not readable JSON.';return null}
}catch(e){storageProblem='Browser storage is unavailable or blocked.';return null}}
let drafts=read(DKEY),active=read(ACTIVE),legacy=read(KEY),legacyChoice=read(CHOICE);
if(rawStorage[DKEY]!==null&&rawStorage[DKEY]!==undefined&&(!object(drafts)||!Object.entries(drafts).every(([key,d])=>validDraft(d)&&norm(d.reviewer)===key&&key.length>0)))recoveryProblem=recoveryProblem||'Stored reviewer drafts have an unsupported shape.';
if(rawStorage[KEY]!==null&&rawStorage[KEY]!==undefined&&!validDraft(legacy))recoveryProblem=recoveryProblem||'The earlier draft has an unsupported shape.';
if(active!==null&&(typeof active!=='string'||!object(drafts)||!validDraft(drafts[active])))recoveryProblem=recoveryProblem||'The active reviewer does not point to a readable draft.';
if(legacyChoice!==null&&!['fresh','continued'].includes(legacyChoice))recoveryProblem=recoveryProblem||'The earlier-draft choice is unreadable.';
if(!object(drafts))drafts={};
let S=empty('');const $=id=>document.getElementById(id);let only=false,cur=-1,unsaved=false,queueText='',queueDecision='';
function notice(reason){unsaved=true;const bar=$('saveState');bar.classList.add('on');bar.textContent='Not saved in this browser: '+reason+' '+(recoveryProblem?'Use the recovery dialog to download the stored bytes.':'Download feedback now to keep this draft. Do not reload or close this tab.');
const retry=document.createElement('button');retry.textContent='Try saving again';retry.onclick=put;bar.appendChild(retry)}
function saved(){unsaved=false;storageProblem='';$('saveState').classList.remove('on');$('saveState').textContent=''}
function commit(next,key){if(recoveryProblem){notice(recoveryProblem+' Stored data has not been replaced.');return false}const value=JSON.stringify(next),pointer=JSON.stringify(key);
let previousDrafts=null,previousActive=null,wrote=false;
try{previousDrafts=localStorage.getItem(DKEY);previousActive=localStorage.getItem(ACTIVE);
localStorage.setItem(DKEY,value);wrote=true;localStorage.setItem(ACTIVE,pointer);
if(localStorage.getItem(DKEY)!==value||localStorage.getItem(ACTIVE)!==pointer)throw Error('readback');
drafts=next;saved();return true
}catch(e){if(wrote){try{if(previousDrafts===null)localStorage.removeItem(DKEY);else localStorage.setItem(DKEY,previousDrafts);
if(previousActive===null)localStorage.removeItem(ACTIVE);else localStorage.setItem(ACTIVE,previousActive)}catch(rollback){/* keep the warning, never promise recovery */}}
const reason=e&&e.name==='QuotaExceededError'?'Browser storage is full.':e&&e.message==='readback'?'The browser did not confirm the stored draft and active reviewer.':'Browser storage is unavailable or blocked.';notice(reason);return false}}
function put(){if(!norm(S.reviewer))return false;
const key=norm(S.reviewer);return commit({...drafts,[key]:{reviewer:S.reviewer.trim(),items:S.items}},key)}
function save(){put()}
function take(name){const d=drafts[norm(name)];S=validDraft(d)?{reviewer:d.reviewer,items:d.items}:empty(name);reviewerLabel();closeReviewerModal();if(cur>=0)close();else render();put()}
let modalReturn=null,lightboxReturn=null,modalKind='';
function reviewerLabel(){$('reviewer').textContent=S.reviewer||'Choose reviewer';$('reviewer').setAttribute('aria-label','Reviewer: '+(S.reviewer||'Choose reviewer')+'. Switch reviewer')}
function focusable(root){return [...root.querySelectorAll('button,input,select,textarea,a[href],[tabindex="0"]')].filter(e=>!e.disabled&&e.getClientRects().length)}
function overlays(){const reviewing=$('lb').classList.contains('open'),choosing=$('reviewModal').classList.contains('open');
document.querySelectorAll('header,main,#board,#credits,footer,#queueTools,#queueEmpty').forEach(e=>e.inert=reviewing||choosing);$('lb').inert=choosing}
function restoreFocus(target){if(target&&target!==document.body&&target.isConnected&&!target.closest('[inert]'))target.focus();else $('reviewer').focus()}
function closeReviewerModal(){$('reviewModal').classList.remove('open');overlays();restoreFocus(modalReturn)}
function modal(title,text,buttons,kind){if(!$('reviewModal').classList.contains('open'))modalReturn=document.activeElement;modalKind=kind;$('reviewModalTitle').textContent=title;$('reviewModalText').textContent=text;
$('switchFields').hidden=kind!=='switch';$('renameFields').hidden=kind!=='rename';$('legacyFields').hidden=kind!=='legacy';const actions=$('reviewModalActions');actions.innerHTML='';
buttons.forEach(([label,fn,primary])=>{const b=document.createElement('button');b.textContent=label;if(primary)b.className='primary';b.onclick=fn;actions.appendChild(b)});$('reviewModal').classList.add('open');overlays();(focusable($('reviewModal'))[0]||$('reviewModal')).focus()}
function listNames(){const select=$('knownReviewers');select.innerHTML='';Object.values(drafts).filter(validDraft).forEach(d=>{const opt=document.createElement('option');opt.value=d.reviewer;opt.textContent=d.reviewer;select.appendChild(opt)});const fresh=document.createElement('option');fresh.value='';fresh.textContent='New reviewer';select.appendChild(fresh);select.value='';$('newReviewer').value=''}
function showBlockedSwitch(){modal('Draft not saved','Switching now could lose this reviewer’s picks, notes or decisions. Download this draft first, then try saving again before switching.',[
['Keep reviewing',closeReviewerModal],['Download feedback',()=>{closeReviewerModal();downloadFeedback()}]],'blocked')}
function switchReviewer(){if(recoveryProblem){showRecovery();return}if(norm(S.reviewer)&&!put()){showBlockedSwitch();return}
listNames();modal('Switch reviewer','The current draft stays in this browser only when saving succeeds. Switching loads only the selected reviewer’s picks, notes and decisions.',[
...(norm(S.reviewer)?[['Cancel',closeReviewerModal]]:[]),['Switch',()=>{const fresh=$('newReviewer').value.trim(),name=fresh||$('knownReviewers').value;if(!name)return;if(fresh&&drafts[norm(fresh)]){alert('That name already has a draft. Choose it from Saved drafts.');return}if(norm(name)===norm(S.reviewer)){closeReviewerModal();return}take(name)},true]],'switch')}
function renameReviewer(){if(recoveryProblem){showRecovery();return}if(!norm(S.reviewer))return;if(!put()){showBlockedSwitch();return}$('renameInput').value=S.reviewer;modal('Rename this reviewer','Change the name on this draft without creating or copying another draft. Feedback already downloaded under the old name will not change.',[
['Cancel',closeReviewerModal],['Rename',()=>{const name=$('renameInput').value.trim(),before=norm(S.reviewer),after=norm(name);if(!after)return;
if(after!==before&&drafts[after]){alert('A different reviewer already has a draft under that name. Use Switch reviewer.');return}
if(after===before){const previous=S.reviewer;S.reviewer=name;if(!put()){S.reviewer=previous;closeReviewerModal();return}reviewerLabel();closeReviewerModal();return}
// Write the new name and remove the old one in one stored draft-set operation.
const next={...drafts};delete next[before];next[after]={reviewer:name,items:S.items};
if(!commit(next,after)){closeReviewerModal();return}S.reviewer=name;
reviewerLabel();closeReviewerModal()},true]],'rename')}
$('switchReviewer').onclick=switchReviewer;$('renameReviewer').onclick=renameReviewer;
$('reviewer').onclick=switchReviewer;
if(!recoveryProblem&&!qForDemo()&&validDraft(legacy)&&!legacyChoice){
const legacyName=(legacy.reviewer||'').trim();$('legacyInput').value=legacyName;modal('Earlier draft found','This browser has an older single draft. Choose whether to keep it under its displayed name or start a fresh draft. No draft is deleted automatically.',[
['Continue earlier draft',()=>{const name=$('legacyInput').value.trim();if(!name)return;const key=norm(name);if(drafts[key]){alert('A saved draft already uses that name. Choose a different name for the earlier draft.');return}S={reviewer:name.trim(),items:legacy.items};if(put()){try{localStorage.setItem(KEY+'-legacy-choice-v2',JSON.stringify('continued'))}catch(e){notice('The earlier-draft choice could not be saved.')}}closeReviewerModal();reviewerLabel();render()}],
['Start fresh',()=>{try{localStorage.setItem(KEY+'-legacy-choice-v2',JSON.stringify('fresh'))}catch(e){notice('The fresh-draft choice could not be saved.')}if(active&&validDraft(drafts[active]))take(drafts[active].reviewer);else switchReviewer()},true]],'legacy')
}else if(!recoveryProblem&&active&&validDraft(drafts[active]))S={reviewer:drafts[active].reviewer,items:drafts[active].items};
function downloadRecovery(){const out={format:'asssets-review-storage-recovery',gallery:M.gallery,reason:recoveryProblem,stored:rawStorage};
const a=document.createElement('a');a.href=URL.createObjectURL(new Blob([JSON.stringify(out,null,2)],{type:'application/json'}));a.download='ASSSETS draft storage recovery.json';document.body.appendChild(a);a.click();a.remove();recoveryDownloaded=true;showRecovery()}
function startFreshRecovery(){if(!recoveryDownloaded)return;if(!confirm('Have you checked that the recovery copy is in your downloads? Replacing storage removes all browser drafts for this gallery. This cannot be undone here.'))return;
const values={[DKEY]:'{}',[ACTIVE]:'null',[KEY]:null,[CHOICE]:JSON.stringify('fresh')};
try{for(const [k,v] of Object.entries(values)){if(v===null)localStorage.removeItem(k);else localStorage.setItem(k,v)};
for(const [k,v] of Object.entries(values))if(localStorage.getItem(k)!==v)throw Error('readback');
recoveryProblem='';drafts={};active=null;legacy=null;S=empty('');saved();closeReviewerModal();reviewerLabel();render();switchReviewer()
}catch(e){try{for(const [k,v] of Object.entries(rawStorage)){if(v===null)localStorage.removeItem(k);else localStorage.setItem(k,v)}}catch(rollback){}
notice('Fresh storage could not be confirmed. Keep the recovery download and do not close this tab.');showRecovery()}}
function showRecovery(){modal('Stored drafts need recovery',recoveryProblem+' Automatic saving is paused so the stored data is not silently replaced. Download the raw storage first. It is a recovery copy, not feedback for native import. Starting fresh replaces this gallery’s browser drafts; it does not change feedback already downloaded. Reviewer names are local labels, not verified identities.',[
['Download recovery copy',downloadRecovery],...(recoveryDownloaded?[['Replace stored drafts and start fresh',startFreshRecovery,true]]:[])],'recovery')}
function qForDemo(){return new URLSearchParams(location.search).has('demo')}
const q=new URLSearchParams(location.search);
if((q.get('demo')||'').startsWith('approve')){S.reviewer='Mara Quinn';const plan=[['approved','Brass plinth is the one. Approved for the lobby.'],['changes','Too tech for us - can the screen show the stone frame?'],['approved',''],['',''],['changes','Warmer, please.'],['approved','']];
M.items.forEach((it,i)=>{const p=plan[i%plan.length];S.items[it.id]={favorite:i===0||i===2,note:p[1],status:p[0]}})}
else if(q.get('demo')){S.reviewer='Jordan (client)';M.items.forEach((it,i)=>{if(i%3===0)S.items[it.id]={favorite:true,note:i===0?'Love this one. Can we try it with the warmer backdrop?':''}})}
const st=id=>S.items[id]||(S.items[id]={favorite:false,note:'',status:''});
const LBL={approved:'✓ Approved',changes:'↺ Changes'};const decide=(id,v)=>{if($('reviewModal').classList.contains('open'))return;const s=st(id);s.status=s.status===v?'':v;save()};
$('title').textContent=M.title;document.title=M.title+' · Review';reviewerLabel();
function sub(){const f=M.items.filter(it=>st(it.id).favorite).length,n=M.items.filter(it=>(st(it.id).note||'').trim()).length,a=M.items.filter(it=>st(it.id).status==='approved').length,c=M.items.filter(it=>st(it.id).status==='changes').length;
$('sub').textContent=M.items.length+' assets · '+f+' favorites · '+a+' approved · '+c+' changes · '+n+' notes · shared '+M.created}
function swatches(el,p){el.innerHTML='';p.slice(0,5).forEach(h=>{const i=document.createElement('i');i.style.background=h;el.appendChild(i)})}
function filtering(){return only||queueText.length>0||queueDecision.length>0}
function matches(it){const s=st(it.id);return (!only||s.favorite)&&(!queueText||[it.title,...it.tags].join(' ').toLocaleLowerCase().includes(queueText))&&(!queueDecision||(queueDecision==='undecided'?!s.status:s.status===queueDecision))}
function queue(){return M.items.map((it,i)=>matches(it)?i:-1).filter(i=>i>=0)}
function resetQueue(){queueText='';queueDecision='';only=false;$('queueSearch').value='';$('queueDecision').value='';$('onlyPicks').classList.remove('on');$('onlyPicks').setAttribute('aria-pressed','false');render()}
$('queueSearch').oninput=e=>{queueText=e.target.value.trim().toLocaleLowerCase();render()};$('queueDecision').onchange=e=>{queueDecision=e.target.value;render()};$('queueReset').onclick=resetQueue;$('queueEmptyReset').onclick=()=>{resetQueue();$('queueSearch').focus()};
function render(){const g=$('grid');g.innerHTML='';M.items.forEach((it,i)=>{const s=st(it.id);if(!matches(it))return;
const c=document.createElement('div');c.className='card'+(s.favorite?' picked':'')+(s.status?' '+s.status:'');
const th=document.createElement('div');th.className='thumb';th.tabIndex=0;th.setAttribute('role','button');th.setAttribute('aria-label','Review '+it.title);th.dataset.reviewId=it.id;th.onkeydown=e=>{if(e.target===th&&(e.key==='Enter'||e.key===' ')){e.preventDefault();open(i)}};const im=document.createElement('img');im.src=it.thumb;im.alt=it.title;im.loading='lazy';th.appendChild(im);th.onclick=()=>open(i);
const h=document.createElement('button');h.className='heart';h.textContent=s.favorite?'♥':'♡';h.title='Favorite';h.setAttribute('aria-label','Favorite '+it.title);h.setAttribute('aria-pressed',String(!!s.favorite));h.onclick=e=>{e.stopPropagation();if($('reviewModal').classList.contains('open'))return;s.favorite=!s.favorite;save();render()};th.appendChild(h);
if((s.note||'').trim()){const n=document.createElement('div');n.className='noted';n.textContent='✎ Note';th.appendChild(n)}
if(s.status){const k=document.createElement('div');k.className='chip '+s.status;k.textContent=LBL[s.status];th.appendChild(k)}
const m=document.createElement('div');m.className='meta';const t=document.createElement('div');t.className='t';t.textContent=it.title;const r=document.createElement('div');r.className='r';r.textContent=it.kind+' · '+it.resolution;
const sw=document.createElement('div');sw.className='sw';swatches(sw,it.palette);
const dc=document.createElement('div');dc.className='st';[['approved','ap','✓ Approve'],['changes','ch','↺ Changes']].forEach(([v,k,l])=>{const b=document.createElement('button');b.className=k+(s.status===v?' on':'');b.textContent=l;b.onclick=e=>{e.stopPropagation();decide(it.id,v);render()};dc.appendChild(b)});
m.append(t,r,sw,dc);c.append(th,m);g.appendChild(c)});$('queueEmpty').hidden=g.childElementCount>0;$('queueCount').textContent=g.childElementCount+' of '+M.items.length+' assets'+(filtering()?' · board overview hidden · downloads include all feedback':'');sub();board()}
function board(){$('board').classList.toggle('on',!!M.board&&!filtering());if(!M.board||filtering())return;$('board').classList.add('on');const w=$('bwrap');w.innerHTML='';const im=document.createElement('img');im.src=M.board.image;im.alt=M.title;w.appendChild(im);
M.board.spots.forEach(sp=>{const i=M.items.findIndex(it=>it.id===sp.id);if(i<0)return;const s=st(sp.id);const d=document.createElement('div');d.className='spot'+(s.favorite?' picked':'');
d.style.left=(sp.x*100)+'%';d.style.top=(sp.y*100)+'%';d.style.width=(sp.w*100)+'%';d.style.height=(sp.h*100)+'%';d.title=M.items[i].title;d.tabIndex=0;d.setAttribute('role','button');d.setAttribute('aria-label','Review '+M.items[i].title+' on board');d.dataset.reviewId=sp.id;d.onkeydown=e=>{if(e.key==='Enter'||e.key===' '){e.preventDefault();open(i)}};d.onclick=()=>open(i);
if(s.favorite){const h=document.createElement('span');h.className='heart';h.textContent='♥';d.appendChild(h)}
if(s.status){const k=document.createElement('span');k.className='chip '+s.status;k.textContent=LBL[s.status];d.appendChild(k)}w.appendChild(d)})}
function open(i){if($('reviewModal').classList.contains('open')||!M.items[i]||(i!==cur&&!matches(M.items[i])))return;const opening=cur<0;if(opening)lightboxReturn=document.activeElement;cur=i;const it=M.items[i],s=st(it.id);$('lbimg').src=it.image;$('lbtitle').textContent=it.title;$('lbres').textContent=it.kind+' · '+it.resolution;swatches($('lbsw'),it.palette);$('lbcredit').textContent=it.credit?'Credit: '+it.credit:'';
$('lbtags').innerHTML='';it.tags.slice(0,12).forEach(t=>{const s2=document.createElement('span');s2.textContent=t;$('lbtags').appendChild(s2)});
$('lbnote').value=s.note||'';$('lbap').className='ap'+(s.status==='approved'?' on':'');$('lbch').className='ch'+(s.status==='changes'?' on':'');$('lbpick').className='pickbtn'+(s.favorite?' on':'');$('lbpick').setAttribute('aria-pressed',String(!!s.favorite));$('lbap').setAttribute('aria-pressed',String(s.status==='approved'));$('lbch').setAttribute('aria-pressed',String(s.status==='changes'));$('lbpick').textContent=s.favorite?'♥ Favorited':'♥ Favorite';$('lb').classList.add('open');overlays();if(opening)$('close').focus()}
function close(){const id=lightboxReturn?.dataset.reviewId,wasBoard=lightboxReturn?.classList.contains('spot');$('lb').classList.remove('open');cur=-1;render();overlays();const target=id?[...document.querySelectorAll(wasBoard?'#board [data-review-id]':'#grid [data-review-id]')].find(e=>e.dataset.reviewId===id):lightboxReturn;restoreFocus(target)}
function step(d){if(cur<0)return;const visible=queue();if(!visible.length){close();$('queueSearch').focus();return}const pos=visible.indexOf(cur);const next=pos>=0?visible[(pos+d+visible.length)%visible.length]:d>0?(visible.find(i=>i>cur)??visible[0]):([...visible].reverse().find(i=>i<cur)??visible[visible.length-1]);open(next)}
$('lbpick').onclick=()=>{const s=st(M.items[cur].id);s.favorite=!s.favorite;save();open(cur)};$('lbap').onclick=()=>{decide(M.items[cur].id,'approved');open(cur)};$('lbch').onclick=()=>{decide(M.items[cur].id,'changes');open(cur)};$('lbnote').oninput=e=>{st(M.items[cur].id).note=e.target.value;save()};
$('close').onclick=close;$('prev').onclick=()=>step(-1);$('next').onclick=()=>step(1);
$('onlyPicks').onclick=()=>{only=!only;$('onlyPicks').classList.toggle('on',only);$('onlyPicks').setAttribute('aria-pressed',String(only));render()};
document.addEventListener('keydown',e=>{const dialog=$('reviewModal').classList.contains('open')?$('reviewModal'):cur>=0?$('lb'):null;
if(dialog&&e.key==='Tab'){const controls=focusable(dialog),first=controls[0],last=controls[controls.length-1];if(e.shiftKey&&document.activeElement===first){e.preventDefault();last?.focus()}else if(!e.shiftKey&&document.activeElement===last){e.preventDefault();first?.focus()}return}
if($('reviewModal').classList.contains('open')){if(e.key==='Escape'&&['rename','blocked'].includes(modalKind)){e.preventDefault();closeReviewerModal()}else if(e.key==='Escape'&&modalKind==='switch'&&norm(S.reviewer)){e.preventDefault();closeReviewerModal()}return}
if(cur<0)return;if(e.key==='Escape'){e.preventDefault();close();return}if(['TEXTAREA','INPUT','SELECT'].includes(e.target.tagName)||e.ctrlKey||e.metaKey||e.altKey)return;
if(e.key==='ArrowRight'){e.preventDefault();step(1)}else if(e.key==='ArrowLeft'){e.preventDefault();step(-1)}else if(e.key==='f'){$('lbpick').click()}else if(e.key==='a'){$('lbap').click()}else if(e.key==='c'){$('lbch').click()}});
function downloadFeedback(){if($('reviewModal').classList.contains('open'))return;const who=S.reviewer.trim();if(!who){switchReviewer();return}put();const out={format:'asssets-review-feedback',gallery:M.gallery,title:M.title,reviewer:who,
items:M.items.map(it=>{const s=st(it.id),x={id:it.id,favorite:!!s.favorite,note:(s.note||'').trim()};if(s.status==='approved'||s.status==='changes')x.status=s.status;return x}).filter(x=>x.favorite||x.note||x.status)};
const a=document.createElement('a');a.href=URL.createObjectURL(new Blob([JSON.stringify(out,null,2)],{type:'application/json'}));
a.download=(M.title+' feedback'+(out.reviewer?' - '+out.reviewer:'')).replace(/[\/:\\]/g,'-')+'.json';document.body.appendChild(a);a.click();a.remove()}
$('download').onclick=downloadFeedback;
if(M.summary){const a=$('summary');a.href=encodeURI(M.summary);a.hidden=false}
if(M.credits&&M.credits.length){const b=$('creditsBtn');b.hidden=false;b.textContent='Credits ('+M.credits.length+')';
$('creditsSub').textContent='Images in this gallery by other people or agencies, and how they are licensed. Keep these credits with any use.';
M.credits.forEach(c=>{const r=document.createElement('div');r.className='cr';const a=document.createElement('b');a.textContent=c.credit;const l=document.createElement('div');l.className='lic';l.textContent=c.license;(c.files||[]).forEach(f=>{const e=document.createElement(f.href?'a':'div');e.className='lf';e.textContent='\u{1F4CE} '+f.name;if(f.href){e.href=f.href;e.target='_blank'}l.appendChild(e)});
const w=document.createElement('div');w.className='what';w.textContent=c.titles.join(', ');r.append(a,l,w);$('creditRows').appendChild(r)});
b.onclick=()=>{const on=$('credits').classList.toggle('on');b.classList.toggle('on',on);if(on)$('credits').scrollIntoView({behavior:'smooth'})};
if(q.get('demo')==='credits'){$('credits').classList.add('on');b.classList.add('on')}}
if(q.get('demo')==='approve-grid')M.board=null;render();if(storageProblem)notice(storageProblem);if(recoveryProblem){notice(recoveryProblem+' Stored data has not been replaced.');showRecovery()}else if(!norm(S.reviewer)&&!q.get('demo')&&!$('reviewModal').classList.contains('open'))switchReviewer();if(q.get('demo')==='lightbox')open(0);if(q.get('demo')==='approve')open(1);
</script></body></html>
"""#
}

extension StudioCatalog {
    public struct FeedbackResult: Equatable, Sendable {
        public var favorites = 0, notes = 0, unknown = 0, withdrawn = 0
        /// Prior notes removed outright or replaced by a different incoming note.
        public var notesRemoved = 0, notesReplaced = 0
        /// Board cards whose status the client's Approve / Request changes moved (1.23).
        public var statuses = 0
        /// Approve / Request changes decisions stored on assets, whether or not the gallery came from a board (1.84).
        public var decisions = 0
        public var smartCollection: UUID?
        /// The board the gallery was shared from, when the round was pinned onto it (1.20).
        public var board: UUID?
        public init() {}
    }

    /// Applies a client's feedback: favorites get "client-pick", notes are stored per reviewer and gallery.
    /// Re-importing the same reviewer's file for the same gallery replaces their earlier note and picks.
    @discardableResult
    public mutating func applyFeedback(_ f: ReviewGallery.Feedback, imported: String = "") -> FeedbackResult {
        var r = FeedbackResult()
        guard let roster = roster(for: f.gallery), roster.title == f.title else {
            r.unknown = f.items.count; return r
        }
        let scope = scopedFeedback(f)
        r.unknown = scope.skipped.count
        let scoped = scope.feedback
        // An outsider-only file is not an intentional withdrawal of a previous round.
        if !f.items.isEmpty && scoped.items.isEmpty { return r }
        let notePreview = previewFeedback(f)
        r.notesRemoved = notePreview.noteRemovals
        r.notesReplaced = notePreview.noteReplacements
        if !roster.recovered, let b = roster.board, let board = board(b) {
            // Board cards are mutable. If an asset now has several cards, an ID-only review
            // cannot tell which card was shared, so leave all its board effects alone.
            let allowed = Set(roster.cards.filter { card in
                board.items.filter { $0.kind == .asset && $0.assetID == card.asset }.count == 1 &&
                board.items.contains { $0.id == card.id && $0.assetID == card.asset }
            }.map(\.asset))
            let boardFeedback = ReviewGallery.Feedback(gallery: f.gallery, title: f.title, reviewer: f.reviewer,
                items: scoped.items.filter { UUID(uuidString: $0.id).map(allowed.contains) ?? false })
            r.statuses = previewFeedback(boardFeedback).statusChanges
            var pinned = false
            // A valid empty replacement clears this reviewer's round; an all-outside
            // board subset cannot erase it merely because card membership moved.
            if f.items.isEmpty || !boardFeedback.items.isEmpty {
                _ = updateBoard(b) { pinned = $0.recordReview(boardFeedback, imported: imported) }
            }
            if pinned { r.board = b }
        }
        let reviewer = feedbackDisplayReviewer(gallery: f.gallery, reviewer: f.reviewer)
        r.withdrawn = replaceFeedbackPicks(gallery: f.gallery, reviewer: reviewer,
            with: scoped.items.filter(\.favorite).compactMap { UUID(uuidString: $0.id) })
        let index = Dictionary(uniqueKeysWithValues: assets.enumerated().map { ($1.id.uuidString.uppercased(), $0) })
        // A replacement drops this reviewer's previous notes even when a formerly
        // shared asset is no longer present in the new feedback file.
        // A resolved tick survives a re-import only for a note whose text did not change.
        var resolvedBefore: [Int: Set<String>] = [:]
        for i in assets.indices {
            resolvedBefore[i] = Set(assets[i].clientNotes.filter { $0.resolved && Self.sameFeedbackRound($0.gallery, $0.reviewer, f.gallery, reviewer) }.map(\.text))
            assets[i].clientNotes.removeAll { Self.sameFeedbackRound($0.gallery, $0.reviewer, f.gallery, reviewer) }
        }
        for i in assets.indices {
            assets[i].clientDecisions.removeAll { Self.sameFeedbackRound($0.gallery, $0.reviewer, f.gallery, reviewer) }
        }
        for e in scoped.items {
            guard let i = index[e.id.uppercased()] else { r.unknown += 1; continue }
            if e.favorite {
                r.favorites += 1
            }
            if let status = e.cardStatus, status != .open {
                assets[i].clientDecisions.append(ClientDecision(reviewer: reviewer, gallery: f.gallery, status: status))
                r.decisions += 1
            }
            let text = FeedbackNoteText.saved(e.note)
            if !text.isEmpty { r.notes += 1; assets[i].clientNotes.append(ClientNote(reviewer: reviewer, text: text, gallery: f.gallery, resolved: resolvedBefore[i]?.contains(text) == true)) }
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
