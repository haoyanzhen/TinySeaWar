"""Experiment-only alpha crop; never writes formal character assets."""
import hashlib
import json
from pathlib import Path
from PIL import Image
ROOT = Path(__file__).resolve().parents[3]
OUT = ROOT / 'reports/art/20261009-far-view'

def sha(path): return hashlib.sha256(path.read_bytes()).hexdigest()

def main():
    entries = {}
    facts = []
    for name, rig_width in [('warspite',72),('yukikaze',52),('enterprise_cv6',76)]:
        path = OUT / 'source' / f'{name}.png'
        image = Image.open(path)
        assert image.mode == 'RGBA', (name, 'native alpha required')
        w,h = image.size
        alpha = image.getchannel('A')
        assert alpha.getextrema() == (0,255)
        # Authored two-object source: explicit left/right hints; fail on any crossing.
        assert alpha.crop((int(w*.46),0,int(w*.51),h)).getextrema()[1] <= 8, 'nonempty gutter'
        roles = {}
        for role,hint in [('body',(0,0,w//2,h)),('rig',(w//2,0,w,h))]:
            region = image.crop(hint)
            box = region.getchannel('A').point(lambda x: 255 if x > 8 else 0).getbbox()
            assert box and box[0]>0 and box[1]>0 and box[2]<region.width and box[3]<h, (name,role,'source touches edge')
            box=(max(0,box[0]-8),max(0,box[1]-8),min(region.width,box[2]+8),min(h,box[3]+8))
            crop=region.crop(box)
            # Add transparent padding without resampling, recoloring or alpha cleanup.
            pad=16
            final=Image.new('RGBA',(crop.width+pad*2,crop.height+pad*2))
            final.paste(crop,(pad,pad))
            target=OUT/'assets'/f'{name}_{role}.png'
            final.save(target)
            roles[role]={'path':str(target.relative_to(ROOT)), 'sha256':sha(target), 'alpha_rect':[pad,pad,crop.width,crop.height], 'size':list(final.size)}
            facts.append({'character':name,'role':role,'source_hint':hint,'crop_box_in_hint':box,'padding':pad,'retained_rgba_preserved':True,'bound_detection_alpha_threshold':8,'edge_expansion':8,'note':'Only near-transparent exterior speckles outside expanded bounds are omitted; source remains immutable'})
        ref=ROOT/f'assets/characters/{name}/processed/ui/{name}_ui_portrait.png'
        entries[name]={'roles':roles,'rig_width':rig_width,'reference':str(ref.relative_to(ROOT)),'reference_sha256':sha(ref),'source_sha256':sha(path)}
    manifest={'schema_version':1,'scope':'experiment_only','route':'Codex built-in ImageGen','actual_model':None,'request_id':None,'human_review':'pending','characters':entries,'crop_facts':facts,'prompts':'tools/art_review/far_view/prompts.json','prompt_sha256':sha(ROOT/'tools/art_review/far_view/prompts.json'),'rejected_sources':[{'path':'source/yukikaze_v1.png','reason':'two triple torpedo racks; corrected to two quadruple racks'}]}
    observed = ROOT/'tools/art_review/far_view/source_review.json'
    if observed.exists():
        notes=json.loads(observed.read_text())
        assert notes['style_anchor']['sha256']==sha(OUT/'source/warspite.png'), 'changed style anchor requires new source review'
        manifest.update(notes)
    (OUT/'manifest.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2)+'\n')
    print('PASS: 3 native-alpha sources, 6 separately cropped assets; human review pending')
if __name__=='__main__': main()
