#!/usr/bin/env python3
"""Verify and report every attempted candidate without merging repeated seeds."""
from __future__ import annotations
import argparse
from collections import Counter, defaultdict
import csv
import hashlib
import json
from pathlib import Path
import random
import statistics

from tune_challenge_difficulty import ROOT, CODES, TARGETS, read_runs, summarize, write_json, choose_candidate, retain_candidate, in_target_band


def quantile(values,q):
    if not values:return None
    values=sorted(values); index=(len(values)-1)*q; low=int(index)
    return values[low]+(values[min(low+1,len(values)-1)]-values[low])*(index-low)


def paired(control, candidate):
    a={r['seed']:r for r in control if r['end_state']=='Finished'}
    b={r['seed']:r for r in candidate if r['end_state']=='Finished'}
    common=sorted(a.keys() & b.keys())
    deltas=[int(b[s]['winner_faction']=='player')-int(a[s]['winner_faction']=='player') for s in common]
    rng=random.Random(20261001)
    bootstrap=[sum(rng.choices(deltas,k=len(deltas)))/len(deltas) for _ in range(2000)] if deltas else []
    planned={r['seed'] for r in control} | {r['seed'] for r in candidate}
    return {'complete_pairs':len(common), 'missing_pairs':sorted(planned-set(common)),
            'loss_to_win':deltas.count(1),'win_to_loss':deltas.count(-1),
            'net_player_win_change':statistics.mean(deltas) if deltas else None,
            'paired_bootstrap95':[quantile(bootstrap,.025),quantile(bootstrap,.975)],
            'median_duration_difference':statistics.median(b[s]['duration']-a[s]['duration'] for s in common) if common else None}


def diagnostics(runs):
    nav=Counter(); reasons=Counter(); recovery=[]; subs=[]; carriers=[];censored=[]
    for r in runs:
        nav.update(r.get('navigation',{}).get('event_counts',{}))
        reasons.update(r.get('navigation',{}).get('failures_by_reason',{}))
        recovery.extend(e.get('duration',0) for e in r.get('ai_behavior',{}).get('navigation_events',[])
                        if e['event_type']=='NavigationRecoveryCompleted')
        active={}
        for event in r.get('ai_behavior',{}).get('navigation_events',[]):
            uid=event.get('unit_id','')
            if event['event_type']=='NavigationRecoveryStarted':active[uid]=event.get('elapsed_time',event.get('time',0))
            elif event['event_type'] in ['NavigationRecoveryCompleted','NavigationRecoveryCancelled']:active.pop(uid,None)
        censored.extend({'seed':r['seed'],'unit_id':uid,'started_at':start,
                         'observed_duration':r['duration']-start,'status':'censored_at_battle_end'} for uid,start in active.items())
        subs.extend(r.get('submarine_ai',{}).values())
        carriers.extend(u for u in r['units'].values() if u['definition_id'] in CARRIER_IDS)
    durations=[r['duration'] for r in runs if r['end_state']=='Finished']
    return {'duration_p10':quantile(durations,.1),'duration_p90':quantile(durations,.9),
            'path_stuck':sum(r['ai_behavior'].get('path_stuck_events',0) for r in runs),
            'route_failures':sum(r['ai_behavior'].get('route_unavailable',0) for r in runs),
            'navigation_events':dict(nav),'navigation_failure_reasons':dict(reasons),
            'completed_recoveries':len(recovery),'slow_recoveries_gt20s':sum(x>20+1e-6 for x in recovery),
            'max_completed_recovery':max(recovery,default=0),
            'unfinished_recoveries':censored,
            'submarine_samples':len(subs),'submarine_zero_fire':sum(s.get('weapon_fires',0)==0 for s in subs),
            'submarine_full_cycles':sum(s.get('normal_full_cycles',0) for s in subs),
            'carrier_samples':len(carriers),'carrier_zero_aviation_damage':sum(u['damage_by_category']['aviation']==0 for u in carriers),
            'reasons':dict(Counter(r['finish_reason_summary'] or r['finish_reason'] for r in runs))}


def csv_write(path,rows):
    if not rows:return
    fields=list(dict.fromkeys(k for row in rows for k in row))
    with path.open('w',newline='') as f:
        writer=csv.DictWriter(f,fields);writer.writeheader()
        writer.writerows({k:json.dumps(v,ensure_ascii=False) if isinstance(v,(dict,list)) else v for k,v in row.items()} for row in rows)


def reinforcements(runs, level):
    """Actual entry is established by native unit facts, not the earliest window."""
    result=[]
    categories=sorted({category for r in runs for u in r['units'].values() for category in u['damage_by_category']})
    for wave in level.get('reinforcement_waves',[]):
        members=[member['entity_id'] for member in wave['members']]
        result.append({'wave_id':wave['wave_id'],'earliest_time':wave['earliest_time'],
                       'members':members,'attempts':len(runs),
                       'entered_battles':sum(all(uid in r['units'] for uid in members) for r in runs),
                       'damage_by_category':{category:sum(r['units'].get(uid,{}).get('damage_by_category',{}).get(category,0)
                                                        for r in runs for uid in members)
                                             for category in categories}})
    return result


CARRIER_IDS=set()
def main():
    parser=argparse.ArgumentParser();parser.add_argument('--experiment',type=Path,default=ROOT/'artifacts/simulations/challenge_ml_tuning_20261001')
    parser.add_argument('--output',type=Path,default=ROOT/'reports/challenges/20261001-tuning')
    args=parser.parse_args();base=args.experiment.resolve();out=args.output.resolve();out.mkdir(parents=True,exist_ok=True)
    status=json.loads((base/'pipeline_status.json').read_text())
    if status['state']!='completed':raise ValueError('Pipeline incomplete; do not issue a final report')
    contract=json.loads((base/'experiment_contract.json').read_text());baseline=Path(contract['baseline'])
    ships={d['id']:d for file in (base/'stage0/frozen/data/ships').glob('*.json') for d in json.loads(file.read_text())['definitions']}
    CARRIER_IDS.update(s['id'] for s in ships.values() if s['ship_class']=='Carrier')
    rows=[];groups=[];unit_rows=[];sub_rows=[];nav_rows=[];comparisons=[];finals=[];all_runs={};invalid=[]
    for path in sorted(base.glob('*/*/*/runs.jsonl')):
        split,stage_name,code=path.relative_to(base).parts[:3];stage=int(stage_name[-1]);runs=read_runs(path)
        manifest=json.loads((path.parent/'manifest.json').read_text());start=manifest['seed_plan']['start']
        expected_start=(91001 if code[0]=='m' else 92001)+(int(code[1:])-1)*100+(20 if split=='holdout' else 0)
        assert split in ['training','holdout'] and start==expected_start and manifest['seed_plan']['count']==20
        assert manifest['simulation_kind']=='FullBattleSimulation' and not manifest['side_swap']
        assert manifest['player_policy_id']==manifest['enemy_policy_id']=='LatestRuntimeAI'
        assert manifest['ai_profile_id']=='ai.profile.'+('hard' if int(code[1:])>=4 else 'standard')
        assert manifest['tick_seconds']==.1 and manifest['maximum_ticks']==12000
        assert manifest['scenarios'][0]['level_definition_id']=='level.challenge.'+code and len(manifest['scenarios'])==1
        assert len(runs)==20 and sorted(r['seed'] for r in runs)==list(range(start,start+20))
        assert len({r['run_id'] for r in runs})==20 and runs==read_runs(path.parent/'progress.jsonl')
        metrics=summarize(runs,TARGETS[int(code[1:])-1]);aggregate=json.loads((path.parent/'aggregate.json').read_text())
        assert aggregate['planned_runs']==20 and aggregate['finished_runs']==metrics['valid'] and aggregate['player_wins']==metrics['wins']
        log=(path.parent/'execution.log').read_text();assert 'SCRIPT ERROR' not in log and 'ERROR:' not in log
        metadata={'split':split,'stage':stage,'code':code}
        level=next(d for d in json.loads((base/f'stage{stage}/frozen/data/levels/formal_challenge_{code[0]}_levels.json').read_text())['definitions'] if d['id']=='level.challenge.'+code)
        groups.append({**metadata,**metrics,**diagnostics(runs),'reinforcements':reinforcements(runs,level)})
        all_runs[split,stage,code]=runs
        for r in runs:
            rows.append({**metadata,'run_id':r['run_id'],'seed':r['seed'],'end_state':r['end_state'],
                         'winner':r['winner_faction'],'duration':r['duration'],'reason':r['finish_reason'],
                         'reason_summary':r['finish_reason_summary'],'fleet_cost':r['fleet_cost'],
                         'path_stuck':r['ai_behavior'].get('path_stuck_events',0),
                         'route_failures':r['ai_behavior'].get('route_unavailable',0)})
            if r['end_state']!='Finished':invalid.append({**metadata, 'seed':r['seed'], 'state':r['end_state'], 'reason':r['finish_reason']})
            for uid,u in r['units'].items():
                unit_rows.append({**metadata,'seed':r['seed'],'unit_id':uid,'end_state':r['end_state'],
                                  'faction':u['faction_id'],'ship':u['definition_id'],'name':u['display_name'],
                                  'damage':u['damage_dealt'],'damage_taken':u['damage_taken'],
                                  'overkill':u['overkill_damage'],'resolved_attacks':u['shots'],**u['damage_by_category']})
            for uid,s in r.get('submarine_ai',{}).items():
                sub_rows.append({**metadata,'seed':r['seed'],'unit_id':uid,'end_state':r['end_state'],**s})
            for event in r.get('ai_behavior',{}).get('navigation_events',[]):
                nav_rows.append({**metadata,'seed':r['seed'],'end_state':r['end_state'],**event})
    assert len(rows)==status['dispatched_battles'] and len(rows)<=920
    selection=json.loads((base/'selection_final.json').read_text())
    for code in CODES:
        target=TARGETS[int(code[1:])-1];tolerance=.03 if code.endswith('5') else .05
        control=read_runs(baseline/code/'runs.jsonl');result=status['levels'][code]
        control_metric=summarize(control,target)
        training_metrics={int(stage):summarize(all_runs['training',int(stage),code],target) for stage in result.get('training',{})}
        if code!='l02':
            stopping_stages=[stage for stage,m in sorted(training_metrics.items()) if in_target_band(m,control_metric,tolerance)]
            expected_stop=min(stopping_stages) if stopping_stages else 3
            assert sorted(training_metrics)==list(range(1,expected_stop+1)),(code,'unexpected training schedule')
        assert result['proposed_stage']==choose_candidate(control_metric,training_metrics)
        for stage in map(int,result.get('training',{})):
            comparisons.append({'code':code,'split':'training','stage':stage,**paired(control,all_runs['training',stage,code])})
        proposed=result['proposed_stage'];retained=result['retained_stage']
        expected_retained=proposed if proposed and retain_candidate(control_metric,training_metrics[proposed],
                              summarize(all_runs['holdout',0,code],target),summarize(all_runs['holdout',proposed,code],target)) else 0
        assert retained==expected_retained==selection['selected_stages'][code]
        if proposed:comparisons.append({'code':code,'split':'holdout','stage':proposed,**paired(all_runs['holdout',0,code],all_runs['holdout',proposed,code])})
        final_train=all_runs['training',retained,code] if retained else control
        final_holdout=all_runs['holdout',retained,code]
        train=summarize(final_train,target);holdout=summarize(final_holdout,target)
        decision={}
        if proposed:
            proposed_train=summarize(all_runs['training',proposed,code],target)
            proposed_holdout=summarize(all_runs['holdout',proposed,code],target)
            holdout_baseline=summarize(all_runs['holdout',0,code],target)
            decision={'training_added_invalid_seeds':sorted(set(proposed_train['invalid_seeds'])-set(summarize(control,target)['invalid_seeds'])),
                      'holdout_added_invalid_seeds':sorted(set(proposed_holdout['invalid_seeds'])-set(holdout_baseline['invalid_seeds'])),
                      'proposed_holdout':proposed_holdout,'holdout_baseline':holdout_baseline}
        finals.append({'code':code,'target':target,'tolerance':tolerance,'original_training':summarize(control,target),
                       'proposed_stage':proposed,'retained_stage':retained,'training':train,'holdout':holdout,
                       'holdout_baseline':summarize(all_runs['holdout',0,code],target),
                       'both_point_estimates_in_band':all(m['distance'] is not None and m['distance']<=tolerance+1e-9 for m in [train,holdout]),
                       'both_20_valid_and_in_band':all(m['valid']==20 and m['distance']<=tolerance+1e-9 for m in [train,holdout]),
                       'training_diagnostics':diagnostics(final_train),'holdout_diagnostics':diagnostics(final_holdout),
                       'holdout_reinforcements':next(g['reinforcements'] for g in groups if (g['split'],g['stage'],g['code'])==('holdout',retained,code)),
                       'reason':result['reason'],'decision_details':decision,'formal_status':'Candidate / formal gates remain open'})
    hash_failures=[]
    for stage in range(4):
        frozen=base/f'stage{stage}/frozen'
        for rel,expected in json.loads((frozen.parent/'source_sha256.json').read_text()).items():
            if hashlib.sha256((frozen/rel).read_bytes()).hexdigest()!=expected:hash_failures.append([stage,rel])
    assert not hash_failures,hash_failures
    verification={'new_battles':len(rows),'valid':sum(r['end_state']=='Finished' for r in rows),'invalid':invalid,
                  'original_200_excluded':True,'all_seed_sets_and_native_aggregates_verified':True,
                  'checkpoint_final_records_equal':True,'frozen_inputs_unchanged':not hash_failures,
                  'bootstrap_replicates':2000,'bootstrap_seed':20261001,
                  'preparation_failures':'artifacts/simulations/challenge_ml_tuning_20261001_preparation_failed_01; missing minimap author manifest, zero battles'}
    write_json(out/'verification.json',verification);write_json(out/'summary.json',finals)
    write_json(out/'groups.json',groups);write_json(out/'paired_comparisons.json',comparisons)
    for filename,items in [('run-results.csv',rows),('unit-damage.csv',unit_rows),('submarine-samples.csv',sub_rows),('navigation-events.csv',nav_rows),('paired-comparisons.csv',comparisons),('groups.csv',groups)]:csv_write(out/filename,items)
    def rate(m):
        return f"{m['wins']}/{m['valid']} = {m['win_rate']:.1%}" if m['win_rate'] is not None else '无有效样本'
    def percentage(value):return f'{value:.1%}' if value is not None else '证据不足'
    def seconds(value):return f'{value:.1f}' if value is not None else '无有效样本'
    text=['# 中大型挑战难度调整与独立复验','',
          f"本次新增{len(rows)}场战斗，{verification['valid']}场有效；最多三组候选与独立配对复验，未扩大样本或替换无效种子。玩家胜率为固定阵营完整AI代打，默认Abstract航空，不是人工玩家胜率。",'',
          '|关卡|目标|原20种子|最终配置原种子|最终配置新种子|新种子原配置|采用组|两批20有效且入带|',
          '|---|---|---|---|---|---|---|---|']
    for f in finals:
        text.append(f"|{f['code'].upper()}|{f['target']:.0%}±{f['tolerance']:.0%}|{rate(f['original_training'])}|{rate(f['training'])}|{rate(f['holdout'])}|{rate(f['holdout_baseline'])}|{f['retained_stage']}|{'是' if f['both_20_valid_and_in_band'] else '否'}|")
    text+=['','0组表示保留原配置。候选按原20种子距离目标更近选择，并列取较少改动；独立复验仅检查预先选中的候选，不据复验重新选组。通过保留条件也不代表两批进入目标带。', '',
           '## 全部训练候选','',
           '|关卡|组|胜率|距离目标（百分点）|相比原配置新增无效种子|',
           '|---|---|---|---|---|']
    for g in sorted((g for g in groups if g['split']=='training'),key=lambda g:(g['code'],g['stage'])):
        baseline_metric=next(f['original_training'] for f in finals if f['code']==g['code'])
        added=sorted(set(g['invalid_seeds'])-set(baseline_metric['invalid_seeds']))
        distance=f"{g['distance']*100:.1f}" if g['distance'] is not None else '无有效样本'
        text.append(f"|{g['code'].upper()}|{g['stage']}|{rate(g)}|{distance}|{added}|")
    text+=['','进入目标带且无新增技术无效种子的候选按规则提前停止；本批三次提前停止均20局有效。无合格训练改善时只复验原配置，不从独立复验重新挑选。L-02两批点估计均入带，但复验只有19局有效，完整样本门禁未通过。','',
           '## 配对比较与技术限制','',
           '下表仅含双方有效的完整配对。缺失配对保留在JSON；净变化为玩家阵营胜率变化，不是距离目标的变化。区间为固定分析种子的2000次配对bootstrap描述性区间，未作多重比较校正。', '',
           '|关卡|样本|候选组|完整配对|负→胜|胜→负|净胜率变化及95%区间|',
           '|---|---|---|---|---|---|---|']
    for c in comparisons:
        net=c['net_player_win_change'];lo,hi=c['paired_bootstrap95']
        text.append(f"|{c['code'].upper()}|{c['split']}|{c['stage']}|{c['complete_pairs']}|{c['loss_to_win']}|{c['win_to_loss']}|{percentage(net)} [{percentage(lo)}, {percentage(hi)}]|")
    text+=['','技术无效记录：`verification.json`；所有候选含拒绝组的完整结果均保留。技术无效不是败局，新增无效种子即拒绝该候选。公共导航、潜艇行为、性能和人工门禁仍未关闭。', '',
           '完成时长的中位数/分位数只含有效结算；行为、潜艇、航空和实际增援诊断保留全部尝试，含技术无效。CSV保留end_state可分层复查，报警和重复请求不能视为独立事故。', '',
           '## 最终配置逐关事实']
    for f in finals:
        reasons={'No eligible training improvement; retained baseline':'没有合格的训练改善，保留原配置',
                 'Training closer; paired holdout non-worsening; no added invalid seeds':'训练更接近目标，独立复验距离不变差，且无新增技术无效种子',
                 'Holdout failed retention rule; reverted without reselection':'独立复验未通过保留条件，回退原配置且未重新选组'}
        display_reason='按计划只复验原配置，作为参照' if f['code']=='l02' else reasons.get(f['reason'],f['reason'])
        text+=['',f"### {f['code'].upper()} · 采用第{f['retained_stage']}组",'',
               f"选择原因：{display_reason}。原种子95% Wilson区间 {percentage(f['training']['wilson95'][0])}–{percentage(f['training']['wilson95'][1])}，新种子 {percentage(f['holdout']['wilson95'][0])}–{percentage(f['holdout']['wilson95'][1])}。中位时长分别为{seconds(f['training']['median_duration'])}/{seconds(f['holdout']['median_duration'])}秒。"]
        if f['decision_details']:
            decision=f['decision_details']
            text+=['',f"拟选第{f['proposed_stage']}组的新种子胜率为{rate(decision['proposed_holdout'])}；新增技术无效种子：{decision['holdout_added_invalid_seeds']}。"]
        for wave in f['holdout_reinforcements']:
            text+=['',f"新种子实际增援：{wave['wave_id']} 最早{wave['earliest_time']}秒，实际入场{wave['entered_battles']}/{wave['attempts']}局；逐类伤害见groups.json。最早时间不等于实际入场时间，原生记录未提供独立入场时间字段。"]
        for label,key in [('原种子','training_diagnostics'),('新种子','holdout_diagnostics')]:
            d=f[key]
            text+=['',f"{label}：P10/P90时长{seconds(d['duration_p10'])}/{seconds(d['duration_p90'])}秒，卡住报警{d['path_stuck']}、路线失败{d['route_failures']}；潜艇实际零开火{d['submarine_zero_fire']}/{d['submarine_samples']}舰次，完整循环{d['submarine_full_cycles']}；航母零航空伤害{d['carrier_zero_aviation_damage']}/{d['carrier_samples']}舰次。最长已完成恢复{d['max_completed_recovery']:.1f}秒。", '',
                   '终局：'+'；'.join(f'{reason}×{count}' for reason,count in d['reasons'].items())+'。']
    text+=['','## 复现与统计语义','',
           f"冻结输入、原始报告、配置哈希及合同：`{base.relative_to(ROOT)}`。生成器和最终选择清单存于`tools/levels/`；每组原生报告有实际入场Cost、逐舰分类伤害、目标、导航和潜艇事实。",'',
           '逐舰resolved_attacks来自AttackResolved，不能解释成WeaponFired。潜艇weapon_fires才是实际开火；航母零航空伤害不等于零起飞。卡住报警不等于永久卡死；完成恢复按事实记录，终局未完成恢复保留为截尾。并行四进程只运行独立会话，不验证绝对CPU/GPU性能。所有结果为Candidate，不外推其他阵容、Physical航空、地图公平性或人工胜率。']
    (out/'summary.md').write_text('\n'.join(text)+'\n')
    print(json.dumps(verification,ensure_ascii=False,indent=2))


if __name__=='__main__':main()
