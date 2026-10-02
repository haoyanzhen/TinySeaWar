#!/usr/bin/env python3
"""Run the authorized, bounded M/L candidate and holdout experiment.

Writes isolated artifacts only. Never applies a selection to the working tree.
The prior frozen runtime is required, so presentation/parallel edits cannot drift
the control inputs while these long-running battles execute.
"""
from __future__ import annotations

import argparse
import concurrent.futures
import hashlib
import json
import math
from pathlib import Path
import shutil
import statistics
import subprocess
import threading
import time

ROOT = Path(__file__).resolve().parents[2]
CODES = [f'{chapter}{i:02}' for chapter in 'ml' for i in range(1, 6)]
TARGETS = [.6, .45, .3, .2, .1]
BUDGET = 920
EPSILON = 1e-9


def write_json(path, value):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2) + '\n')


def read_runs(path):
    return [json.loads(line) for line in path.read_text().splitlines() if line.strip()]


def summarize(runs, target):
    valid = [r for r in runs if r['end_state'] == 'Finished']
    wins = sum(r['winner_faction'] == 'player' for r in valid)
    n = len(valid)
    p = wins / n if n else None
    ci = [None, None]
    if n:
        z = 1.959963984540054
        d = 1 + z*z/n
        center = (p + z*z/(2*n))/d
        half = z*math.sqrt(p*(1-p)/n + z*z/(4*n*n))/d
        ci = [center-half, center+half]
    return {'attempts': len(runs), 'valid': n, 'wins': wins, 'win_rate': p,
            'distance': abs(p-target) if p is not None else None,
            'wilson95': ci, 'invalid_seeds': sorted(r['seed'] for r in runs if r['end_state'] != 'Finished'),
            'median_duration': statistics.median(r['duration'] for r in valid) if n else None}


def eligible(candidate, control):
    return candidate['win_rate'] is not None and set(candidate['invalid_seeds']) <= set(control['invalid_seeds'])


def in_target_band(candidate, control, tolerance):
    return eligible(candidate, control) and candidate['distance'] <= tolerance + EPSILON


def choose_candidate(control, candidates):
    if control['distance'] is None: return 0
    choices = [(stage, m) for stage, m in candidates.items()
               if eligible(m, control) and m['distance'] < control['distance']-EPSILON]
    return min(choices, key=lambda item: (round(item[1]['distance'], 12), item[0]))[0] if choices else 0


def retain_candidate(train_control, train_candidate, holdout_control, holdout_candidate):
    if train_control['distance'] is None or holdout_control['distance'] is None: return False
    return (eligible(train_candidate, train_control) and eligible(holdout_candidate, holdout_control)
            and train_candidate['distance'] < train_control['distance']-EPSILON
            and holdout_candidate['distance'] <= holdout_control['distance']+EPSILON)


PREFLIGHT = '''extends SceneTree
const Registry = preload("res://scripts/infrastructure/data/config_registry.gd")
const Session = preload("res://scripts/application/battle_session.gd")
func _init():
    var registry = Registry.new()
    if not registry.load_all():
        push_error(str(registry.errors))
        quit(1)
        return
    var failures = []
    var checks = 0
    for chapter in ["m", "l"]:
        for index in range(1, 6):
            var code = "%s%02d" % [chapter, index]
            var session = Session.new(registry)
            var created = session.create_battle("level.challenge." + code, 1)
            checks += 1
            if not created.get("ok", false):
                failures.append([code, created])
                continue
            var level = registry.get_definition("levels", "level.challenge." + code)
            for faction in ["player", "enemy"]:
                var other = "enemy" if faction == "player" else "player"
                var target = session.state.units_by_id[session.state.fleets_by_id["fleet." + other].flagship_unit_id]
                for member in level[faction + "_fleet"]:
                    var unit = session.state.units_by_id[member.entity_id]
                    checks += 2
                    if not session.terrain_query.can_occupy_circle(unit.position, unit.stats.collision_radius, session._movement_tags(unit)):
                        failures.append([code, unit.entity_id, "illegal actual hull"])
                    var path = session.route_planner.plan_path(session.terrain_query, session.navigation_definition, unit.position, target.position, unit.stats.collision_radius, session._movement_tags(unit), session.terrain_context_service)
                    if not path.get("ok", false) or path.get("target_projected", false):
                        failures.append([code, unit.entity_id, "disconnected actual hull", path])
    print("BALANCE_PREFLIGHT %d checks failures=%s" % [checks, failures])
    quit(0 if failures.is_empty() else 1)
'''


class Experiment:
    def __init__(self, baseline, output):
        self.baseline = baseline
        self.output = output
        self.lock = threading.Lock()
        self.dispatched = 0
        self.results = {}
        self.started = time.time()
        self.stages = {stage: output / f'stage{stage}' / 'frozen' for stage in range(4)}

    def status(self, state='running'):
        write_json(self.output/'pipeline_status.json', {'state': state, 'dispatched_battles': self.dispatched,
                   'budget': BUDGET, 'wall_seconds': time.time()-self.started, 'levels': self.results})

    def prepare(self):
        if self.output.exists():
            raise ValueError('Output exists; refusing to overwrite prior experiments')
        self.output.mkdir(parents=True)
        contract = {'authorization': 'User 2026-10-01 explicitly requested implementation of approved tuning plan',
                    'baseline': str(self.baseline), 'maximum_new_battles': BUDGET,
                    'candidate_stages': [1,2,3], 'holdout_seed_offset': 20, 'count_per_group': 20,
                    'side_swap': False, 'policies': ['LatestRuntimeAI','LatestRuntimeAI'],
                    'aviation': 'default Abstract', 'kind': 'FullBattleSimulation',
                    'selection': 'strict training distance improvement; tie chooses lower stage; invalid seed subset',
                    'holdout': 'distance non-worsening and no added invalid seed versus paired baseline; no reselection',
                    'stop': 'target band with no added invalid seed, or 3 candidates',
                    'formal_status': 'Candidate / behavior, performance and human gates remain open'}
        write_json(self.output/'experiment_contract.json', contract)
        # Verify that the old measurement still describes the shared runtime.
        drift = []
        instrumented = Path('scripts/application/simulation/simulation_runner.gd')
        for base in ['scripts/domain','scripts/application','scripts/infrastructure','data']:
            for file in (ROOT/base).rglob('*'):
                rel = file.relative_to(ROOT)
                old = self.baseline/'frozen'/rel
                if file.is_file() and file.suffix in ['.gd','.json','.tscf'] and rel != instrumented:
                    if not old.exists() or old.read_bytes() != file.read_bytes():
                        drift.append(str(rel))
        write_json(self.output/'baseline_drift_check.json', {'changes': drift, 'checkpoint_only_exception': str(instrumented)})
        if drift:
            raise ValueError(f'Baseline runtime drift; must rebuild comparison before tuning: {drift}')
        for stage, frozen in self.stages.items():
            shutil.copytree(self.baseline/'frozen', frozen)
            shutil.copytree(ROOT/'tools/terrain', frozen/'tools/terrain', dirs_exist_ok=True)
            minimap=Path('assets/ui/processed/battle/terrain/terrain_minimap_manifest.json')
            (frozen/minimap).parent.mkdir(parents=True,exist_ok=True)
            shutil.copy2(ROOT/minimap,frozen/minimap)
            (frozen/'tools/levels').mkdir(parents=True, exist_ok=True)
            for name in ['build_challenge_levels.py','challenge_balance_selection.json','tune_challenge_difficulty.py']:
                shutil.copy2(ROOT/'tools/levels'/name, frozen/'tools/levels'/name)
            with (frozen.parent/'generation.log').open('w') as log:
                subprocess.run(['uv','run','--locked','python','tools/levels/build_challenge_levels.py',
                                '--output-root',str(frozen),'--candidate-stage',str(stage)],
                               cwd=ROOT, stdout=log, stderr=subprocess.STDOUT, check=True)
            original = json.loads((self.baseline/'frozen/data/terrain/authoring/challenge_deployment_evidence.json').read_text())['levels']
            evidence = json.loads((frozen/'data/terrain/authoring/challenge_deployment_evidence.json').read_text())['levels']
            assert [d['geometry_sha256'] for d in original] == [d['geometry_sha256'] for d in evidence]
            (frozen/'balance_preflight.gd').write_text(PREFLIGHT)
            with (frozen.parent/'preflight.log').open('w') as log:
                subprocess.run(['godot','--headless','--path',str(frozen),'--script','balance_preflight.gd'],
                               stdout=log, stderr=subprocess.STDOUT, check=True)
            hashes = {str(p.relative_to(frozen)): hashlib.sha256(p.read_bytes()).hexdigest()
                      for prefix in ['scripts','data','tools/levels'] for p in (frozen/prefix).rglob('*') if p.is_file()}
            write_json(frozen.parent/'source_sha256.json', hashes)
            print(f'PREPARED stage{stage}', flush=True)
        self.status()

    def run(self, code, stage, split):
        frozen = self.stages[stage]
        directory = self.output/split/f'stage{stage}'/code
        directory.mkdir(parents=True)
        manifest = json.loads((self.baseline/f'frozen/difficulty_manifests/{code}.json').read_text())
        manifest.update(experiment_id=f'sim.tuning.{code}.20261001.{split}.stage{stage}',
                        authorization='用户2026-10-01明确授权：最多三组候选及独立20种子配对复验，最多920局',
                        description=f'{code} stage{stage} {split}; Candidate, not formal acceptance',
                        output_directory=str(directory))
        if split == 'holdout': manifest['seed_plan']['start'] += 20
        manifest_path = frozen/f'tuning_manifests/{split}_{code}.json'
        write_json(manifest_path, manifest)
        write_json(directory/'manifest.json', manifest)
        with self.lock:
            if self.dispatched + 20 > BUDGET: raise ValueError('Authorized battle budget exhausted')
            self.dispatched += 20
            self.results.setdefault(code, {})['active'] = {'stage':stage, 'split':split, 'output':str(directory)}
            self.status()
        start = time.time()
        with (directory/'execution.log').open('w') as log:
            result = subprocess.run(['godot','--headless','--path',str(frozen),'--script',
                                     'tools/simulation/run_experiment.gd','--',str(manifest_path)],
                                    stdout=log, stderr=subprocess.STDOUT)
        write_json(directory/'execution_status.json', {'exit_code':result.returncode, 'wall_seconds':time.time()-start})
        if result.returncode not in [0,2]: raise ValueError(f'Execution failed: {directory}')
        log = (directory/'execution.log').read_text()
        if 'SCRIPT ERROR' in log or 'ERROR:' in log: raise ValueError(f'Runtime error: {directory}')
        runs = read_runs(directory/'runs.jsonl')
        start_seed = manifest['seed_plan']['start']
        assert len(runs)==20 and sorted(r['seed'] for r in runs)==list(range(start_seed,start_seed+20))
        assert len({r['run_id'] for r in runs}) == 20
        assert runs == read_runs(directory/'progress.jsonl')
        target = TARGETS[int(code[1:])-1]
        metrics = summarize(runs, target)
        aggregate = json.loads((directory/'aggregate.json').read_text())
        assert aggregate['planned_runs']==20 and aggregate['finished_runs']==metrics['valid']
        assert aggregate['player_wins']==metrics['wins']
        write_json(directory/'metrics.json', metrics)
        print(json.dumps({'code':code,'stage':stage,'split':split, **metrics}), flush=True)
        with self.lock:
            self.results[code].setdefault(split,{})[str(stage)] = metrics
            self.status()
        return metrics

    def run_level(self, code):
        target = TARGETS[int(code[1:])-1]
        tolerance = .03 if code.endswith('5') else .05
        control = summarize(read_runs(self.baseline/code/'runs.jsonl'), target)
        tested = {}
        if code != 'l02':
            for stage in [1,2,3]:
                metric = self.run(code, stage, 'training')
                tested[stage] = metric
                if in_target_band(metric, control, tolerance):
                    break
        chosen = choose_candidate(control, tested)
        with self.lock:
            self.results.setdefault(code,{})['training_baseline'] = control
            self.results[code]['proposed_stage'] = chosen
            self.status()
        holdout_control = self.run(code, 0, 'holdout')
        retained = 0
        reason = 'No eligible training improvement; retained baseline'
        if chosen:
            holdout_candidate = self.run(code, chosen, 'holdout')
            if retain_candidate(control, tested[chosen], holdout_control, holdout_candidate):
                retained = chosen
                reason = 'Training closer; paired holdout non-worsening; no added invalid seeds'
            else:
                reason = 'Holdout failed retention rule; reverted without reselection'
        with self.lock:
            self.results[code].update(retained_stage=retained, reason=reason, active=None)
            self.status()
        return retained

    def execute(self):
        self.prepare()
        with concurrent.futures.ThreadPoolExecutor(max_workers=4) as pool:
            selections = dict(zip(CODES, pool.map(self.run_level, CODES)))
        write_json(self.output/'selection_final.json', {'schema_version':1,
                   'status':'Candidate / independent verification completed; formal gates remain open',
                   'experiment_directory':str(self.output), 'selected_stages':selections})
        self.status('completed')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--baseline', type=Path, default=ROOT/'artifacts/simulations/challenge_ml_difficulty_20261001')
    parser.add_argument('--output', type=Path, default=ROOT/'artifacts/simulations/challenge_ml_tuning_20261001')
    args = parser.parse_args()
    experiment = Experiment(args.baseline.resolve(), args.output.resolve())
    try:
        experiment.execute()
    except Exception:
        with experiment.lock: experiment.status('failed')
        raise


if __name__ == '__main__':
    main()
