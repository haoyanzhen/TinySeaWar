#!/usr/bin/env python3
"""Summarize M/L diagnostic evidence without claiming formal win-rate acceptance."""
import argparse,csv,json
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]
def main():
 p=argparse.ArgumentParser();p.add_argument('--runs',default='artifacts/simulations/challenge_ml_20260930/gate3');p.add_argument('--overrides',default='artifacts/simulations/challenge_ml_20260930/gate4');p.add_argument('--output',default='reports/challenges/20260930-ml');a=p.parse_args()
 out=ROOT/a.output;out.mkdir(parents=True,exist_ok=True)
 summary=[];damage=[];navigation=[];runs=[]
 for code in [f'{c}{n:02}' for c in 'ml' for n in range(1,6)]:
  source=ROOT/a.runs/code/'runs.jsonl'
  override=ROOT/a.overrides/code/'runs.jsonl'
  if override.exists():source=override
  if not source.exists():continue
  records=[json.loads(s) for s in source.read_text().splitlines() if s.strip()]
  valid=[r for r in records if r['end_state']=='Finished'];wins=sum(r['winner_faction']=='player' for r in valid)
  stuck=sum(r['ai_behavior'].get('path_stuck_events',0) for r in records);failed=sum(r['ai_behavior'].get('route_unavailable',0) for r in records)
  nofire=sum(v['weapon_fires']==0 for r in records for v in r.get('submarine_ai',{}).values())
  row={'code':code,'attempts':len(records),'valid':len(valid),'player_wins':wins,'diagnostic_win_rate':wins/len(valid) if valid else None,'mean_duration':sum(r['duration'] for r in valid)/len(valid) if valid else None,'path_stuck_all_attempts':stuck,'route_failed_all_attempts':failed,'submarine_zero_fire_unit_runs':nofire,'formal_20_seed_status':'not_run_behavior_gate_unresolved'};summary.append(row)
  for r in records:
   runs.append({'code':code,'seed':r['seed'],'end_state':r['end_state'],'winner':r['winner_faction'],'duration':r['duration'],'reason':r['finish_reason'],'reason_summary':r.get('finish_reason_summary',''),'fleet_cost':json.dumps(r.get('fleet_cost',{}))})
   for uid,u in r['units'].items():
    damage.append({'code':code,'seed':r['seed'],'unit_id':uid,'side':u['faction_id'],'ship':u['definition_id'],'shots':u['shots'],'damage':u['damage_dealt'],'contribution':u.get('contribution_damage',0),**u.get('damage_by_category',{})})
   for e in r['ai_behavior'].get('navigation_events',[]):navigation.append({'code':code,'seed':r['seed'],'end_state':r['end_state'],'event':json.dumps(e,ensure_ascii=False)})
 for name,rows in [('gate-summary',summary),('run-results',runs),('unit-damage',damage),('navigation-events',navigation)]:
  if rows:
   with (out/(name+'.csv')).open('w') as f:
    writer=csv.DictWriter(f,fieldnames=list(rows[0]));writer.writeheader();writer.writerows(rows)
 (out/'gate-summary.json').write_text(json.dumps(summary,ensure_ascii=False,indent=2)+'\n')
 text=['# M/L 三种子行为核查','', '以下为诊断样本，不能代替每关20种子的正式平衡。胜率分母仅含有效局；导航与零开火统计保留全部尝试。未展开正式实验；潜艇参与、导航异常和性能需要独立关闭。','', '|关卡|有效/尝试|玩家胜|平均秒|卡住|请求失败|潜艇零开火舰次|','|---|---|---|---|---|---|---|']
 for r in summary:text.append(f"|{r['code'].upper()}|{r['valid']}/{r['attempts']}|{r['player_wins']}|{r['mean_duration']:.1f}|{r['path_stuck_all_attempts']}|{r['route_failed_all_attempts']}|{r['submarine_zero_fire_unit_runs']}|")
 text+=['','同目录 CSV 保存逐局终局原因、各舰分类伤害和全部导航事件。原始完整潜艇决策与单位终态仍见 runs.jsonl。','', '## 整场 CPU / 航空源点探针','', '单位为毫秒；P95/P99 是整 Tick 规则 CPU，包含诊断开销，主机背景负载未隔离，不代表正式性能验收、GPU 或真人输入体验。','', '|关卡|Tick P95|Tick P99|航空源点窗口|真实航母开火事件|','|---|---|---|---|---|']
 for probe in sorted(out.glob('probe-*.json')):
  r=json.loads(probe.read_text());p=r['performance'].get('tick_total_usec',{});windows=r['carrier_source_weather_windows'];conds={k:{c:round(v,1) for c,v in w['seconds_by_condition'].items()} for k,w in windows.items()}
  text.append(f"|{r['code'].upper()}|{p.get('p95',0)/1000:.2f}|{p.get('p99',0)/1000:.2f}|{json.dumps(conds,ensure_ascii=False)}|{len(r['carrier_weapon_fires'])}|")
 text+=['','源点窗口只是航空合法性的必要条件；目标点天气、接触、射程、装填仍由公共规则检查，未绕过 Severe 禁飞。性能与航空原始数据保存在 probe-*.json。']
 (out/'summary.md').write_text('\n'.join(text)+'\n')
if __name__=='__main__':main()
