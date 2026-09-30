"""Validate downloaded candidates and render a local, exportable listening page."""
import argparse, collections, concurrent.futures, hashlib, html, json, subprocess
from pathlib import Path

def sha(path): return hashlib.sha256(path.read_bytes()).hexdigest()
def measure(path):
    p=subprocess.run(['ffmpeg','-hide_banner','-nostats','-i',str(path),'-af','ebur128=peak=true','-f','null','-'],capture_output=True,text=True,check=True)
    return p.stderr.split('Summary:')[-1].strip()
def main():
    p=argparse.ArgumentParser();p.add_argument('output',type=Path);p.add_argument('--measure',action='store_true');a=p.parse_args()
    batch=json.loads((a.output/'batch.json').read_text()); records={}; missing=[]; hashes=[]; cards=[]
    measurements_path=a.output/'loudness.json'
    measurements=json.loads(measurements_path.read_text()) if measurements_path.exists() else {}
    pending=[]
    for asset in batch['assets']:
        for candidate in asset['candidates']:
            id_=candidate['id']; state=a.output/asset['category']/(id_+'.json')
            if not state.exists(): missing.append(id_);continue
            r=json.loads(state.read_text())
            if r.get('status')!='generated':missing.append(id_);continue
            assert r['seed']==candidate['seed']
            for kind in ('raw','preview'):
                f=a.output/r[kind]['path']; assert f.is_file() and sha(f)==r[kind]['sha256'],str(f)
            hashes.append(r['preview']['sha256']);records[id_]=r
            if a.measure and measurements.get(id_,{}).get('sha256')!=r['preview']['sha256']:pending.append((id_,r))
    if pending:
        with concurrent.futures.ThreadPoolExecutor(max_workers=4) as pool:
            results=pool.map(lambda item:(item[0],measure(a.output/item[1]['preview']['path'])),pending)
            for id_,result in results:measurements[id_]=dict(sha256=records[id_]['preview']['sha256'],ffmpeg_ebur128=result)
        measurements_path.write_text(json.dumps(measurements,ensure_ascii=False,indent=2)+'\n')
    assert len(hashes)==len(set(hashes)),'Duplicated audio candidates'
    categories=collections.Counter(x['category'] for x in batch['assets'])
    summary=dict(requirements=len(batch['requirements']),assets=len(batch['assets']),expected=len(batch['assets'])*3,
        generated=len(records),missing=missing,unique_preview_hashes=len(set(hashes)),categories=dict(categories),
        long_candidates=[id_ for id_,r in records.items() if r['duration_review_required']],
        source_overrange=[id_ for id_,r in records.items() if r['source_clipped_samples']],
        peak_warnings=[id_ for id_,r in records.items() if r['true_peak_4x_dbfs']>-1],
        human_review='pending',runtime_integration='not_started',batch_sha256=sha(a.output/'batch.json'))
    (a.output/'validation.json').write_text(json.dumps(summary,ensure_ascii=False,indent=2)+'\n')
    labels={'weapon':'武器','impact':'命中/舰体','water':'破水/航行','aviation':'航空','submarine':'潜艇','skill':'技能','alert':'战术提示','ambience':'环境','facility':'设施','ui':'UI'}
    for asset in batch['assets']:
        uses=[r['id'] for r in batch['requirements'] if asset['id'] in r['assets']]
        takes=[]
        for candidate in asset['candidates']:
            id_=candidate['id'];r=records.get(id_)
            if r:
                warning=('时长超过设计目标，待剪辑/返工。' if r['duration_review_required'] else '')+('源浮点峰值偏高，待实听复查。' if r['source_clipped_samples'] else '')
                take=f'<audio controls preload="none" {"loop" if asset["loop"] else ""} src="{r["preview"]["path"]}"></audio><small>{r["duration_seconds"]:.2f}s · 48kHz · {r["channels"]}声道 · 峰值 {r["true_peak_4x_dbfs"]:.1f}dBTP（4×）</small><p class="warn">{warning}</p><a href="{r["raw"]["path"]}">原始 WAV</a>'
            else:take='<p>尚未生成</p>'
            takes.append(f'<div class="take"><b>{id_} · {candidate["variation"]}</b>{take}</div>')
        cards.append(f'<section data-category="{asset["category"]}" data-search="{html.escape(asset["title"]+" "+asset["id"]+" "+" ".join(uses))}"><h2>{asset["id"]} · {asset["title"]}</h2><p>{labels[asset["category"]]} · 工单 {", ".join(uses)} · 目标 {asset["target_seconds"]}s · {"循环，试听三轮" if asset["loop"] else "单次"}</p><p>{asset["direction"]}</p><div class="takes">{"".join(takes)}</div><div class="feedback" data-id="{asset["id"]}"><label>偏好 <select><option value="">待评审</option><option>A</option><option>B</option><option>C</option><option>全部返工</option></select></label><input placeholder="听感意见、问题时间点" aria-label="{asset["title"]}听感意见"></div></section>')
    ref_path=a.output/'references.json'
    reference_html=''
    if ref_path.exists():
        refs=json.loads(ref_path.read_text())
        reference_html='<section><h2>已选小样参考（不计入本批候选）</h2><div class="takes">'+''.join('<div class="take"><b>'+html.escape(r['title'])+'</b><audio controls preload="none" src="'+html.escape(r['path'],quote=True)+'"></audio></div>' for r in refs)+'</div></section>'
    payload=json.dumps(dict(batch_id=batch['id'],batch_sha256=summary['batch_sha256'],audio_hashes={id_:r['preview']['sha256'] for id_,r in records.items()}),ensure_ascii=False)
    page='''<!doctype html><html lang="zh-CN"><meta charset="utf-8"><meta name="viewport" content="width=device-width"><title>Tiny Sea War 音效候选</title><style>
body{font:16px/1.6 system-ui;background:#0c202c;color:#e8edef;margin:0}header,main{max-width:1380px;margin:auto;padding:24px}header{position:sticky;top:0;background:#102b38;z-index:2;border-bottom:1px solid #c4a86a}h1{margin:0;font-size:26px}h2{font-size:19px;color:#ecd8a3;margin:0}section{background:#173440;border:1px solid #375660;border-radius:12px;margin-bottom:20px;padding:22px}.takes{display:grid;grid-template-columns:repeat(3,1fr);gap:18px}.take{background:#102934;padding:14px;border-radius:8px}audio{display:block;width:100%;margin:12px 0}small{display:block;color:#aac4cc}a{color:#b5dfed}.warn{color:#f2bf87;font-size:13px}input,select,button{background:#ecf2ef;color:#142b36;border:0;border-radius:6px;padding:9px;margin:6px}input{min-width:240px}.feedback input{width:60%}p{margin:6px 0 12px}@media(max-width:800px){.takes{grid-template-columns:1fr}header{position:static}.feedback input{width:85%}}
</style><header><h1>Tiny Sea War · 音效三候选试听</h1><p>COUNT · GPU Stable Audio 3 Small SFX · 人工听感待评审 · 尚未接入游戏。环境素材默认循环；一次只播放一条。</p><input id="q" placeholder="搜索名称或工单 ID"><select id="cat"><option value="">全部分类</option>OPTIONS</select><button id="export">导出试听意见</button><span id="visible"></span></header><main>CARDS</main><script>
const meta=PAYLOAD, key='tsw-sfx-'+meta.batch_sha256;let feedback={};try{feedback=JSON.parse(localStorage.getItem(key)||'{}')}catch(e){}
const sections=[...document.querySelectorAll('section[data-category]')];function filter(){let n=0;for(const s of sections){s.hidden=!!((cat.value&&s.dataset.category!==cat.value)||(q.value&&!s.dataset.search.toLowerCase().includes(q.value.toLowerCase())));if(!s.hidden)n++}document.querySelector('#visible').textContent=n+' 个条目'}
const q=document.querySelector('#q'),cat=document.querySelector('#cat');q.oninput=cat.onchange=filter;filter();
document.addEventListener('play',e=>{if(e.target.tagName==='AUDIO')document.querySelectorAll('audio').forEach(x=>{if(x!==e.target)x.pause()})},true);
document.querySelectorAll('.feedback').forEach(el=>{let id=el.dataset.id,s=el.querySelector('select'),i=el.querySelector('input');s.value=feedback[id]?.choice||'';i.value=feedback[id]?.notes||'';s.onchange=i.oninput=()=>{feedback[id]={choice:s.value,notes:i.value,reviewed_at:new Date().toISOString()};try{localStorage.setItem(key,JSON.stringify(feedback))}catch(e){alert('浏览器存储不可用，请立即导出意见')}}});
document.querySelector('#export').onclick=()=>{let blob=new Blob([JSON.stringify({...meta,feedback},null,2)],{type:'application/json'}),url=URL.createObjectURL(blob),a=document.createElement('a');a.href=url;a.download=meta.batch_id+'.review.json';a.click();setTimeout(()=>URL.revokeObjectURL(url),1000)};
</script></html>'''
    page=page.replace('COUNT',f'{len(records)}/{summary["expected"]} 候选').replace('OPTIONS',''.join(f'<option value="{k}">{v}</option>' for k,v in labels.items())).replace('CARDS',reference_html+''.join(cards)).replace('PAYLOAD',payload)
    (a.output/'listen.html').write_text(page)
    print(json.dumps({k:v for k,v in summary.items() if k not in ('long_candidates','source_overrange')},ensure_ascii=False))
if __name__=='__main__': main()
