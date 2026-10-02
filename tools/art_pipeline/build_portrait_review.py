"""Build source-backed portrait QA previews and an exact 48-character coverage report."""
from pathlib import Path
import html
import json
import os

from PIL import Image, ImageDraw

import character_roster
import portrait_revision as portraits

ROOT = portraits.ROOT
OUT = ROOT / "reports/portraits/20261001-unframed"


def checker(size):
    image = Image.new("RGB",size,"#e9eef0")
    draw = ImageDraw.Draw(image)
    for y in range(0,size[1],16):
        for x in range(0,size[0],16):
            if (x//16+y//16)%2: draw.rectangle((x,y,x+15,y+15),fill="#bdcbd0")
    return image


def paste_fit(canvas, path, rect):
    with Image.open(path) as opened: image=opened.convert("RGBA")
    x,y,w,h=rect
    image.thumbnail((w,h),Image.Resampling.LANCZOS)
    canvas.paste(image,(x+(w-image.width)//2,y+(h-image.height)//2),image)


def main():
    OUT.mkdir(parents=True,exist_ok=True)
    ids=sorted(character_roster.roster_by_id("all"))
    rows=[]
    for cid in ids:
        source,meta=portraits.locations(ROOT,cid)
        rows.append({"character_id":cid,"generated":source.exists() and meta.exists(),
                     "issues":portraits.validate_revision(ROOT,cid) if meta.exists() else ["portrait revision missing"]})
    (OUT/"coverage.json").write_text(json.dumps({"expected":len(ids),"generated":sum(x['generated'] for x in rows),
        "accepted":sum(not x['issues'] for x in rows),"characters":rows},ensure_ascii=False,indent=2)+"\n")
    for page,start in enumerate(range(0,len(ids),16),1):
        subset=ids[start:start+16]
        for background,color in [("light","#dce9ee"),("dark","#172c3b"),("checker",None)]:
            canvas=checker((1440,960)) if color is None else Image.new("RGB",(1440,960),color)
            draw=ImageDraw.Draw(canvas)
            for n,cid in enumerate(subset):
                x=n%4*360;y=n//4*240
                base=ROOT/"assets/characters"/cid/"processed/ui"
                paste_fit(canvas,base/f"{cid}_ui_portrait.png",(x+5,y+5,200,200))
                paste_fit(canvas,base/f"{cid}_ui_portrait_small.png",(x+215,y+15,128,128))
                paste_fit(canvas,base/f"{cid}_ui_portrait_small.png",(x+235,y+160,40,40))
                draw.text((x+12,y+215),cid,fill="#ffffff" if background=="dark" else "#203748")
            canvas.save(OUT/f"{background}-{page}.png")
        comparison=Image.new("RGB",(1440,960),"#dce9ee");draw=ImageDraw.Draw(comparison)
        for n,cid in enumerate(subset):
            x=n%4*360;y=n//4*240
            before=OUT/"before"/f"{cid}_ui_portrait.png"
            if before.exists(): paste_fit(comparison,before,(x,y,175,195))
            paste_fit(comparison,ROOT/"assets/characters"/cid/"processed/ui"/f"{cid}_ui_portrait.png",(x+180,y,175,195))
            draw.text((x+8,y+205),cid+"  before / after",fill="#203748")
        comparison.save(OUT/f"comparison-{page}.png")
    overview=Image.new("RGB",(1600,1200),"#172c3b");draw=ImageDraw.Draw(overview)
    for n,cid in enumerate(ids):
        x=n%8*200;y=n//8*200
        paste_fit(overview,ROOT/"assets/characters"/cid/"processed/ui"/f"{cid}_ui_portrait.png",(x,y,200,175))
        draw.text((x+8,y+180),cid,fill="white")
    overview.save(OUT/"overview.png")
    samples=Image.new("RGB",(1600,420),"#dce9ee");draw=ImageDraw.Draw(samples)
    for n,cid in enumerate(("warspite","hai_shih","akizuki","belfast")):
        paste_fit(samples,ROOT/"assets/characters"/cid/"processed/ui"/f"{cid}_ui_portrait.png",(n*400,0,400,380))
        draw.text((n*400+20,392),cid,fill="#203748")
    samples.save(OUT/"samples.png")
    cards=[]
    for row in rows:
        cid=row['character_id'];base=ROOT/"assets/characters"/cid/"processed/ui"
        urls={k:html.escape(os.path.relpath(base/f"{cid}_{k}.png",OUT)) for k in portraits.SIZES}
        cards.append(f'<article data-id="{cid}"><h2>{cid}</h2><div class="images"><div><small>旧头像</small><img width="128" height="128" src="before/{cid}_ui_portrait.png"></div><div><small>新头像128px</small><img width="128" height="128" src="{urls["ui_portrait_small"]}"></div><div><small>战斗40px</small><img width="40" height="40" src="{urls["ui_portrait_small"]}"></div></div><details><summary>512px与检查结果</summary><img width="300" height="300" src="{urls["ui_portrait"]}"><pre>{html.escape(json.dumps(row,ensure_ascii=False,indent=2))}</pre></details></article>')
    page='''<!doctype html><html lang="zh"><meta charset="utf-8"><title>TinySeaWar 无框头像全量审查</title><style>
    body{font:15px system-ui;background:#dce9ee;color:#203748;margin:24px}header{position:sticky;top:0;padding:12px;background:#f6fafbee;border-radius:12px;z-index:1}h1{font-size:24px}button,input{padding:8px;margin:4px}main{display:grid;grid-template-columns:repeat(auto-fit,minmax(350px,1fr));gap:16px;margin-top:20px}article{border:1px solid #7e9ba8;padding:12px;border-radius:12px}.images{display:flex;gap:12px;align-items:center}small{display:block}img{object-fit:contain}body.dark article{background:#172c3b;color:white}body.checker article{background:repeating-conic-gradient(#e9eef0 0% 25%,#bdcbd0 0% 50%) 0/24px 24px}h2{font-size:17px}pre{white-space:pre-wrap}</style><header><h1>48名舰娘 · 透明无框头像</h1><p>原图、128px与战斗40px对照。头像修订审查独立于完整角色包验收。</p><button onclick="document.body.className=''">浅底</button><button onclick="document.body.className='dark'">深底</button><button onclick="document.body.className='checker'">棋盘底</button><input placeholder="按角色ID筛选" oninput="document.querySelectorAll('article').forEach(x=>x.hidden=!x.dataset.id.includes(this.value.toLowerCase()))"></header><main>'''+''.join(cards)+'</main></html>'
    previews='<nav><a href="overview.png">全量总览</a> · <a href="samples.png">四张样本</a> · <a href="validation.md">验证记录</a><br>'
    for kind,label in (("dark","深底"),("light","浅底"),("checker","棋盘底"),("comparison","前后对照")):
        previews+=label+' '+ ' '.join(f'<a href="{kind}-{n}.png">{n}</a>' for n in range(1,4))+' · '
    previews+='<details><summary>1080p／1440p实际界面</summary>'
    for name in ("t08","s04","m05","l05","custom","hud","skill-hints"):
        previews+=name+' '+ ' '.join(f'<a href="ui/{name}-{height}.png">{height}p</a>' for height in (1080,1440))+'<br>'
    previews+='</details></nav>'
    page=page.replace('</header>',previews+'</header>')
    (OUT/"index.html").write_text(page)
    print(json.dumps({"expected":len(ids),"generated":sum(x['generated'] for x in rows),"accepted":sum(not x['issues'] for x in rows)}))


if __name__ == "__main__": main()
