import json,copy
from pathlib import Path
root=Path.cwd(); d=json.loads((root/'tools/sfx/reviews/current_disposition.json').read_text()); old=json.loads((root/'tools/sfx/full_batch_20260930_v3.json').read_text())
briefs={
'W01':'One small naval deck cannon fires. A compact deep gunpowder blast with a full chesty pressure body, followed by a heavy sliding recoil mechanism. Clearly a ship cannon, not a pistol or rifle. Short outdoor decay.',
'W02':'One medium naval cannon fires once: a solid low boom followed by one short recoil clunk. Simple clean two-part action, no scattered debris, no layered explosions.',
'W09':'A short controlled burst of a naval close-in automatic cannon. Several clearly separated low-mid throaty reports with rhythmic mechanical cycling. Rounded edges, subdued treble, no shrill rattling.',
'W10a':'A heavy naval anti-aircraft autocannon fires a short regular burst of three heavy low-pitched reports, each with a mechanical recoil. Slower and deeper than a light autocannon. Not a single cannon shot. Short decay.',
'W13b':'A shell strikes thick steel naval armor: one sharp dense impact followed by brief bending metal and loose steel fittings vibrating. Dry irregular metallic stress, no drum tone, no musical resonance.',
'A03':'An aircraft bomb rack gently releases its load: one quiet rounded mechanical latch opening followed by a soft brief air swish moving away. No explosion, no landing impact, no shrill whistle.',
'S01':'A small submarine slips below the sea surface: broad natural water folds over the hull, then a few soft bubbles fade underwater. A clear surface-to-submerged transition. Full natural bandwidth, no telephone or radio sound, no sonar.',
'S02':'A small submarine gently breaks the sea surface: a short broad displacement of water rises, then water sheets drain softly off metal. Clear emerge-then-drain sequence. Not beach surf, not a tap or fountain.',
'K01':'A compact mechanical ability activation: a softly spring-loaded precision latch releases, a warm brief airy impulse expands and quickly settles. Rounded low-mid body, gentle treble, no sharp chime, no spell explosion.',
'N10':'A quiet task progress interface cue: two discrete warm low-mid wooden clicks, the second slightly firmer, then silence. A small step forward, restrained and dry, no high-pitched bells.',
'N11a':'A restrained objective complete cue: a soft tension release followed by a single warm resonant wooden closure with a tiny rounded upward finish. Calm satisfaction and finality, no alarm, no fanfare, no science fiction laser.',
'U02':'A gentle interface back action: a very short soft sliding mechanism retracts inward and lands on a rounded low wooden stop. Quiet, smooth and reassuring, no harsh buzzer, no rejection alarm.',
'N13':'A short countdown warning made of dry low-mid clock ticks. Three evenly distinct ticks followed by two ticks closer together, then silence. Subtle urgency through accelerating spacing, no rising notification chime, no siren.',
'F02':'A precision mechanical lock changes ownership: one latch disengages, a tiny pause, then a second latch firmly clicks into place. Clear release then secure sequence, dry intimate mechanism, no motor hum or electronic notification.',
'F04':'Gentle boat docking: a mooring rope briefly stretches taut, a rubber fender softly compresses against the hull, then all motion stops. Close small-scale physical detail, no steel crash or reward chime.',
'F05a':'Naval refueling begins: a hose coupling clicks securely into its socket, immediately followed by a short smooth liquid flow starting inside the hose. Clear connect then flow, no completion signal, no tools hammering.',
'F09a':'A naval mine deployment rack is prepared: a safety lever flips open, then a metal carriage slides outward along its rail and stops softly. Preparation only, no splash, no detonation.',
'F09b':'A naval mine deployment rack finishes its action: a metal carriage slides back inward along its rail and seats with one clear locking click. Return then lock, no splash, no detonation.',
'F11a':'A compact naval electrical relay arms: two closely spaced firm relay clicks followed by a very brief stable low-mid electrical tone. Clear engagement and settled powered state, no spark or explosion.',
'F11b':'The same compact naval electrical relay disarms: one soft release click followed by a tiny electrical vibration rapidly dying into silence. Clear release and power-off, no two-click engagement.',
'U04a':'A short move-command interface acknowledgment: one rounded soft contact click followed immediately by a tiny smooth forward air glide. One gesture, dry and light, no double click, no chime.',
'U04b':'A queued waypoint interface acknowledgment: two separate soft rounded contact clicks, the second noticeably lighter. A concise add-one-item gesture, no glide or notification bell.',
'U04c':'A focus-target interface acknowledgment: two small precision mechanical parts converge into one dry centered locking click. Tight controlled closure, no gunfire, no impact explosion, no electronic beep.',
'U06':'An ammunition selector turns one notch: a short rotary mechanical detent snaps into the next position with a rounded tactile click. No cartridge loading, no gunshot, no electronic flourish.',
'U07a':'A small tactile toggle switches on: a soft physical click followed by a very short rounded low-to-mid rising tone. Clear activation, warm and gentle, no shrill high pitch.',
'U07b':'The same small tactile toggle switches off: a soft physical click followed by a very short rounded mid-to-low falling tone that stops cleanly. Clear deactivation, warm and gentle.',
'U11':'A lightweight interface panel opens: a very quiet short sliding rail moves outward and comes to a soft cushioned stop. Delicate airy friction, no button click, no notification bell.'}
selected=[x for x in d['items'] if x['status'] in ('revise_timbre','redesign_semantics')]; assert set(briefs)=={x['id'] for x in selected}
b=copy.deepcopy(old);b.update(id='sfx_rework27_20260930_v1',status='planned',parent_batches=[old['id']],assets=[],requirements=d['requirements'],cancelled=d['cancelled_asset_ids'],retained_preferences={},review_source=d['source_review']);b.pop('supersedes_attempt',None);b['duration_note']='Integer source seconds; retain full source and natural decay.'
lookup={x['id']:x for x in old['assets']}; request={'batch_id':b['id'],'sounds':[]}
variations=[('干净动作','Close and dry recording, precise transient detail and a brief natural decay.'),('温暖材质','Warmer material body with subdued treble, keeping the exact action sequence and timing clear.'),('柔和耐听','Softer attack with rounded edges, quiet fine detail, preserving the exact action and rhythm.')]
for i,item in enumerate(selected):
 a=copy.deepcopy(lookup[item['id']]);a.update(direction=item['revision_brief'],english_brief=briefs[item['id']],previous_feedback=item['feedback'],generation_seconds=1 if a['category']=='ui' else 3 if a['id'] in ('W09','W10a','S01','S02','N13') else 2,loop=False,candidates=[])
 for j,(name,style) in enumerate(variations):
  cid=f"{a['id']}_rw1_{'abc'[j]}";prompt=briefs[a['id']]+' '+style+' Isolated sound effect for a small-scale naval tactics game. Complete action then silence. No speech, voices, music, or background ambience.'
  c=dict(id=cid,seed=202609309000+i*10+j,variation=name,prompt=prompt,status='planned');a['candidates'].append(c);request['sounds'].append(dict(id=cid,seed=c['seed'],prompt=prompt,seconds=a['generation_seconds']))
 b['assets'].append(a)
for filename,data in [('rework27_20260930_v1.json',b),('rework27_request_20260930_v1.json',request)]:
 p=root/'tools/sfx'/filename;content=json.dumps(data,ensure_ascii=False,indent=2)+'\n'
 if p.exists():assert p.read_text()==content
 else:p.write_text(content)
assert len(request['sounds'])==81 and not(set(briefs)&set(d['cancelled_asset_ids']))
print('27 assets / 81 candidates, cancelled and adopted excluded')
