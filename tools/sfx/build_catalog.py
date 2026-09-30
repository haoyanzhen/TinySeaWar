"""Build production-only catalog; never a runtime event manifest."""
import json, re
from pathlib import Path
ROOT = Path(__file__).resolve().parents[2]
SOURCE = ROOT / 'tools/sfx/catalog_source.tsv'
OUT = ROOT / 'tools/sfx/batch_20260930.json'
REUSE = {
'A04':['W12b','W12c','W13b'], 'A07':['N10','K09','U02'], 'A08':['K09'],
'N14':['U11'], 'N15':['U05c'], 'E07':['E02b'], 'E09':['N09'],
'E11':['E10a','E10b'], 'E15':['N10'], 'F06':['U02','U05a'],
'F08':['U04b','A01','N11a','U02'], 'U13':['U01','U02','U05a'],
'U15':['U01','U02'], 'U17':['U01'], 'F10':['W14'],
}
SILENT = {'W20':'无公开精确事实，暂缓专属跳弹/互撞声', 'K10':'专属演出/语音另立制作，不制作喊招',
'E08':'无独立物理声源，用混音变化表达', 'F12':'首轮设备持续工作静默', 'U16':'高频悬停/镜头/调试默认静默'}

def build():
    briefs_path = ROOT / 'tools/sfx/english_briefs.json'
    briefs = json.loads(briefs_path.read_text()) if briefs_path.exists() else {}
    assets = []
    for line in SOURCE.read_text().splitlines():
        if not line or line.startswith('#'): continue
        id_, category, title, duration, character = line.split('|')
        duration = float(duration)
        loop = duration >= 8
        prompt = briefs.get(id_)
        assets.append(dict(id=id_, category=category, title=title, target_seconds=duration,
            generation_seconds=max(3.0, duration + (0 if loop else 1)), loop=loop,
            direction=character, english_brief=prompt,
            candidates=[dict(id=f'{id_}_{v}', seed=2026093000+i*10+j,
                variation=style, prompt=(prompt + '. ' + suffix) if prompt else None,
                status='planned') for j,(v,style,suffix) in enumerate([
                ('a','干净短促','Clean dry close sound, controlled transient, minimal reverberation.'),
                ('b','厚实机械','Fuller warm body and detailed texture, controlled low end, clear separation.'),
                ('c','柔和耐听','Softer rounded high frequencies, restrained tail, suitable for repeated game playback.')]) for i in [len(assets)] ]))
    ids = {a['id'] for a in assets}
    rows = []
    text = (ROOT/'workorder/20260929-sound-effects-inventory-and-integration.md').read_text()
    for m in re.finditer(r'^\| ([WASKNEFU]\d{2}) \| ([^|]+) \| ([^|]+) \| ([^|]+) \|', text, re.M):
        id_, title, trigger, note = [x.strip() for x in m.groups()]
        targets = sorted(x for x in ids if re.match(r'^'+id_+r'[a-z]?$',x)) + REUSE.get(id_,[])
        if id_ == 'F07': targets += ['W02','W03','W13a','W13b']
        if id_ == 'F09': targets += ['U02']
        assert targets or id_ in SILENT, id_
        rows.append(dict(id=id_, title=title, assets=targets, status='silent_deferred' if not targets else 'planned',
            reason=SILENT.get(id_, '制作候选；实际触发仍须观察过滤、语义判定与去重'), trigger=trigger, constraints=note))
    assert len(rows)==105 and len({r['id'] for r in rows})==105
    assert all(x in ids for r in rows for x in r['assets'])
    batch = dict(id='sfx_20260930_v1', version=1, backend='stabilityai/stable-audio-3-small-sfx',
        status='planned_not_generated', source='workorder/20260929-sound-effects-inventory-and-integration.md',
        candidates_per_asset=3, sample_rate_source=44100, sample_rate_delivery=48000,
        steps=8, guidance_scale=1.0, assets=assets, requirements=rows)
    OUT.write_text(json.dumps(batch,ensure_ascii=False,indent=2)+'\n')
    print(f'{len(rows)} requirements, {len(assets)} assets, {len(assets)*3} candidates; English briefs {len(briefs)}')
if __name__=='__main__': build()
