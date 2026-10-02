import json,copy
from pathlib import Path
root=Path(__file__).resolve().parents[2];f=root/'tools/sfx';d=json.loads((f/'reviews/current_disposition.json').read_text());b=copy.deepcopy(json.loads((f/'revision15_20261001_v4.json').read_text()));old={a['id']:a for a in b['assets']}
spec={
'K01':(1,.65,'技能成功：圆润有力的短起势，适度明亮，避开碎铃和细金属。',[
'A game ability activation sound: a short soft air swell into one clear warm orchestral hit. Rounded, confident and gently bright. Compact anime naval combat cue, no tinkling bells.',
'A tactical game skill activation cue: a quick rounded whoosh ending in a warm solid synth chord stab. Clear upbeat release, smooth treble, short clean decay.',
'A naval game ability activation cue: a soft low drum accent under a brief warm rising orchestral swell, ending firmly. Light energy with body, no metallic ringing.']),
'N11a':(2,1.1,'任务完成：简洁和谐的解决感，三候选比较乐器，不使用电报脉冲。',[
'A short mission accomplished game jingle. Three gentle felt-piano notes forming a simple rising major arpeggio, last note resolves warmly. About one second, clean and consonant.',
'A short naval strategy victory notification. A warm marimba rising major arpeggio with three evenly spaced notes and a soft resolved ending. About one second.',
'A brief task completed game jingle. Soft orchestral strings play a small uplifting consonant cadence, settled and satisfying. One second, restrained, no dramatic fanfare.']),
'F09b':(2,2,'非人声报告声：海军通信确认，两段短音/信号后收束；不使用旋律。',[
'A naval radio message received signal. A short squelch opening, two clear rounded communication beeps, then a soft squelch closing. Two seconds, clean restrained military radio acknowledgment, no voice or music.',
'A ship bridge report acknowledgment buzzer. Two short low steady buzzer calls separated by a pause, ending cleanly. Two seconds, nonmusical and restrained, no speech.',
'A naval communications terminal report received signal. One short clear call tone, a pause, then a longer confirming tone at the same pitch. Two seconds, dry and calm, no melody or voice.']),
'U04a':(1,.35,'移动确认：单次短确认，比较木质触点、圆润音和轻鼓点，不再复制旧B。',[
'A naval strategy game move order accepted sound. One soft wooden tap followed by a tiny warm upward tone. Brief clean positive confirmation, a third of a second.',
'A game movement command acknowledgment. A single rounded warm pluck with a slight upward lift and quick decay. Calm precise UI sound, no noise.',
'A tactical map move-command cue. A small muted drum tap with a soft clean tonal finish. One brief confident gesture, no mechanical clatter.']),
'U06':(1,.45,'舰炮弹种选择：短粗重落位，取消长液压铺垫，不表达完整装填。',[
'A short heavy naval artillery breech clunk. One deep solid steel mechanism seats firmly, immediate low thud and quick stop. Half a second, no extended loading sequence.',
'A battleship gun ammunition selector mechanism locks into position. A single thick low metal chunk, weighty and compact, rapid decay. No rifle rattling.',
'A large naval gun mechanism makes one short heavy locking thump. Dense low steel impact with a very brief hydraulic finish. Under half a second.']),
'U07a':(1,.6,'辅助开启：同乐器三音上行；候选用柔和真实键盘乐器，避免怪异合成器。',[
'A simple game enable sound: three soft felt-piano notes ascending a major triad, evenly spaced. Warm natural piano tone, brief clean finish, half a second.',
'A simple interface on jingle: three gentle marimba notes ascending a major triad, evenly spaced. Warm wooden musical tone, short and friendly.',
'A simple game assistance enabled jingle: three soft electric-piano notes stepping upward, evenly spaced, warm and consonant. Brief natural decay.']),
'U07b':(1,.6,'辅助关闭：与开启对应乐器三音下行，保持材质与节奏。',[
'A simple game disable sound: three soft felt-piano notes descending a major triad, evenly spaced. Warm natural piano tone, brief clean finish, half a second.',
'A simple interface off jingle: three gentle marimba notes descending a major triad, evenly spaced. Warm wooden musical tone, short and friendly.',
'A simple game assistance disabled jingle: three soft electric-piano notes stepping downward, evenly spaced, warm and consonant. Brief natural decay.'])}
assert set(spec)=={x['id'] for x in d['items'] if x['status'] in ('revise_timbre','redesign_semantics')}
b.update(id='sfx_revision7_20261001_v5',assets=[],requirements=d['requirements'],cancelled=d['cancelled_asset_ids'],parent_batches=['sfx_revision15_20261001_v4'],revision_reason='第四轮7项反馈逐条重设计');req={'batch_id':b['id'],'sounds':[]}
for i,(aid,(seconds,target,direction,prompts)) in enumerate(spec.items()):
 a=copy.deepcopy(old[aid]);a.update(generation_seconds=seconds,target_seconds=target,direction=direction,english_brief=prompts[0],candidates=[])
 for j,prompt in enumerate(prompts):
  c=dict(id=f'{aid}_r5_{"abc"[j]}',seed=202610015000+i*10+j,prompt=prompt+' Isolated sound effect, no speech or background ambience.',variation=['方案A','方案B','方案C'][j],status='planned');a['candidates'].append(c);req['sounds'].append(dict(id=c['id'],seed=c['seed'],prompt=c['prompt'],seconds=seconds))
 b['assets'].append(a)
for name,obj in [('revision7_20261001_v5.json',b),('revision7_request_20261001_v5.json',req)]:
 p=f/name;t=json.dumps(obj,ensure_ascii=False,indent=2)+'\n'
 if p.exists():assert p.read_text()==t
 else:p.write_text(t)
(f/'revision7_design_20261001_v5.md').write_text('# 第五轮7项声音设计\n\n21条新生成，维持54项采用及61项取消。布雷完成暂按非人声报告信号设计，不假设用户要求台词。技能采用圆润有力的起势而非碎铃；任务完成与辅助开关采用具体乐器的和谐音型。模型对音程和次数不保证准确，仍需听审。\n\n'+ '\n'.join('- '+a['id']+' '+a['title']+'：'+a['direction'] for a in b['assets'])+'\n')
