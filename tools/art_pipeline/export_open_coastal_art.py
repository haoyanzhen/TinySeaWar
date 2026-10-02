#!/usr/bin/env python3
"""Export reviewed ImageGen terrain sprites into the existing source/runtime contract.

Only size and canvas placement are normalized; generated colors and alpha are
retained. Rule polygons remain independently authored and are never traced here.
"""
from pathlib import Path
import argparse,json,hashlib,shutil
from PIL import Image,ImageDraw,ImageFont
ROOT=Path(__file__).resolve().parents[2]
LAND=ROOT/'assets/environment/land'
NAMES={'scattered_islands':'散岛群','broken_atoll':'破碎环礁','central_sandbar':'中央沙洲','crescent_bay':'新月湾','offset_large_island':'偏置大岛','long_archipelago':'长岛链','dual_channel_reef_line':'双航道礁线','ring_lagoon':'环形泻湖','harbor_mouth':'港口入口','double_island_long_channel':'双岛长水道'}
def main():
 ap=argparse.ArgumentParser();ap.add_argument('--sources',default=str(LAND/'source/open_coasts_v1/input_manifest.json'));args=ap.parse_args()
 sources=json.loads(Path(args.sources).read_text());layouts={t['id'].split('.')[-1].removesuffix('_16x9'):t for t in json.loads((LAND/'source/open_coasts_v1/layout_reference.json').read_text())['definitions']}
 out=LAND/'source/open_coasts_v1';out.mkdir(exist_ok=True)
 manifest={'revision':'open_coasts_v1','tool':'built-in imagegen','export':'size and canvas placement only; original generated alpha retained','assets':[]}
 sheet=Image.new('RGB',(1280,5*398),(20,52,65));sd=ImageDraw.Draw(sheet);font=ImageFont.truetype('/System/Library/Fonts/STHeiti Light.ttc',21)
 for i,item in enumerate(sources):
  name=item['name'];src=Path(item['path']);src=src if src.is_absolute() else ROOT/src;raw=out/f'land_{name}_generated.png'
  if src.resolve()!=raw.resolve():shutil.copyfile(src,raw)
  im=Image.open(raw).convert('RGBA');assert im.getchannel('A').getextrema()==(0,255)
  bbox=im.getchannel('A').point(lambda v:255 if v>128 else 0).getbbox()
  points=[p for o in layouts[name]['obstacles'] for p in o['polygon']];target=[min(p[0] for p in points),min(p[1] for p in points),max(p[0] for p in points),max(p[1] for p in points)]
  # Registration of the generated composition to the authored bounding box,
  # retaining all antialiased edge pixels (no replacement polygon alpha).
  sx=(target[2]-target[0])*2/(bbox[2]-bbox[0]);sy=(target[3]-target[1])*2/(bbox[3]-bbox[1]);w,h=round(im.width*sx),round(im.height*sy)
  offset=(round(target[0]*2-bbox[0]*sx),round(target[1]*2-bbox[1]*sy))
  canvas=Image.new('RGBA',(3840,2160));canvas.alpha_composite(im.resize((w,h),Image.Resampling.LANCZOS),offset)
  master=LAND/'source'/f'land_{name}_source.png';runtime=LAND/f'land_{name}_16x9_runtime.png'
  canvas.save(master);canvas.resize((1920,1080),Image.Resampling.LANCZOS).save(runtime)
  manifest['assets'].append({'id':name,'generated':str(raw.relative_to(ROOT)),'generated_sha256':hashlib.sha256(raw.read_bytes()).hexdigest(),'source_master':str(master.relative_to(ROOT)),'runtime':str(runtime.relative_to(ROOT)),'registration_scale':[sx,sy],'registration_offset':offset,'prompt':'Authoritative layout reference with exact island count, position, silhouette and open water; existing low-saturation illustrated rocky olive islands as style only; transparent background, no extra rocks, text, buildings or water.'})
  thumb=canvas.resize((640,360),Image.Resampling.LANCZOS);x=(i%2)*640;y=(i//2)*398;sheet.paste(thumb,(x,y+36),thumb);sd.text((x+12,y+7),NAMES[name]+(' · 窄路特色' if name in ['harbor_mouth','double_island_long_channel'] else ' · 开放机动'),font=font,fill='white')
 (out/'manifest.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2)+'\n')
 qa=ROOT/'reports/terrain/20261002-open-coasts';qa.mkdir(parents=True,exist_ok=True);sheet.save(qa/'art_contact_sheet.png');sheet.save(ROOT/'assets/environment/qa/coastal_maps_16x9_contact_sheet.png')
if __name__=='__main__':main()
