"""Check scoped source/output integrity; never infer aesthetic acceptance."""
import hashlib,json
from pathlib import Path
from PIL import Image
ROOT=Path(__file__).resolve().parents[3]
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def main():
 roster=json.loads(Path(__file__).with_name('full_roster_inventory.json').read_text())
 result={'characters':0,'parts':0,'issues':[],'human_review':'pending'}
 for item in roster:
  id=item['id'];base=ROOT/'assets/characters'/id
  try:
   config=json.loads((base/'processed/config'/f'{id}_far_battle_config.json').read_text())
   revision=json.loads((base/'meta'/f'{id}_far_battle_revision.json').read_text())
   assert config['character_id']==id and revision['scope']=='battle_far_body_and_rig_only'
   assert sha(ROOT/revision['source'])==revision['source_sha256']==revision['source_review']['sha256']
   assert revision['source_review']['verdict']=='pass' and revision['legacy_package_migrated'] is False
   assert sha(ROOT/revision['reference'])==revision['reference_sha256']
   assert sha(ROOT/revision['style_reference']['path'])==revision['style_reference']['sha256']
   source=Image.open(ROOT/revision['source']);assert source.mode=='RGBA' and source.getchannel('A').getextrema()==(0,255)
   for role in ['body','rig']:
    entry=config['roles'][role];p=ROOT/entry['path'];assert sha(p)==entry['sha256']
    im=Image.open(p);assert im.mode=='RGBA' and list(im.size)==entry['size'] and im.getchannel('A').getextrema()==(0,255)
    x,y,w,h=entry['alpha_rect'];assert x>=0 and y>=0 and w>0 and h>0 and x+w<=im.width and y+h<=im.height
    a=im.getchannel('A').point(lambda p:255 if p>8 else 0);bb=a.getbbox();assert bb[0]>0 and bb[1]>0 and bb[2]<im.width and bb[3]<im.height
    assert x<=bb[0] and y<=bb[1] and x+w>=bb[2] and y+h>=bb[3]
    result['parts']+=1
   result['characters']+=1
  except (AssertionError,OSError,KeyError,ValueError) as ex:result['issues'].append(id+': '+repr(ex))
 assert len(roster)==48
 out=ROOT/'reports/art/20261009-far-view-all/asset_validation.json';out.parent.mkdir(parents=True,exist_ok=True);out.write_text(json.dumps(result,ensure_ascii=False,indent=2)+'\n')
 print(json.dumps(result,ensure_ascii=False));return 1 if result['issues'] else 0
if __name__=='__main__':raise SystemExit(main())
