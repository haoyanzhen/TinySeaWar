import json, copy
from pathlib import Path
root=Path(__file__).resolve().parents[2]; f=root/'tools/sfx'
d=json.loads((f/'reviews/current_disposition.json').read_text())
b=copy.deepcopy(json.loads((f/'revision7_20261001_v5.json').read_text())); old={a['id']:a for a in b['assets']}
spec={
'K01':(1,.7,'舰娘技能成功施放的短提示：A极简类别词；B短上扬气流与温暖落点；C加SFX标签。不是武器发射或命中。',[
'Game skill activation sound effect.',
'A short rising whoosh ending in a warm soft impact. Anime naval game skill activation, dry, quick decay.',
'TrackType: SFX. A short rising whoosh ending in a warm soft impact. Anime naval game skill activation, dry, quick decay.']),
'N11a':(2,1.2,'海战战术目标完成：全部为钢琴三音，比较极简描述、明确声源音型、Instrument标签；与辅助开关的电钢琴作区分。',[
'Three ascending piano notes, mission complete sound effect.',
'Acoustic piano plays three ascending notes of a major chord, evenly spaced, then stops. Warm soft attack, short dry decay.',
'TrackType: Instrument. Acoustic piano plays three ascending notes of a major chord, evenly spaced, then stops. Warm soft attack, short dry decay.']),
'F09b':(2,2,'布雷作业完成的舰桥非人声报告：改用中低音报告铃双击和自然余响，避开电报码、通信蜂鸣与音乐旋律。这是待听审的新设计假设。',[
'A ship bridge bell ringing twice.',
'A medium brass ship bell struck twice, two rounded low clongs followed by a short natural decay. Close dry recording.',
'TrackType: SFX. A medium brass ship bell struck twice, two rounded low clongs followed by a short natural decay. Close dry recording.'])}
assert set(spec)=={a['id'] for a in d['items'] if a['status'] in ('revise_timbre','redesign_semantics')}
b.update(id='sfx_revision3_20261001_v6',assets=[],requirements=d['requirements'],cancelled=d['cancelled_asset_ids'],parent_batches=['sfx_revision7_20261001_v5'],revision_reason='官方与社区提示词调研后3项对照生成'); req={'batch_id':b['id'],'sounds':[]}
for i,(aid,(seconds,target,direction,prompts)) in enumerate(spec.items()):
 a=copy.deepcopy(old[aid]);a.update(generation_seconds=seconds,target_seconds=target,direction=direction,english_brief=prompts[0],candidates=[])
 for j,prompt in enumerate(prompts):
  # B/C share seed so optional-tag comparison does not also change sampling noise.
  c=dict(id=f'{aid}_r6_{"abc"[j]}',seed=202610016000+i*10+min(j,1),prompt=prompt,variation=['极简类别描述','声源与动作','同声源动作加官方标签'][j],status='planned')
  a['candidates'].append(c);req['sounds'].append(dict(id=c['id'],seed=c['seed'],prompt=prompt,seconds=seconds))
 b['assets'].append(a)
for name,obj in [('revision3_20261001_v6.json',b),('revision3_request_20261001_v6.json',req)]:
 p=f/name;t=json.dumps(obj,ensure_ascii=False,indent=2)+'\n'
 if p.exists():assert p.read_text()==t
 else:p.write_text(t)
