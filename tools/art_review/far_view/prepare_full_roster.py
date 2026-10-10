"""56px battle-only revision; shared source-aware extraction, immutable legacy packs."""
import hashlib, json, shutil, sys
from pathlib import Path
from PIL import Image
ROOT=Path(__file__).resolve().parents[3]
sys.path.insert(0,str(ROOT/'tools/art_pipeline'))
from postprocess_trial_sheets import prepare_crop
from generation_contract import image_facts
from delivery_review import write_review
RAW=ROOT/'artifacts/art_pipeline/raw/far56_20261009'
OUT=ROOT/'reports/art/20261009-far-view-all'
QA=Path(__file__).with_name('full_roster_review.json')
def sha(p): return hashlib.sha256(p.read_bytes()).hexdigest()
def dump(p,obj): p.parent.mkdir(parents=True,exist_ok=True);p.write_text(json.dumps(obj,ensure_ascii=False,indent=2)+'\n')
def main():
    review=json.loads(QA.read_text()); roster=json.loads(Path(__file__).with_name('full_roster_inventory.json').read_text())
    prompts=json.loads(Path(__file__).with_name('full_roster_prompts.json').read_text())
    corrections=json.loads(Path(__file__).with_name('full_roster_corrections.json').read_text())
    pilot_prompts=json.loads(Path(__file__).with_name('prompts.json').read_text())
    entries={}; issues=[]
    weapons=[entry for path in sorted((ROOT/'data/visuals').glob('*weapon_visuals.json')) for entry in json.loads(path.read_text())['definitions']]
    for item in roster:
        id=item['id']; q=review.get(id,{})
        if q.get('verdict')!='pass': issues.append(id+': pending source review'); continue
        base=ROOT/'assets/characters'/id; target=base/'battle'/f'{id}_far_battle_sheet.png'
        src=ROOT/q['source']
        if not src.exists(): src=target
        assert sha(src)==q['sha256'],id+' review stale'
        img=Image.open(src); assert img.mode=='RGBA' and img.getchannel('A').getextrema()==(0,255),id
        a=img.getchannel('A').point(lambda p:255 if p>8 else 0); w,h=img.size
        # Find an actual transparent gutter; this is not a fixed-grid crop.
        empty=[x for x in range(int(w*.35),int(w*.65)) if a.crop((x,0,x+1,h)).getbbox() is None]
        groups=[]
        for x in empty:
            if not groups or x>groups[-1][-1]+1: groups.append([])
            groups[-1].append(x)
        assert groups,id+' no gutter'
        gap=max(groups,key=len); assert len(gap)>=16,id+' narrow gutter'
        split=(gap[0]+gap[-1])//2
        target.parent.mkdir(parents=True,exist_ok=True)
        if src.resolve()!=target.resolve(): shutil.copyfile(src,target)
        roles={}; outputs=[]; specs=[]
        for role,hint in [('body',(0,0,split,h)),('rig',(split,0,w,h))]:
            bb=a.crop(hint).getbbox();assert bb,id+role
            assert bb[0]>0 and bb[1]>0 and bb[2]<hint[2]-hint[0] and bb[3]<h,id+role+' truncated'
            # Explicit component hint contains the complete selected object.
            crop,meta=prepare_crop(img,hint)
            dest=base/'processed/battle'/f'{id}_battle_far_{role}.png';crop.save(dest)
            bound=crop.getchannel('A').point(lambda p:255 if p>8 else 0).getbbox()
            # 4px safety band retains feather edges but excludes balanced-layout padding.
            x0,y0,x1,y1=bound;x0=max(0,x0-4);y0=max(0,y0-4);x1=min(crop.width,x1+4);y1=min(crop.height,y1+4)
            roles[role]={'path':str(dest.relative_to(ROOT)),'sha256':sha(dest),'alpha_rect':[x0,y0,x1-x0,y1-y0],'size':list(crop.size)}
            outputs.append({'path':str(dest.relative_to(ROOT)),'sha256':sha(dest),'crop':meta})
            specs.append({'role':role,'source':str(target.relative_to(ROOT)),'source_sha256':sha(target),'hint':list(hint),'crop':meta})
        anchors={}
        for v in weapons:
            if v.get('character_id')==id:
                name=v.get('launch_bind','')
                if name: anchors[name]=([0,0] if name=='unit_center' else ([.42,0] if 'muzzle' in name else ([.2,.12] if 'torpedo' in name else [0,0])))
        width={'Destroyer':52,'LightCruiser':60,'HeavyCruiser':66,'Battleship':72,'AircraftCarrier':76,'Carrier':76,'Submarine':50}.get(item['class'],60)
        config={'schema_version':1,'character_id':id,'body_basis':'upright','rig_heading_degrees':0,'rig_width':width,'roles':roles,'anchors':anchors,'animation':'procedural_far_view'}
        dump(base/'processed/config'/f'{id}_far_battle_config.json',config)
        dump(base/'meta'/f'{id}_far_battle_crop_specs.json',{'schema_version':1,'scope':'battle_far_only','components':specs})
        ref=ROOT/f'assets/characters/{id}/processed/ui/{id}_ui_portrait.png'
        prompt=next((p.get('prompt') for p in prompts if p['id']==id),pilot_prompts.get(id))
        revision={'schema_version':2,'scope':'battle_far_body_and_rig_only','character_id':id,'route':'codex_builtin_imagegen','requested_model':None,'actual_model':None,'request_id':None,'endpoint':'Codex managed; not exposed','background':'transparent','output_format':'png','quality':'tool-managed','source':str(target.relative_to(ROOT)),'source_sha256':sha(target),'alpha_facts':image_facts(target),'reference':str(ref.relative_to(ROOT)),'reference_sha256':sha(ref),'prompt':prompt,'source_review':q,'human_review':'56px style adopted; new per-character full-roster review pending','outputs':outputs,'legacy_package_migrated':False}
        revision['correction_history']=[item for batch in corrections.values() for item in batch if item['id']==id]
        anchor=ROOT/'assets/characters/warspite/battle/warspite_far_battle_sheet.png'
        if not anchor.exists(): anchor=ROOT/'reports/art/20261009-far-view/source/warspite.png'
        revision['style_reference']={'path':'assets/characters/warspite/battle/warspite_far_battle_sheet.png','sha256':sha(anchor)}
        dump(base/'meta'/f'{id}_far_battle_revision.json',revision)
        # Existing review machinery initializes changed outputs as pending.
        review_path=base/'processed/config'/f'{id}_delivery_review.json'
        previous=json.loads(review_path.read_text()) if review_path.exists() else {}
        write_review(ROOT,id,{'outputs':outputs})
        # Keep old crop evidence even when the package-wide approval is invalidated.
        refreshed=json.loads(review_path.read_text())
        for filename,entry in refreshed['assets'].items():
            if not entry['crop_evidence']:
                entry['crop_evidence']=previous.get('assets',{}).get(filename,{}).get('crop_evidence',{})
        dump(review_path,refreshed)
        entries[id]={'name':item['name'],'class':item['class'],**config}
    dump(OUT/'manifest.json',{'schema_version':1,'characters':entries,'pending':issues})
    print(f'Prepared {len(entries)}/48 battle revisions; {len(issues)} pending')
if __name__=='__main__':main()
