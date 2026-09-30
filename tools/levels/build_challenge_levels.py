#!/usr/bin/env python3
"""Build M/L challenges from approved coastal geometry; never alter shared maps.

Navigation profiles are copied only because rules geometry is byte-identical.
Spawn projection uses the largest 46-radius deep-water connected component;
Godot integration tests additionally check actual hull/draft and runtime loading.
"""
from __future__ import annotations
import argparse, copy, json, math, sys, hashlib
from pathlib import Path
ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT/'tools/terrain'))
from bake_collision_fields import bake_field
from bake_navigation_graph import _segment_clear
W,H=6144,3456
BASE='hood warspite hindenburg prinz_eugen san_diego sirius chongqing yukikaze shimakaze u_47 argus'
MBASE='hood san_diego chongqing yukikaze hai_shih'
# code, title, template, palette, deployment, player, enemy, objective suffix
ROWS=[
('m01','港湾扩编','harbor_mouth','rain_dawn','SN',MBASE,'warspite kirov sirius gnevny ward','harbor'),
('m02','泻湖护航','ring_lagoon','rain_dusk','SN','warspite san_diego kirov hosho anshan','bismarck prinz_eugen yukikaze ward argus','carrier_escort'),
('m03','群岛雷击','long_archipelago','rain_night','WE',MBASE,'iowa hindenburg hosho gnevny anshan','flanks'),
('m04','风暴猎场','scattered_islands','thunderstorm_day','WE','warspite san_diego kirov shimakaze argus','bismarck san_diego shimakaze u_47 argus','storm'),
('m05','海峡封锁','double_island_long_channel','thunderstorm_dawn','SN',MBASE,'iowa hindenburg san_diego shimakaze u_47','blockade'),
('l01','舰队展开','central_sandbar','clear_day','WE',BASE,'warspite iowa kirov prinz_eugen aurora ning_hai anshan gnevny ward hosho hai_shih','deployment'),
('l02','岛侧航空走廊','offset_large_island','cloudy_day','WE',BASE,'san_diego sirius kirov prinz_eugen yukikaze anshan enterprise_cv6 ward pobeda hai_shih argus','air_corridor'),
('l03','双航道巨炮','dual_channel_reef_line','overcast_day','WE',BASE,'yamato bismarck iowa hindenburg prinz_eugen yukikaze gnevny ward hai_shih san_diego sirius','gun_lane'),
('l04','风暴群岛合围','long_archipelago','thunderstorm_dusk','WE',BASE,'iowa bismarck hood hindenburg prinz_eugen san_diego chongqing yukikaze shimakaze u_47 enterprise_cv6','encirclement'),
('l05','雷夜环礁终局','broken_atoll','thunderstorm_night','WE','iowa enterprise_cv6 pobeda bismarck yamato hood hindenburg san_diego shimakaze u_47 chongqing','yamato bismarck iowa enterprise_cv6 pobeda hindenburg prinz_eugen san_diego shimakaze u_47 yukikaze','finale')]
WAVES={'m04':[(150,'ward','RN')],'m05':[(120,'pobeda','RS')],'l04':[(210,'gnevny','RN')],'l05':[(180,'hood','RN'),(300,'hai_shih','RS')]}
PROTECT={'m02':['hosho'],'l02':['argus'],'l04':['argus']}
MASTERY={'m02':[['argus'],['bismarck']],'m03':[['gnevny','anshan'],['iowa']],'l02':[['pobeda','argus'],['enterprise_cv6']],'l03':[['yukikaze','hai_shih'],['yamato']]}
# Rectangles are author coordinates normalized to the approved coastline.
ZONES={
'm01':[('tidal_water',(.355,.62,.442,.88)),('lee_water',(.34,.59,.66,.92))],
'm02':[('sea_fog',(.39,.37,.61,.63))],
'm03':[('strong_current',(.25,.18,.75,.30),0),('strong_current',(.25,.70,.75,.82),180),('moonlit_lane',(.43,.40,.57,.60))],
'm04':[('high_sea',(.1,.04,.9,.20)),('high_sea',(.1,.80,.9,.96)),('lee_water',(.30,.30,.43,.50)),('lee_water',(.57,.50,.70,.70))],
'm05':[('rain_squall',(.38,.40,.52,.60),0),('lee_water',(.40,.70,.60,.88)),('lee_water',(.40,.12,.60,.30))],
'l01':[],
'l02':[('strong_current',(.23,.12,.78,.28),0)],
'l03':[('high_sea',(.22,.04,.78,.18)),('high_sea',(.22,.82,.78,.96)),('lee_water',(.35,.28,.65,.39)),('lee_water',(.35,.61,.65,.72))],
'l04':[('rain_squall',(.27,.20,.42,.34),0),('rain_squall',(.58,.66,.73,.80),180),('lee_water',(.39,.39,.48,.52)),('lee_water',(.52,.48,.61,.61))],
'l05':[('high_sea',(.1,.04,.9,.18)),('high_sea',(.1,.82,.9,.96)),('moonlit_lane',(.65,.38,.78,.62)),('strong_current',(.65,.41,.82,.59),180)]}
def read(p): return json.loads((ROOT/p).read_text())
def write(p,obj,check=False):
 text=json.dumps(obj,ensure_ascii=False,indent=2)+'\n'; path=ROOT/p
 if check:
  if not path.exists() or path.read_text()!=text: raise ValueError(f'stale generated file: {p}')
 else: path.parent.mkdir(parents=True,exist_ok=True);path.write_text(text)
def doc(items): return {'schema_version':1,'definitions':items}
def component(profile):
 nodes={n['id']:n for n in profile['nodes']};left=set(nodes);groups=[]
 while left:
  todo=[min(left)];seen=set(todo);left.difference_update(todo)
  while todo:
   for n in nodes[todo.pop()]['neighbors']:
    if n in left: left.remove(n);seen.add(n);todo.append(n)
  groups.append(seen)
 return [nodes[k] for k in sorted(max(groups,key=lambda g:(len(g),min(g))))]
def candidates(count,axis):
 if count==5:
  return [(W*x,H*y) for x,y in ([(.5,.8),(.4,.84),(.6,.84),(.3,.88),(.7,.88)] if axis=='SN' else [(.2,.5),(.17,.34),(.17,.66),(.22,.2),(.22,.8)])]
 return [(W*x,H*y) for x,y in [(.18,.5),(.18,.38),(.18,.62),(.15,.26),(.15,.74),(.21,.3),(.21,.7),(.24,.42),(.24,.58),(.12,.36),(.12,.64)]]
def main():
 parser=argparse.ArgumentParser();parser.add_argument('--check',action='store_true');parser.add_argument('--bake-fields',action='store_true');args=parser.parse_args()
 terrains={d['id']:d for d in read('data/terrain/terrain_definitions.json')['definitions']};navs={d['id']:d for d in read('data/terrain/navigation_definitions.json')['definitions']}
 ships={d['id']:d for f in (ROOT/'data/ships').glob('*.json') for d in json.loads(f.read_text())['definitions']}
 levels=[];maps=[];graphs=[];envs=[];objectives=[];evidence=[];fields=[]
 for code,title,template,palette,axis,player,enemy,suffix in ROWS:
  n=5 if code[0]=='m' else 11;terrain=copy.deepcopy(terrains[f'terrain.map.{template}_16x9']);nav=copy.deepcopy(navs[terrain['navigation_definition_id']]);source_id=terrain['id']
  terrain.update(id=f'terrain.map.challenge_{code}',display_name=f'{code.upper()} {title}',facility_layout_id='',facility_anchors=[],environment_zone_set_id=f'environment.zone_set.challenge_{code}',navigation_definition_id=f'navigation.challenge_{code}',collision_field_id=f'collision_field.terrain.map.challenge_{code}',source_document='res://tools/levels/build_challenge_levels.py',spawn_points=[])
  nav.update(id=terrain['navigation_definition_id'],terrain_definition_id=terrain['id'])
  nodes=component(next(p for p in nav['profiles'] if p['id'].endswith('large_deep')))
  occupied=[]
  def project(point,faction):
   eligible=[x for x in nodes if (x['position'][1]>H*.62 if faction=='player' else x['position'][1]<H*.38)] if axis=='SN' else [x for x in nodes if (x['position'][0]<W*.35 if faction=='player' else x['position'][0]>W*.65)]
   for node in sorted(eligible,key=lambda x:(math.dist(point,x['position']),x['id'])):
    pos=node['position']
    if all(math.dist(pos,p)>=180 for p in occupied) and _segment_clear(pos,pos,46,terrain['obstacles'],terrain['regions'],{'Surface'}):
     occupied.append(pos);return pos,node['id']
   raise ValueError(f'No connected legal spawn {code}/{faction}/{point}')
  level={'id':f'level.challenge.{code}','display_name':f'{code[0].upper()}-{code[1:]} {title}','battle_mode':'ChallengeBattle','objective_set_id':f'objective.{code}_{suffix}','enemy_ai_profile_id':'ai.profile.'+('hard' if int(code[1:])>=4 else 'standard'),'map':{'width':W,'height':H,'ocean_palette':palette,'terrain_definition_id':terrain['id'],'navigation_definition_id':nav['id'],'environment_zone_set_id':terrain['environment_zone_set_id'],'facility_layout_id':''},'time_limit':1200.0}
  cost={};positions=[]
  for faction,roster in [('player',player),('enemy',enemy)]:
   level[faction+'_fleet']=[];cost[faction]=0
   flagship='enterprise_cv6' if code=='l02' and faction=='enemy' else roster.split()[0]
   for i,(ship,point) in enumerate(zip(roster.split(),candidates(n,axis))):
    if faction=='enemy':point=(point[0],H-point[1]) if axis=='SN' else (W-point[0],point[1])
    pos,node=project(point,faction);heading=(270 if faction=='player' else 90) if axis=='SN' else (0 if faction=='player' else 180)
    member={'entity_id':f'unit.{faction}.{code}.{ship}','ship_id':'ship.'+ship,'position':pos,'heading':heading,'is_flagship':ship==flagship}
    level[faction+'_fleet'].append(member);cost[faction]+=ships['ship.'+ship]['cost'];positions.append({'unit_id':member['entity_id'],'node_id':node,'position':pos,'candidate':point})
    terrain['spawn_points'].append({'id':f'{faction}_{i+1}','faction_id':faction,'position':pos,'heading':heading,'radius':46.0,'movement_tags':['Surface']})
  if n==5:
   for faction in ['player','enemy']:
    for i in range(5,11):
     point=(W*(.22+.04*(i%3)),H*(.72+.06*(i//3))) if axis=='SN' else (W*(.12+.04*(i%3)),H*(.2+.12*(i-5)))
     if faction=='enemy':point=(point[0],H-point[1]) if axis=='SN' else (W-point[0],point[1])
     pos,_=project(point,faction)
     terrain['spawn_points'].append({'id':f'{faction}_{i+1}','faction_id':faction,'position':pos,'heading':(270 if faction=='player' else 90) if axis=='SN' else (0 if faction=='player' else 180),'radius':46,'movement_tags':['Surface']})
  for index,(time,ship,point_id) in enumerate(WAVES.get(code,[])):
   candidate=(W*(.32 if point_id=='RN' else .68),H*.08) if axis=='SN' else (W*.92,H*(.18 if point_id=='RN' else .82))
   pos,node=project(candidate,'enemy');member={'entity_id':f'unit.enemy.{code}.{ship}_reserve','ship_id':'ship.'+ship,'position':pos,'heading':90 if axis=='SN' else 180,'is_flagship':False}
   level.setdefault('reinforcement_waves',[]).append({'wave_id':f'wave.{code}.{index+1:02}','faction_id':'enemy','earliest_time':time,'concurrent_unit_cap':n,'spawn_point_id':point_id,'spawn_display_name':('北侧西口' if point_id=='RN' else '北侧东口') if axis=='SN' else ('东侧北口' if point_id=='RN' else '东侧南口'),'members':[member]})
   terrain['spawn_points'].append({'id':point_id,'faction_id':'enemy','position':pos,'heading':member['heading'],'radius':46,'movement_tags':['Surface']});positions.append({'unit_id':member['entity_id'],'node_id':node,'position':pos,'candidate':candidate})
  target=next(m['entity_id'] for m in level['enemy_fleet'] if m['is_flagship']);pflag=level['player_fleet'][0]['entity_id']
  obj={'id':level['objective_set_id'],'objective_kind':'ChallengeMission','title':level['display_name'],'completion_text':'完成全部任务目标','failure_text':'保护条件失效，任务取消','required_enemy_unit_ids':[target],'protected_player_unit_ids':[pflag]+[f'unit.player.{code}.{s}' for s in PROTECT.get(code,[])]}
  target_name=ships[next(m['ship_id'] for m in level['enemy_fleet'] if m['is_flagship'])]['display_name']
  protected_names=[ships['ship.'+id.split('.')[-1]]['display_name'] for id in obj['protected_player_unit_ids']]
  obj['completion_text']='击沉'+target_name+('，累计击沉至少'+('4' if code=='m05' else '8')+'艘敌舰（含旗舰）' if code in ['m05','l05'] else '')
  obj['failure_text']='、'.join(protected_names)+'任一沉没'+('，或己方第3艘舰沉没' if code=='m04' else '')
  obj['description']={'m01':'前卫侦查，主力推进；涨潮捷径与外侧深水路线均可选择。','m02':'保护凤翔；选择直接击沉敌旗舰，或先削弱敌方航空支援。','m03':'分路观察并利用流向雷击；拆除两翼仅为可选精通。','m04':'争取背风水域，集中突破；旗舰须存活，最多损失两舰。','m05':'突破封锁，累计击沉四舰；敌旗舰沉没后可能仍需继续交战。','l01':'前卫、主力、后卫分组展开；集中一翼或保持双翼观察。','l02':'保护己方百眼巨人；快速斩首或先拆敌方两艘护航航母。','l03':'主力牵制一条航道，雷击侧翼争取另一条；无需强制追杀潜艇。','l04':'打穿一翼并保持后卫支援；胡德与百眼巨人都必须存活。','l05':'保护衣阿华并分配火力；击沉大和且累计八舰即可结束。'}[code]
  if code in MASTERY:obj['optional_enemy_sunk_stages']=[[f'unit.enemy.{code}.{s}' for s in stage] for stage in MASTERY[code]]
  if code in ['m05','l05']:obj['minimum_enemy_sunk']=4 if code=='m05' else 8
  if code=='m04':obj.update(required_any_player_unit_ids=[m['entity_id'] for m in level['player_fleet']],minimum_required_any_player_alive=3)
  env={'id':terrain['environment_zone_set_id'],'definition_type':'EnvironmentZoneSet','global_environment':{'seed_offset':91000+len(levels)},'zones':[]}
  if code=='m01':env['global_environment']['tide']={'initial_phase':'Flood','phases':['Flood','High','Ebb','Low'],'phase_duration':45,'open_phases':['Flood','High']}
  for i,z in enumerate(ZONES[code]):
   effect,rect,*heading=z;x1,y1,x2,y2=rect;zone={'id':f'zone.{code}.{i}','effect_id':'environment.effect.'+effect,'polygon':[[W*x1,H*y1],[W*x1,H*y2],[W*x2,H*y2],[W*x2,H*y1]],'position':[0,0],'heading':heading[0] if heading else 0,'drift_speed':0,'intensity':1.0,'phase':'Stable','duration':0,'public_trend':'Stable'}
   if effect=='rain_squall':zone.update(drift_speed=3.0,drift_path=[[0,0],[900 if zone['heading']==0 else -900,0]],public_trend='DriftingEast' if zone['heading']==0 else 'DriftingWest')
   env['zones'].append(zone)
  if palette.startswith('thunderstorm'):
   timeline='environment.timeline.challenge_'+code;rain=palette.replace('thunderstorm','rain');level['map']['environment_timeline_id']=timeline
   envs.append({'id':timeline,'definition_type':'EnvironmentTimeline','display_name':title+'·雷雨过境','forecast_seconds':10,'stages':[{'start_seconds':t,'ocean_palette':p} for t,p in [(0,palette),(60,rain),(240,palette),(300,rain)]]})
  envs.append(env);levels.append(level);maps.append(terrain);graphs.append(nav);objectives.append(obj)
  evidence.append({'level':level['id'],'source_terrain':source_id,'geometry_sha256':hashlib.sha256(json.dumps({k:terrain[k] for k in ['obstacles','regions','visual_instances']},sort_keys=True).encode()).hexdigest(),'spawn_projection':'nearest connected 46-radius deep-water node; separation >=180','positions':positions,'initial_cost':cost,'enemy_total_cost':cost['enemy']+sum(ships['ship.'+s]['cost'] for _,s,_ in WAVES.get(code,[]))})
  base_seed=(91001 if code[0]=='m' else 92001)+(int(code[1:])-1)*100
  experiment={'schema_version':1,'experiment_id':f'sim.level.{code}.win_rate_20','description':title+'正式二十种子验收','authorization':'用户2026-09-30授权十关实现、20种子验收及设计范围内调参','simulation_kind':'LevelWinRateEvaluation','player_policy_id':'LatestRuntimeAI','enemy_policy_id':'LatestRuntimeAI','ai_profile_id':level['enemy_ai_profile_id'],'side_swap':False,'tick_seconds':.1,'maximum_ticks':12000,'seed_plan':{'type':'SequentialRange','start':base_seed,'count':20},'win_rate_evaluation':{'settlement_source':'BattleStatisticsReport','target_player_win_rate':[.6,.45,.3,.2,.1][int(code[1:])-1],'tolerance':.03 if code.endswith('5') else .05},'scenarios':[{'scenario_id':'challenge_'+code,'level_definition_id':level['id']}],'output_directory':f'res://artifacts/simulations/challenge_ml_20260930/v4/{code}'}
  write(f'data/simulations/experiments/level_{code}_win_rate_20.json',experiment,args.check)
  if args.bake_fields:
   path=f'data/terrain/collision_fields/challenge_{code}.tscf';fields.append(bake_field(terrain,ROOT/path,8,path));print('baked',code,flush=True)
 for chapter in ['m','l']:write(f'data/levels/formal_challenge_{chapter}_levels.json',doc([l for l in levels if l['id'].split('.')[-1].startswith(chapter)]),args.check)
 for path,data in [('data/terrain/challenge_terrains.json',maps),('data/terrain/challenge_navigation.json',graphs),('data/environments/challenge_environments.json',envs),('data/objectives/challenge_ml_objectives.json',objectives)]:write(path,doc(data),args.check)
 masks={m['terrain_definition_id']:m for m in read('assets/ui/processed/battle/terrain/terrain_minimap_manifest.json')['masks']}
 write('assets/ui/processed/battle/terrain/challenge_minimap_manifest.json',{'schema_version':1,'masks':[dict(masks[e['source_terrain']],terrain_definition_id='terrain.map.challenge_'+e['level'].split('.')[-1]) for e in evidence]},args.check)
 write('data/terrain/authoring/challenge_deployment_evidence.json',{'levels':evidence},args.check)
 if args.bake_fields:write('data/terrain/challenge_collision_fields.json',doc(fields),args.check)
 print('Validated/generated ten challenges')
if __name__=='__main__': main()
