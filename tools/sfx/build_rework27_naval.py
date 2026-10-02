"""Create immutable second rework with explicit naval context per action."""
import json,copy
from pathlib import Path
root=Path(__file__).resolve().parents[2]
b=copy.deepcopy(json.loads((root/'tools/sfx/rework27_20260930_v1.json').read_text()))
context={
'W01':'An anime shipgirl fires her destroyer-mounted naval deck gun across open sea. Naval artillery pressure and recoiling steel gun rigging, with open-air decay over water.',
'W02':'An anime shipgirl fires a cruiser naval turret across open water. A solid marine artillery blast and compact steel turret recoil, open-air decay without indoor echoes.',
'W09':'An anime shipgirl naval anti-aircraft mount defends her fleet at sea. A compact burst from a ship-mounted automatic cannon, weighty steel breech cycling over an open deck.',
'W10a':'Heavy naval anti-aircraft artillery on a shipgirl gun rig fires a controlled burst over open sea. Large-caliber automatic deck guns, deep repeated muzzle pressure and heavy recoil mechanisms.',
'W13b':'A naval shell hits an anime shipgirl heavy armored gun rig during an open-sea battle. Thick naval steel plate deforms and weapon fittings shudder from the impact.',
'A03':'A carrier-based naval propeller bomber over the ocean releases an anti-ship bomb. A compact underwing bomb-shackle release and a soft departing airflow, isolated release only.',
'S01':'An anime submarine shipgirl and her compact steel submarine rig descend beneath open ocean. Seawater folds over the diving hull and air escapes through ballast vents.',
'S02':'An anime submarine shipgirl and her steel submarine rig emerge from beneath open ocean. Broad seawater displacement and water draining off the surfaced naval hull.',
'K01':'An anime shipgirl activates a tactical naval combat ability in her compact gun rig. Precise marine fire-control equipment unlocks with a warm short powered readiness impulse, elegant and restrained.',
'N10':'A fleet commander receives a battle-plan phase update on a naval bridge tactical console. Two muted maritime instrument pulses step forward with a small chart-console switch confirmation.',
'N11a':'A fleet commander receives successful naval mission completion on a warship bridge tactical console. A brief warm rounded maritime instrument acknowledgment resolves firmly, calm naval professionalism.',
'N13':'A naval battle time-limit warning on a fleet command bridge chronometer. Muted low-mid instrument ticks accelerate slightly to convey time running out, short restrained urgency.',
'F02':'A coastal naval station changes fleet control. Its marine control interlock releases and a shipboard-style command relay secures into the new position, short decisive two-stage mechanical confirmation.',
'F04':'An anime shipgirl naval rig completes gentle docking at a floating naval supply pontoon. Wet mooring line tension and a soft rubber marine fender compression settle into stillness.',
'F05a':'A docked anime shipgirl naval rig begins resupply from a naval tender. A marine fueling hose coupling locks to the rig, followed by a brief smooth enclosed liquid-flow start.',
'F09a':'A naval minelaying rack on an anime shipgirl rig begins its deployment cycle over the sea. A marine safety catch opens and the heavy salt-weathered launch rail slides outward.',
'F09b':'A naval minelaying rack on an anime shipgirl rig finishes its deployment cycle. The emptied marine launch carriage retracts and locks securely in its steel cradle.',
'F11a':'A coastal naval defensive minefield is armed from a marine control console. Two close shipboard relay contacts engage and a short low rounded naval instrument tone confirms the circuit is live.',
'F11b':'A coastal naval defensive minefield is disarmed from the same marine control console. One shipboard relay contact releases and a tiny low electrical vibration dies away.',
'U02':'The fleet commander backs out of a naval tactical-chart menu. A refined brass-and-enamel marine console control softly retracts with one low rounded contact, small elegant anime naval interface gesture.',
'U04a':'The fleet commander confirms a shipgirl sailing course on the naval tactical chart. One soft nautical chart-console contact followed by a tiny forward airy glide, conveying course execution.',
'U04b':'The fleet commander appends a waypoint to a shipgirl sea route on a naval tactical chart. Two brief muted brass console contacts, the second lighter, conveying one additional plotted point.',
'U04c':'The fleet commander orders naval concentrated fire through a shipboard optical fire-control director. Two fine steel rangefinder controls converge into one centered locking click, command confirmation only.',
'U06':'The fleet commander switches a shipgirl naval gun between shell types using a brass-and-steel gunnery selector. One rotary marine instrument detent clicks into its new position.',
'U07a':'The fleet commander enables a shipgirl navigation-assist control on a naval bridge console. A refined marine toggle clicks on with a very brief warm low-to-mid instrument rise.',
'U07b':'The fleet commander disables the same shipgirl navigation-assist control on a naval bridge console. A refined marine toggle clicks off with a very brief warm mid-to-low instrument fall.',
'U11':'A fleet tactical chart panel opens in an anime naval command interface. A small brass marine instrument tray slides outward with delicate friction and a cushioned stop.'}
# Replace generic foley metaphors where the new naval object is the primary sound source.
replace={'N10':'Two discrete low-mid marine instrument pulses, second slightly firmer. Short dry update, not a high bell.', 'N11a':'A soft naval-console relay closure with a brief warm rounded resolving tone. No fanfare, musical phrase, alarm or laser.', 'N13':'Three dry chronometer ticks followed by two closer ticks, then silence. No siren or notification melody.'}
b.update(id='sfx_rework27_naval_20260930_v2',parent_batches=['sfx_rework27_20260930_v1'],status='planned',revision_reason='用户反馈主题不足；每条以舰娘海战场景、海军声源与具体动作起句')
req={'batch_id':b['id'],'sounds':[]}
for i,a in enumerate(b['assets']):
 aid=a['id'];assert aid in context
 a['naval_context']=context[aid];a['direction']='舰娘海战场景：'+a['direction'];base=replace.get(aid,a['english_brief'])
 for j,c in enumerate(a['candidates']):
  style=['Close, crisp material detail and short outdoor decay.','Warm full material body, controlled low frequencies and gentle treble.','Rounded gentle attack with clear action timing, comfortable for repeated playback.'][j]
  prompt='Sound effect for Tiny Sea War, a 2D anime shipgirl naval battle game. '+context[aid]+' '+base+' '+style+' One isolated compact event with a complete ending. No voices, speech, music, seagulls, background surf, room ambience, or fantasy magic. Preserve the specific naval action; no unrelated generic notification.'
  c.update(id=f"{aid}_nav2_{'abc'[j]}",seed=202609312000+i*10+j,prompt=prompt,status='planned')
  req['sounds'].append(dict(id=c['id'],seed=c['seed'],prompt=prompt,seconds=a['generation_seconds']))
assert len(req['sounds'])==81
for name,obj in [('rework27_naval_20260930_v2.json',b),('rework27_naval_request_20260930_v2.json',req)]:
 p=root/'tools/sfx'/name;t=json.dumps(obj,ensure_ascii=False,indent=2)+'\n'
 if p.exists():assert p.read_text()==t
 else:p.write_text(t)
print('27 naval-context assets, 81 candidates')
