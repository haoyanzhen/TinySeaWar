#!/usr/bin/env python3
"""Derive PCM16 runtime resources from immutable selected masters (no GPU/reports dependency)."""
import array, hashlib, json, pathlib, re, subprocess, sys, wave
ROOT = pathlib.Path(__file__).resolve().parents[2]
SOURCE = ROOT / 'assets/audio/sfx/source/selected_20261001_v1'
DEST = ROOT / 'assets/audio/sfx/runtime'
def sha(p): return hashlib.sha256(p.read_bytes()).hexdigest()
def definitions(folder):
    return [d for p in sorted((ROOT/'data'/folder).glob('*.json')) for d in json.loads(p.read_text()).get('definitions', [])]
def main():
    source = json.loads((SOURCE/'manifest.json').read_text())
    assets = {}
    DEST.mkdir(parents=True, exist_ok=True)
    for item in source['assets']:
        original = SOURCE/item['selected']['path']
        assert sha(original) == item['selected']['sha256']
        channels = 2 if item['category'] in ('ambience', 'alert', 'ui') or item['id'] in ('S03a','S03b') else 1
        samples = array.array('f')
        samples.frombytes(subprocess.check_output(['ffmpeg','-v','error','-i',str(original),'-f','f32le','-ar','48000','-ac',str(channels),'-']))
        if sys.byteorder != 'little': samples.byteswap()
        frames = len(samples)//channels
        crossfade = min(24000, frames//8) if item['loop'] else 0
        if crossfade:
            # Place tail->head overlap first; its last frame continues into the unmodified body.
            start = array.array('f')
            for f in range(crossfade):
                t = f/max(1,crossfade-1)
                for c in range(channels):
                    start.append(samples[(frames-crossfade+f)*channels+c]*(1-t)+samples[f*channels+c]*t)
            samples = start + samples[crossfade*channels:(frames-crossfade)*channels]
        pcm = array.array('h', (round(max(-1,min(1,s))*32767) for s in samples))
        if sys.byteorder != 'little': pcm.byteswap()
        target = DEST/item['category']/(item['id'].lower()+'.wav')
        target.parent.mkdir(parents=True,exist_ok=True)
        with wave.open(str(target),'wb') as out:
            out.setnchannels(channels); out.setsampwidth(2); out.setframerate(48000); out.writeframes(pcm.tobytes())
        bus = 'Ambience' if item['category']=='ambience' else ('UI' if item['category']=='ui' else ('Alerts' if item['category'] in ('alert','facility') or item['id'] in ('S03a','S03b') else 'Combat'))
        assets[item['id']] = dict(path='res://'+str(target.relative_to(ROOT)),bus=bus,loop=item['loop'],gain_db=-18 if bus=='Ambience' else (-12 if bus=='Combat' else -8),priority=90 if item['id'] in ('S04','N06') else (60 if bus=='Alerts' else (50 if bus=='UI' else (35 if item["category"]=="impact" else 20))),duration=len(pcm)/channels/48000,source_sha256=sha(original),sha256=sha(target),crossfade_frames=crossfade,channels=channels)
    weapons={}
    for w in definitions('weapons'):
        kind=w.get('mount_type')
        match=re.search(r'(\d+(?:\.\d+)?)\s*(?:毫米|mm)', w.get('display_name','')) or re.search(r'_(\d{2,3})(?:_|$)',w['id'])
        caliber=float(match[1]) if match else 0
        fire={'Torpedo':'W05','AntiSubmarine':'W07a','Aviation':'A01','AntiAir':'W09' if caliber<76 else 'W10a'}.get(kind)
        if kind=='Gun':
            assert caliber>0 or w['id']=='weapon.hood_secondary', w['id']
            fire='W04' if caliber>=450 else ('W03' if caliber>=280 else ('W02' if caliber>=140 else 'W01'))
        assert fire, w
        weapons[w['id']]=dict(fire=fire,mount_type=kind,caliber_mm=caliber,aviation_payload=w.get("aviation_payload", ""))
    ships={s['id']:dict(weapons=s['weapon_mounts'],skill_id=s.get('skill_id','')) for s in definitions('ships')}
    skills={s['id']:dict(sound=None,reason='K01–K09 cancelled; actual weapon/aircraft facts only') for s in definitions('skills')}
    manifest=dict(schema_version=1,assets=assets,weapons=weapons,ships=ships,skills=skills,requirements=source['requirements'],cancelled_asset_ids=source['cancelled_asset_ids'],mix=dict(short_voices=32,reserved_alert_voices=4,ambience_loops=4,aircraft_loops=2,aggregate_seconds=0.25,dense_aggregate_seconds=0.6,max_distance=1800,dense_max_distance=1100,heavy_voices=2,impact_cell_size=180,alert_interval=1.5,duck_db=-8,duck_seconds=1.5,duck_attack_seconds=0.15,duck_release_seconds=0.5,loop_fade_seconds=0.5,low_oxygen_ratio=0.2,low_oxygen_rearm=0.35,critical_hp_ratio=0.25,critical_hp_rearm=0.4,time_warning_seconds=60))
    (ROOT/'data/audio/sfx_manifest.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2)+'\n')
    print(f'{len(assets)} assets, {len(weapons)} weapons, {len(ships)} ships, {len(skills)} silent skills; {sum(p.stat().st_size for p in DEST.rglob("*.wav"))} bytes')
if __name__=='__main__': main()
