#!/usr/bin/env python3
"""ACE-Step batch workflow. Standard library only; local and SSH worker entrypoints."""
from __future__ import annotations
import argparse
import array
import base64
import csv
from datetime import datetime, timezone
import hashlib
import io
import json
import math
from pathlib import Path
import re
import shlex
import subprocess
import sys
import time
import urllib.parse
import urllib.request
import wave
import zipfile

HERE = Path(__file__).resolve().parent
SAFE = re.compile(r'^[a-z0-9][a-z0-9_-]{0,79}$')
MODEL = 'acestep-v15-xl-sft'
LM = 'acestep-5Hz-lm-4B'


def encoded(value):
    return json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(',', ':')).encode()


def digest(value):
    return hashlib.sha256(encoded(value)).hexdigest()


def read(path):
    return json.loads(Path(path).read_text())


def save(path, value):
    path = Path(path)
    tmp = path.with_suffix(path.suffix + '.tmp')
    tmp.write_bytes(encoded(value))
    tmp.replace(path)


def validate(batch):
    assert batch.get('version') == 1, 'Unsupported manifest version'
    assert SAFE.fullmatch(batch['id']), 'Unsafe batch id'
    assert 1 <= len(batch['tracks']) <= 100, 'Expected 1..100 tracks'
    seen = set()
    for track in batch['tracks']:
        slug = track['id']
        assert SAFE.fullmatch(slug) and slug not in seen, 'Invalid/duplicate track id'
        seen.add(slug)
        assert track['category'] in ('title', 'battle', 'victory', 'defeat', 'neutral')
        assert isinstance(track['title'], str) and track['title'].strip()
        req = track['request']
        assert req['model'] == MODEL and req['lm_model_path'] == LM
        assert req['audio_format'] == 'wav' and req['batch_size'] == 1
        assert req['use_random_seed'] is False and type(req['seed']) is int
        assert isinstance(req['prompt'], str) and req['prompt'].strip()
        assert type(req['audio_duration']) in (int, float) and math.isfinite(req['audio_duration']) and req['audio_duration'] > 0
        assert 1 <= req['inference_steps'] <= 200
        assert req.get('thinking') is True and req.get('lm_backend') == 'pt'
        # Keep generation self-contained. Uploaded audio/reference workflows need a separate contract.
        assert not (set(req) & {'reference_audio_path', 'src_audio_path', 'audio_codes'})
    return batch


def api(config, path, payload=None, binary=False):
    url = config['api_url']
    parsed = urllib.parse.urlparse(url)
    assert parsed.scheme == 'http' and parsed.hostname in ('127.0.0.1', 'localhost'), 'API must be remote loopback'
    opener = urllib.request.build_opener(urllib.request.ProxyHandler({}))
    data = None if payload is None else encoded(payload)
    with opener.open(urllib.request.Request(url + path, data=data,
                     headers={'Content-Type': 'application/json'}), timeout=120) as response:
        body = response.read()
    return body if binary else json.loads(body)


def probe(config):
    query = subprocess.check_output(['nvidia-smi', '--query-gpu=index,uuid,name,memory.total,memory.used,memory.free,utilization.gpu',
                                     '--format=csv,noheader,nounits'], text=True)
    gpus = []
    for row in csv.reader(query.splitlines()):
        row = [s.strip() for s in row]
        gpus.append(dict(zip(('index','uuid','name','total_mib','used_mib','free_mib','utilization'),
                             [int(row[0]),row[1],row[2],*[int(v) for v in row[3:]]])))
    gpu = next(g for g in gpus if g['index'] == config['gpu_index'])
    # Check the actual running service process tree environment, not only a config file.
    pid = int(subprocess.check_output(['systemctl','--user','show',config['service'],'--property=MainPID','--value'], text=True))
    assert pid > 0, 'Service is not running; tools do not auto-start/load models'
    pending, visible = [pid], []
    while pending:
        current = pending.pop()
        proc = Path('/proc') / str(current)
        try:
            env = (proc/'environ').read_bytes().split(b'\0')
            values = [e.split(b'=',1)[1].decode() for e in env if e.startswith(b'CUDA_VISIBLE_DEVICES=')]
            visible.extend(values)
            pending.extend(map(int,(proc/'task'/str(current)/'children').read_text().split()))
        except FileNotFoundError:
            continue
    assert visible and all(v in (str(gpu['index']),gpu['uuid']) for v in visible), 'Cannot verify service GPU mapping'
    health = api(config, '/health')['data']
    assert health.get('models_initialized') and health.get('llm_initialized'), 'Models not loaded; do not auto-load'
    assert health.get('loaded_model') == MODEL and health.get('loaded_lm_model') == LM, 'Unexpected loaded models'
    return {'checked_at':time.time(),'gpu':gpu,'all_gpus':gpus,'health':health,'service_pid':pid}


def gate(snapshot, track, batch_hash, approval=None):
    gpu = snapshot['gpu']
    reasons = []
    # Operational free-memory reserve, not a duration limit or a capacity guarantee.
    if gpu['free_mib'] < 16384:
        reasons.append('free VRAM below 16384 MiB incremental reserve')
    if not reasons:
        return {'allowed':True,'reasons':[],'override':False}
    valid = approval is not None and (
        approval.get('batch_sha256') == batch_hash and approval.get('gpu_uuid') == gpu['uuid'] and
        isinstance(approval.get('user_decision'),str) and bool(approval['user_decision'].strip()) and
        0 < approval.get('expires_at',0)-time.time() <= 3600 and
        isinstance(approval.get('free_floor_mib'),int) and
        gpu['free_mib'] >= approval['free_floor_mib'] >= 0)
    return {'allowed':bool(valid),'reasons':reasons,'override':bool(valid)}


def run_batch(config, batch, approval=None):
    import fcntl
    validate(batch)
    root = Path(config['remote_root']).expanduser()
    assert root.is_dir(), 'Deployment root does not exist'
    # One workflow at a time, across all its batches; not a reservation against unrelated GPU users.
    with (root/'music-tools.lock').open('a') as lock:
        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        folder = root/'outputs'/'batches'/batch['id']
        folder.mkdir(parents=True,exist_ok=True)
        mp = folder/'manifest.json'
        if mp.exists():
            assert digest(read(mp)) == digest(batch), 'Batch id already used with different content'
        else:
            save(mp,batch)
        provenance = folder/'provenance.json'
        if not provenance.exists():
            revision = subprocess.run(['git','-C',str(root/'app'),'rev-parse','HEAD'],
                                      capture_output=True,text=True)
            save(provenance,{'source_commit':revision.stdout.strip() or None,
                 'tool_sha256':config.get('tool_sha256'),'python':sys.version,
                 'model_manifest_sha256':hashlib.sha256((root/'model-manifest.json').read_bytes()).hexdigest()
                    if (root/'model-manifest.json').exists() else None,
                 'deployment_patch_sha256':hashlib.sha256((root/'deployment.patch').read_bytes()).hexdigest()
                    if (root/'deployment.patch').exists() else None})
        for track in batch['tracks']:
            slug = track['id']
            state_path = folder/f'{slug}.state.json'
            state = read(state_path) if state_path.exists() else {'phase':'new'}
            if state['phase'] == 'complete':
                wav = folder/f'{slug}.wav'
                assert hashlib.sha256(wav.read_bytes()).hexdigest() == state['sha256'], 'Completed file hash mismatch'
                continue
            if state['phase'] in ('submitting','failed'):
                raise RuntimeError(f'{slug}: {state["phase"]}; inspect state/API logs, never auto-resubmit')
            if state['phase'] == 'new':
                snapshot = probe(config)
                decision = gate(snapshot,track,digest(batch),approval)
                save(folder/f'{slug}.preflight.json',{'snapshot':snapshot,'decision':decision,
                     'batch_sha256':digest(batch),'approval':approval if decision['override'] else None})
                if not decision['allowed']:
                    return {'status':'needs_user_decision','track':slug,'snapshot':snapshot,
                            'decision':decision,'batch_sha256':digest(batch)}
                save(folder/f'{slug}.request.json',track['request'])
                # Persist intent BEFORE POST; uncertain network outcomes must not create duplicate jobs.
                save(state_path,{'phase':'submitting','started_at':time.time()})
                submitted = api(config,'/release_task',track['request'])
                save(folder/f'{slug}.submission.json',submitted)
                state = {'phase':'submitted','task_id':submitted['data']['task_id']}
                save(state_path,state)
            if state['phase'] == 'submitted':
                deadline = time.monotonic()+config.get('poll_timeout_seconds',1800)
                while time.monotonic() < deadline:
                    result = api(config,'/query_result',{'task_id_list':[state['task_id']]})
                    item = result['data'][0]
                    save(folder/f'{slug}.result.json',result)
                    if item['status'] == 2:
                        save(state_path,{**state,'phase':'failed'})
                        raise RuntimeError(f'{slug}: remote generation failed, see result.json')
                    if item['status'] == 1:
                        state = {**state,'phase':'generated'}
                        save(state_path,state)
                        break
                    time.sleep(config.get('poll_interval_seconds',5))
                else:
                    raise TimeoutError(f'{slug}: polling timed out; run again to resume SAME task')
            result = read(folder/f'{slug}.result.json')
            sample = json.loads(result['data'][0]['result'])[0]
            assert sample['dit_model'] == MODEL and sample['lm_model'] == LM, 'Generation model mismatch'
            url = sample['file']
            assert url.startswith('/v1/audio?'), 'Unexpected audio URL'
            content = api(config,url,binary=True)
            tmp = folder/f'{slug}.wav.part'
            tmp.write_bytes(content)
            tmp.replace(folder/f'{slug}.wav')
            save(state_path,{**state,'phase':'complete','sha256':hashlib.sha256(content).hexdigest()})
        return {'status':'complete','batch_id':batch['id'],'batch_sha256':digest(batch)}


def export_batch(config,batch):
    folder = Path(config['remote_root']).expanduser()/'outputs'/'batches'/batch['id']
    assert digest(read(folder/'manifest.json')) == digest(batch), 'Remote manifest differs'
    names = ['manifest.json','provenance.json']
    for track in batch['tracks']:
        names += [f'{track["id"]}.{suffix}' for suffix in
                  ('wav','request.json','preflight.json','submission.json','result.json','state.json')]
    with zipfile.ZipFile(sys.stdout.buffer,'w',compression=zipfile.ZIP_STORED) as archive:
        for name in names:
            path = folder/name
            if path.exists():
                assert not path.is_symlink(), 'Symlink artifact rejected'
                archive.write(path,name)


def remote(config, action, batch=None, approval=None, output=None):
    config = {**config,'tool_sha256':hashlib.sha256(Path(__file__).read_bytes()).hexdigest()}
    target = config['ssh_target']
    assert re.fullmatch(r'[A-Za-z0-9_.-]+@[A-Za-z0-9_.-]+',target), 'Invalid SSH target'
    payload = base64.b64encode(encoded({'config':config,'action':action,'batch':batch,'approval':approval})).decode()
    command = shlex.join([config['remote_python'],'-','worker',payload])
    result = subprocess.run(['ssh','-o','BatchMode=yes','-o','StrictHostKeyChecking=yes',target,command],
                            input=Path(__file__).read_bytes(),stdout=output or subprocess.PIPE,check=True)
    return None if output else json.loads(result.stdout)


def analyze_wav(path, expected):
    """Windowed PCM analysis. Flags for human review, never musical approval."""
    with wave.open(str(path),'rb') as wav:
        assert wav.getsampwidth() == 2 and wav.getcomptype() == 'NONE', 'Expected PCM16 WAV; convert explicitly before analysis'
        rate, channels, frames = wav.getframerate(),wav.getnchannels(),wav.getnframes()
        peak, square, count, windows, clipped = 0,0,0,[],0
        while raw := wav.readframes(rate):
            samples = array.array('h',raw)
            if sys.byteorder != 'little': samples.byteswap()
            energy = sum(v*v for v in samples)
            rms = math.sqrt(energy/len(samples))/32768
            windows.append(round(20*math.log10(max(rms,1e-12)),2))
            peak=max(peak,max(abs(v) for v in samples)/32768)
            clipped+=sum(abs(v)>=32767 for v in samples)
            square+=energy;count+=len(samples)
    assert count, 'Empty WAV'
    duration=frames/rate
    active=[i for i,v in enumerate(windows) if v>-55]
    trailing=duration-min(duration,active[-1]+1) if active else duration
    quiet_runs=[];start=None
    for i,v in enumerate(windows+[0]):
        if v<=-55 and start is None: start=i
        elif v>-55 and start is not None:
            if i-start>=3: quiet_runs.append([start,min(i,duration)])
            start=None
    issues=[]
    if abs(duration-expected)>1: issues.append('duration_mismatch')
    if rate!=48000 or channels!=2: issues.append('unexpected_format')
    if not active: issues.append('silent')
    if trailing>=5: issues.append('long_quiet_tail')
    if quiet_runs: issues.append('quiet_regions_review')
    if clipped: issues.append('clipped_samples')
    return {'duration_seconds':duration,'sample_rate':rate,'channels':channels,'peak':peak,
            'rms':math.sqrt(square/count)/32768,'window_seconds':1,'rms_dbfs':windows,
            'quiet_threshold_dbfs':-55,'quiet_regions_seconds':quiet_runs,'trailing_quiet_seconds':trailing,
            'issues':issues,'technical_status':'needs_review' if issues else 'basic_checks_passed',
            'human_status':'pending','sha256':hashlib.sha256(Path(path).read_bytes()).hexdigest()}


def review(folder):
    batch=validate(read(folder/'manifest.json'))
    tracks=[]
    for track in batch['tracks']:
        wav=folder/f'{track["id"]}.wav'
        row=dict(track)
        if wav.exists():
            report=analyze_wav(wav,track['request']['audio_duration'])
            state=folder/f'{track["id"]}.state.json'
            if state.exists(): assert read(state)['sha256']==report['sha256'], 'Downloaded WAV hash mismatch'
            save(folder/f'{track["id"]}.validation.json',report)
            row['validation']=report
        else:
            row['validation']={'technical_status':'missing','human_status':'pending','issues':['audio_missing']}
        tracks.append(row)
    save(folder/'validation_summary.json',tracks)
    data=encoded({'batch_id':batch['id'],'batch_sha256':digest(batch),'tracks':tracks}).decode().replace('<','\\u003c')
    template=(HERE/'review.html').read_text()
    (folder/'listen.html').write_text(template.replace('/*BATCH_DATA*/',data))
    return {'status':'review_ready','folder':str(folder),'tracks':len(tracks),
            'flagged':sum(bool(t['validation']['issues']) for t in tracks)}


def fetch(config,batch,folder):
    folder.mkdir(parents=True,exist_ok=True)
    if (folder/'manifest.json').exists():
        assert digest(read(folder/'manifest.json'))==digest(batch),'Local batch differs'
    archive=folder/'download.zip.part'
    with archive.open('wb') as out: remote(config,'export',batch,output=out)
    allowed={'manifest.json','provenance.json'} | {f'{t["id"]}.{s}' for t in batch['tracks'] for s in
               ('wav','request.json','preflight.json','submission.json','result.json','state.json')}
    with zipfile.ZipFile(archive) as z:
        assert set(z.namelist())<=allowed and len(set(z.namelist()))==len(z.namelist()),'Unexpected archive entries'
        for info in z.infolist():
            assert info.file_size<=1024**3,'Artifact too large'
            dest=folder/info.filename
            assert not dest.is_symlink(),'Local symlink rejected'
            tmp=dest.with_suffix(dest.suffix+'.download')
            with z.open(info) as src, tmp.open('wb') as out:
                import shutil
                shutil.copyfileobj(src,out)
            tmp.replace(dest)
    archive.unlink()
    assert digest(read(folder/'manifest.json'))==digest(batch),'Downloaded manifest differs'
    return review(folder)


def main():
    if len(sys.argv)>1 and sys.argv[1]=='worker':
        args=json.loads(base64.b64decode(sys.argv[2])); config=args['config']; batch=args['batch']
        if args['action']=='export':
            validate(batch);export_batch(config,batch);return
        if args['action']=='probe':
            result=probe(config)
            if batch:
                validate(batch)
                result['batch_sha256']=digest(batch)
                result['decisions']={t['id']:gate(result,t,digest(batch)) for t in batch['tracks']}
        else: result=run_batch(config,batch,args['approval'])
        print(json.dumps(result,ensure_ascii=False));return
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('command',choices=['check','generate','fetch','review','e2e','serve'])
    parser.add_argument('--config',type=Path,default=HERE/'server.json')
    parser.add_argument('--manifest',type=Path)
    parser.add_argument('--output',type=Path)
    parser.add_argument('--approval',type=Path,help='Explicit user decision record; never fabricate consent')
    parser.add_argument('--port',type=int,default=8767)
    args=parser.parse_args()
    if args.command in ('e2e','fetch','review','serve') and not args.output:
        parser.error('--output is required for this command')
    if args.command in ('e2e','fetch','generate') and not args.manifest:
        parser.error('--manifest is required for this command')
    if args.command=='serve':
        assert args.output
        from http.server import ThreadingHTTPServer,SimpleHTTPRequestHandler
        from functools import partial
        print(f'http://127.0.0.1:{args.port}/listen.html',flush=True)
        ThreadingHTTPServer(('127.0.0.1',args.port),partial(SimpleHTTPRequestHandler,directory=str(args.output.resolve()))).serve_forever()
        return
    if args.command=='review':
        assert args.output; result=review(args.output)
    else:
        config=read(args.config)
        batch=validate(read(args.manifest)) if args.manifest else None
        if args.command=='check': result=remote(config,'probe',batch)
        elif args.command in ('generate','e2e'):
            assert batch
            result=remote(config,'generate',batch,read(args.approval) if args.approval else None)
            print(json.dumps(result,ensure_ascii=False,indent=2),flush=True)
            if result['status']=='needs_user_decision': sys.exit(3)
            if args.command=='e2e':
                assert args.output; result=fetch(config,batch,args.output)
        else:
            assert batch and args.output;result=fetch(config,batch,args.output)
    print(json.dumps(result,ensure_ascii=False,indent=2))

if __name__=='__main__':
    main()
