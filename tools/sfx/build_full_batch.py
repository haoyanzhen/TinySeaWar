"""Build a new, review-informed full batch without mutating pilot manifests."""
import json,copy,argparse,math
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]
def main():
 parser=argparse.ArgumentParser();parser.add_argument('--integer-durations',action='store_true');args=parser.parse_args()
 b=json.loads((ROOT/'tools/sfx/batch_20260930.json').read_text())
 b.update(id='sfx_full_20260930_v2',status='planned',runtime='modelscope-runtime/ComfyUI',parent_batches=['sfx_pilot5_20260930_v1','sfx_revision2_20260930_v1'],retained_preferences={'W03':'sfx_pilot5_20260930_v1/W03_c','U01':'sfx_pilot5_20260930_v1/U01_a','W14':'sfx_revision2_20260930_v1/W14_r2_a'},cancelled=['N04'])
 b['assets']=[a for a in b['assets'] if a['id']!='N04']
 for r in b['requirements']:
  if r['id']=='N04':r.update(assets=[],status='cancelled_by_user',reason='用户试听后取消鱼雷危险预警声音，保留视觉信息')
 styles={
 'weapon':('Compact stylized naval combat game effect, convincing weight, crisp readable mechanical action and a restrained decay.','清楚短促|A dry precise close transient with clean mechanical detail.','厚实紧凑|A warm fuller body, firm weight and compact low end.','圆润耐听|A rounded transient and gentler treble for repeated playback.'),
 'impact':('Stylized anime naval battle game impact, believable material and water, controlled bass, concise natural decay.','集中冲击|A concentrated compact impact and clear material detail.','低沉厚实|A deeper warmer body and a short restrained tail.','圆润克制|A softer rounded impact retaining clear weight.'),
 'water':('A small agile ship rig gliding at the water surface, delicate believable water movement for a naval game.','清晰水纹|Clean close water detail with restrained fine spray.','柔和水流|Warm flowing water with slow smooth motion.','轻盈破水|Airy rounded water movement, no harsh hiss.'),
 'aviation':('Compact propeller aircraft sound for an anime naval tactics game, clear mechanical detail without an overwhelming engine wall.','清晰机体|Clear controlled mechanical detail.','温暖机声|Warmer fuller engine texture at restrained intensity.','柔和航行|Rounded smoother engine and airflow texture.'),
 'submarine':('Readable submarine equipment and water sound for a naval game, distinct short phases, restrained intensity.','清晰过程|Clean precise mechanical and water detail.','沉稳水感|Warmer softer submerged water texture.','轻柔收束|Gentler rounded edges and a short finish.'),
 'skill':('A short elegant anime naval tactical ability sound, subtle polished metal and luminous electronic accents. A concise sound effect, not a magical combat explosion or a musical phrase.','珐琅机械|Delicate polished metallic detail with a tiny warm electronic accent.','清亮战术|A clear luminous electronic gesture, rounded and concise.','柔和舰装|Soft airy movement with restrained mechanical detail.'),
 'alert':('A short readable naval tactical interface signal, rounded midrange frequencies and a distinctive rhythmic identity. Restrained and comfortable, not a loud siren or a melody.','清楚节奏|Dry concise midrange tones with clearly separated pulses.','温暖提示|Warm lower midrange tones preserving the requested rhythm.','柔亮提示|Gently brighter rounded tones with a restrained finish.'),
 'ui':('A refined anime naval strategy interface sound, light enamel and brushed metal touch with a subtle warm electronic accent. Very short, comfortable and readable on repeated clicks.','珐琅轻点|Dry delicate enamel tap with a precise finish.','舰装拨片|Subtle warm brushed metal detail, compact and soft.','柔亮触点|A tiny rounded luminous electronic accent, light and brief.'),
 'facility':('A small naval support facility sound, precise light machinery, restrained tools and subtle tactical confirmation. Compact and readable.','精密机械|Clean dry fine mechanical detail.','温暖金属|Warmer small metal and motor texture.','轻柔设备|Softer rounded tool and mechanical detail.'),
 'ambience':('Natural wide-band maritime ambience with open spacious air and gentle dynamics, clean water and weather texture, no telephone or radio filtering.','宽阔自然|Open spacious natural texture with slow smooth variation.','柔和背景|Soft distant even texture, subtle movement, no sharp foreground sounds.','细腻平稳|Delicate full bandwidth detail and stable restrained energy.')}
 sea=['Soft broad slow swells on the open sea, gently rising and sinking water with smooth rolling wash. Offshore ocean ambience, wide spacious natural sound, calm and mellow, no close beach fizz or breaking surf. Only water, no birds, animals, chirps, boats, voices or music.',
 'Quiet open ocean water, long gentle swells moving slowly underneath a light smooth wash of small waves. A broad relaxed rolling water bed, natural airy bandwidth, no narrow muffled recording. Offshore rather than a beach, no birds, chirps, people, engines or music.',
 'Peaceful offshore sea with softly undulating broad waves and a delicate continuous wash, slow rounded wave cycles and a spacious open horizon. Natural smooth water texture without crashing or sharp droplets. No wildlife, birds, voices, radio effects or music.']
 w14='One deep underwater explosion heard entirely from below the water surface. A rounded powerful sub bass pressure thump, heavily muffled dark rumbling and a brief dense bubble collapse. Short natural decay into silence. No surface splash, metallic crack, music or speech.'
 request=dict(purpose='full_game_sfx_candidates',batch_id=b['id'],sounds=[])
 for i,a in enumerate(b['assets']):
  cat=a['category'];base,*variations=styles[cat]
  a['generation_seconds']=a['target_seconds'] if a['loop'] else (1 if cat=='ui' else (1.5 if cat in ('skill','alert') else max(2,min(4,a['target_seconds']+1))))
  a['review_target_rms_dbfs']=(-34 if a['id']=='E01' else -30) if a['loop'] else (-24 if cat in ('skill','ui') else -23)
  for j,c in enumerate(a['candidates']):
   label,style=variations[j].split('|')
   prompt=a['english_brief']+'. '+base+' '+style
   if a['id']=='W14':prompt=w14+' '+style
   if a['id']=='E01':prompt=sea[j]
   prompt+=(' Continuous even background texture with no isolated foreground events.' if a['loop'] else ' One compact isolated effect, complete decay then silence, no repetition.')
   prompt+=' No speech, no vocals, no music.'
   c.update(id=f"{a['id']}_full_{'abc'[j]}",seed=202609306000+i*10+j,variation=label,prompt=prompt,status='planned')
   # Only the approved underwater family has a deliberate low-pass texture.
   if a['id']=='W14':c['lowpass_hz']=[650,850,1000][j]
   request['sounds'].append(dict(id=c['id'],prompt=prompt,seconds=a['generation_seconds'],seed=c['seed']))
 assert len(b['assets'])==121 and len(request['sounds'])==363
 assert len({c['seed'] for c in request['sounds']})==363
 assert all(x in {a['id'] for a in b['assets']} for r in b['requirements'] for x in r['assets'])
 version='v2'
 if args.integer_durations:
  version='v3';b['id']='sfx_full_20260930_v3';b['supersedes_attempt']='sfx_full_20260930_v2';b['duration_note']='Use integer source durations after W02 2.1s nonfinite output; same prompt/seed 3s probe succeeded. Does not prove a universal fractional-duration defect.'
  request['batch_id']=b['id']
  for a in b['assets']:a['generation_seconds']=math.ceil(a['generation_seconds'])
  for c in request['sounds']:c['seconds']=math.ceil(c['seconds'])
 for filename,data in [(f'full_batch_20260930_{version}.json',b),(f'full_request_20260930_{version}.json',request)]:
  out=ROOT/'tools/sfx'/filename
  content=json.dumps(data,ensure_ascii=False,indent=2)+'\n'
  if out.exists() and out.read_text()!=content:raise ValueError('Existing immutable batch differs: '+filename)
  out.write_text(content)
 print('121 sound assets, 363 candidates, 105 requirements with N04 cancelled')
if __name__=='__main__':main()
