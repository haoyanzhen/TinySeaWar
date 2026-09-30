"""Stable Audio 3 serial batch worker. Run only in the isolated server environment."""
import argparse, hashlib, json, os, subprocess, time, traceback
from pathlib import Path

def digest(path): return hashlib.sha256(path.read_bytes()).hexdigest()
def save(path, value):
    tmp=path.with_suffix('.tmp'); tmp.write_text(json.dumps(value,ensure_ascii=False,indent=2)+'\n'); tmp.replace(path)
def gpu_snapshot():
    output=subprocess.check_output(['nvidia-smi','--query-gpu=uuid,memory.free,utilization.gpu','--format=csv,noheader,nounits'],text=True)
    uuid=os.environ['CUDA_VISIBLE_DEVICES']
    row=next(row for row in output.splitlines() if row.startswith(uuid))
    device,free,util=[x.strip() for x in row.split(',')]
    if int(free)<16384: raise RuntimeError(f'Insufficient remaining headroom: {row}')
    return dict(uuid=device,free_mib=int(free),utilization=int(util))

def main():
    p=argparse.ArgumentParser(); p.add_argument('manifest',type=Path); p.add_argument('output',type=Path); p.add_argument('--limit',type=int); args=p.parse_args()
    args.output.mkdir(parents=True,exist_ok=True)
    import fcntl
    lock=(args.output.parent/'generation.lock').open('w'); fcntl.flock(lock,fcntl.LOCK_EX|fcntl.LOCK_NB)
    batch=json.loads(args.manifest.read_text()); batch_hash=digest(args.manifest)
    saved=args.output/'batch.json'
    if saved.exists() and digest(saved)!=batch_hash: raise RuntimeError('Immutable batch differs')
    saved.write_bytes(args.manifest.read_bytes())
    initial=gpu_snapshot()
    import torch, soundfile as sf, numpy as np
    from scipy.signal import resample_poly
    from stable_audio_3 import StableAudioModel
    model=StableAudioModel.from_pretrained('small-sfx', device='cuda')
    model.model.eval()
    assert model.model.sample_rate == 44100
    save(args.output/'environment.json',dict(initial_gpu=initial,torch=torch.__version__,cuda=torch.version.cuda,
        source_commit=subprocess.check_output(['git','-C','/home/hyz/server/sfxGen/stable-audio-3','rev-parse','HEAD'],text=True).strip(),
        batch_sha256=batch_hash,backend=batch['backend'],source_rate=44100,delivery_rate=48000,
        terms='https://huggingface.co/stabilityai/stable-audio-3-small-sfx'))
    count=0
    for asset in batch['assets']:
        for take in asset['candidates']:
            folder=args.output/asset['category']; folder.mkdir(exist_ok=True)
            stem=folder/take['id']; state=stem.with_suffix('.json')
            if state.exists():
                previous=json.loads(state.read_text())
                if previous.get('status')=='generated':
                    for key in ('raw','preview'):
                        assert digest(args.output/previous[key]['path'])==previous[key]['sha256']
                    continue
                if previous.get('status')=='failed': raise RuntimeError(f"Review failed take before retry: {take['id']}")
            if args.limit and count>=args.limit: return
            pre=gpu_snapshot(); started=time.time()
            prompt=take['prompt']
            if not prompt: raise ValueError('Missing English prompt')
            prompt += (' Continuous even texture throughout, no isolated foreground events.' if asset['loop'] else ' One isolated sound event at the beginning, then a natural complete decay into silence, no repetition.')
            prompt += ' No speech, no voices, no music, no background soundtrack.'
            record=dict(id=take['id'],asset_id=asset['id'],seed=take['seed'],prompt=prompt,steps=batch['steps'],guidance_scale=batch['guidance_scale'],
                generation_seconds=asset['generation_seconds'],target_seconds=asset['target_seconds'],before_gpu=pre,status='generating',started_at=started)
            save(state,record)
            try:
                with torch.inference_mode():
                    wave=model.generate(prompt=prompt, duration=asset['generation_seconds'], steps=batch['steps'],
                        cfg_scale=batch['guidance_scale'], seed=take['seed'], batch_size=1).cpu()[0]
                samples=wave[:,:int(asset['generation_seconds']*44100)].T.numpy()
                if not np.isfinite(samples).all(): raise ValueError('Nonfinite audio')
                raw=stem.with_name(stem.name+'_raw.wav'); sf.write(raw,samples,44100,subtype='FLOAT')
                # Crop only sub-threshold leading/trailing silence, never force-fit event duration.
                mono=np.max(np.abs(samples),axis=1); active=np.flatnonzero(mono>10**(-48/20))
                if not len(active): raise ValueError('Silent generation')
                left=0 if asset['loop'] else max(0,int(active[0])-int(.025*44100))
                right=len(samples) if asset['loop'] else min(len(samples),int(active[-1])+int(.12*44100))
                audio=resample_poly(samples[left:right],160,147).astype(np.float32)
                loop_crossfade=0
                if asset['loop']:
                    n=min(24000,len(audio)//8); f=np.linspace(0,1,n)[:,None]
                    blend=audio[-n:]*(1-f)+audio[:n]*f
                    audio=np.concatenate([blend,audio[n:-n]])
                    loop_crossfade=n/48000
                else:
                    n=min(240,len(audio)//8); audio[:n]*=np.linspace(0,1,n)[:,None]; audio[-n:]*=np.linspace(1,0,n)[:,None]
                # World point sounds mono; UI/alerts and ambience retain model stereo.
                if asset['category'] not in ('ambience','ui','alert','skill') and asset['id'] not in ('S03a','S03b'): audio=audio.mean(axis=1,keepdims=True)
                rms=float(np.sqrt(np.mean(audio**2))); peak=float(np.max(np.abs(audio)))
                target_db=-27 if asset['loop'] else (-23 if asset['category'] in ('ui','skill') else -21)
                gain=min(10**(target_db/20)/max(rms,1e-9),10**(-3/20)/max(peak,1e-9),4)
                audio*=gain
                preview=stem.with_suffix('.wav'); sf.write(preview,audio,48000,subtype='PCM_24')
                true_peak=float(np.max(np.abs(resample_poly(audio,4,1))))
                if true_peak>=1: raise ValueError('Oversampled peak clips')
                record.update(status='generated',human_review='pending',elapsed_seconds=time.time()-started,
                    raw=dict(path=str(raw.relative_to(args.output)),sha256=digest(raw)),
                    preview=dict(path=str(preview.relative_to(args.output)),sha256=digest(preview)),
                    source_peak=float(mono.max()),source_clipped_samples=int(np.count_nonzero(np.abs(samples)>=1)),
                    duration_seconds=len(audio)/48000,channels=audio.shape[1],sample_peak_dbfs=20*np.log10(max(float(np.max(np.abs(audio))),1e-9)),
                    rms_dbfs=20*np.log10(max(float(np.sqrt(np.mean(audio**2))),1e-9)),
                    true_peak_4x_dbfs=20*np.log10(max(true_peak,1e-9)),crop_seconds=[left/44100,right/44100],
                    gain_db=20*np.log10(gain),loop_crossfade_seconds=loop_crossfade,
                    loop_points_frames=[0,len(audio)] if asset['loop'] else None,
                    duration_review_required=(not asset['loop'] and len(audio)/48000>asset['target_seconds']*1.75),
                    loop_seam_review='pending' if asset['loop'] else 'not_applicable')
                save(state,record); print(json.dumps(dict(id=take['id'],status='generated',seconds=round(time.time()-started,2))),flush=True)
                del wave; torch.cuda.empty_cache(); count+=1
            except Exception:
                record.update(status='failed',error=traceback.format_exc()); save(state,record); raise
if __name__=='__main__': main()
