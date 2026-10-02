import json,copy
from pathlib import Path
root=Path(__file__).resolve().parents[2];f=root/'tools/sfx';d=json.loads((f/'reviews/current_disposition.json').read_text());b=copy.deepcopy(json.loads((f/'design18_20261001_v3.json').read_text()));old={a['id']:a for a in b['assets']}
spec={
'W13b':(2,1.3,'A heavy naval shell exploding against battleship armor. One massive explosive impact, deep thunderous blast and short powerful rumbling decay. Outdoor naval battle sound effect.'),
'A03':(2,1.3,'A naval bomber bomb bay opening with a heavy hydraulic door movement, followed immediately by the first short rushing air sound of a released bomb. Isolated aircraft bomb release sound effect.'),
'S01':(3,2,'A submarine diving into deep ocean. A large mass of seawater surges over the steel hull and sinks downward with deep rolling water and heavy bubbling. Powerful broad water movement.'),
'S02':(3,2,'A submarine breaking out of the ocean surface. One large deep splash of seawater rising and falling off the hull. Broad heavy ocean water displacement, isolated surfacing sound.'),
'K01':(1,.55,'A bright gentle video game ability activation chime. Light clear bell-like sparkle, a short uplifting sound with a soft pleasant finish. Anime naval game interface sound effect.'),
'N10':(1,.45,'A pleasant short video game notification chime. Two light marimba notes, warm natural wooden tone, clean gentle finish. Naval mission progress notification.'),
'N11a':(2,.9,'A cheerful short game mission complete jingle. Three clear piano notes forming an uplifting major chord, with a soft bell accent and a resolved ending. Brief naval strategy game success sound.'),
'F04':(2,1.2,'A ship anchor windlass ratchet locking with three consecutive heavy clanks. Clank, clank, clank, then stops. Solid low steel anchor mechanism on a naval deck.'),
'F09b':(1,.55,'A short pleasant game task complete chime, two warm marimba notes followed by a soft bell finish. Clear calm confirmation that naval minelaying is complete.'),
'U04c':(1,.5,'An optical naval gunsight zooming in and locking onto a target. A short smooth lens motor whirr tightening into a firm click. Clean focused targeting sound effect.'),
'U06':(2,.9,'A battleship main gun heavy ammunition hoist shifting a large naval artillery shell into position. A short deep hydraulic movement and one massive steel breech clunk. Weighty large machinery.'),
'U07a':(1,.65,'A friendly game interface enable jingle. Three soft piano notes ascending in pitch, evenly spaced, clear and gently uplifting. Short naval strategy game assistance enabled sound.'),
'U07b':(1,.65,'A friendly game interface disable jingle. Three soft piano notes descending in pitch, evenly spaced, clear and gently settling. Short naval strategy game assistance disabled sound.'),
'U11':(3,3,'A large nautical parchment chart unrolling across a wooden table for three seconds. Continuous soft thick paper rolling and unfolding, gently settling flat at the end. Naval tactical map panel opening sound.')}
b.update(id='sfx_revision15_20261001_v4',assets=[],requirements=d['requirements'],cancelled=d['cancelled_asset_ids'],parent_batches=['sfx_design18_20261001_v3'],revision_reason='最新用户指定声音动作；缩短提示词，提示音乐不再禁止');req={'batch_id':b['id'],'sounds':[]}
for i,x in enumerate(z for z in d['items'] if z['status'] in ('revise_timbre','redesign_semantics')):
 aid=x['id'];a=copy.deepcopy(old[aid]);a.update(direction=x['revision_brief'],previous_feedback=x['feedback'],candidates=[])
 if aid=='U04a':seconds,target,base=1,1.1,'Editing previous U04a_d3_b into two identical successive sounds.'
 else:seconds,target,base=spec[aid]
 a.update(generation_seconds=seconds,target_seconds=target,english_brief=base)
 for j,(label,suffix) in enumerate([('清楚自然','Clean close recording.'),('柔和温暖','Warm tone, gentle treble.'),('饱满圆润','Full rounded sound, soft edges.')]):
  c=dict(id=f'{aid}_r4_{"abc"[j]}',seed=202610014000+i*10+j,prompt=base+' '+suffix,variation=label,status='planned')
  if aid=='U04a':c.update(variation=f'B二连音·间隔{[60,120,200][j]}ms',production_method='edit_reference',gap_ms=[60,120,200][j]);a['reference']=x['revision_reference']
  else:req['sounds'].append(dict(id=c['id'],seed=c['seed'],prompt=c['prompt'],seconds=seconds))
  a['candidates'].append(c)
 b['assets'].append(a)
assert len(b['assets'])==15 and len(req['sounds'])==42
for name,obj in [('revision15_20261001_v4.json',b),('revision15_request_20261001_v4.json',req)]:
 p=f/name;t=json.dumps(obj,ensure_ascii=False,indent=2)+'\n'
 if p.exists():assert p.read_text()==t
 else:p.write_text(t)
(f/'revision15_design_20261001_v4.md').write_text('# 第四轮制作设计\n\n依据最新评审的15项逐条约束，见reviews/sfx_design18_20261001_v3.summary.md。本轮42条模型新生成＋3条U04a-B二连音编辑；编辑候选仅比较60/120/200ms间隔，不冒充独立模型生成。\n\n模型官方卡示例采用简洁的声源＋动作描述：https://huggingface.co/stabilityai/stable-audio-3-small-sfx 。据此本轮尝试短正向描述，减少抽象电子术语、否定清单和多层叙述；这是实验策略，不保证质量。提示音乐采用钢琴/木琴/铃声描述，U11为3秒海图展开。U06仅借重型舰炮机构表达选择，不证明装填完成。\n\n'+ '\n'.join('- '+a['id']+' '+a['title']+'：'+a['direction'] for a in b['assets'])+'\n')
