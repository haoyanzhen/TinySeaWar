"""Prepare a review batch from the deployed ComfyUI CLI's source WAVs.
Run in the server audio environment (numpy/scipy/soundfile).
"""
import argparse, hashlib, json, shutil
from pathlib import Path
import numpy as np
import soundfile as sf
from scipy.signal import resample_poly, butter, sosfiltfilt
from math import gcd

def sha(p): return hashlib.sha256(p.read_bytes()).hexdigest()
def main():
    p=argparse.ArgumentParser();p.add_argument('catalog',type=Path);p.add_argument('source',type=Path);p.add_argument('output',type=Path);a=p.parse_args()
    batch=json.loads(a.catalog.read_text());a.output.mkdir(parents=True,exist_ok=True)
    bfile=a.output/'batch.json'
    if bfile.exists() and sha(bfile)!=sha(a.catalog):raise ValueError('Immutable batch mismatch')
    shutil.copyfile(a.catalog,bfile)
    for name in ('request.json','report.json'):
        shutil.copyfile(a.source/name,a.output/('generation_'+name))
    for asset in batch['assets']:
        folder=a.output/asset['category'];folder.mkdir(exist_ok=True)
        for take in asset['candidates']:
            id_=take['id'];source=a.source/(id_+'.wav');meta=json.loads((a.source/(id_+'.json')).read_text())
            assert meta['status']=='generated' and meta['seed']==take['seed'] and meta['sha256']==sha(source)
            samples,rate=sf.read(source,dtype='float32',always_2d=True)
            assert np.isfinite(samples).all() and rate==44100
            raw=folder/(id_+'_raw.wav');shutil.copyfile(source,raw)
            envelope=np.max(np.abs(samples),axis=1);active=np.flatnonzero(envelope>10**(-48/20))
            if not len(active):raise ValueError('Silent source '+id_)
            left=0 if asset['loop'] else max(0,int(active[0]) - round(.025*rate))
            right=len(samples) if asset['loop'] else min(len(samples),int(active[-1])+round(.12*rate))
            divisor=gcd(rate,48000);audio=resample_poly(samples[left:right],48000//divisor,rate//divisor).astype(np.float32)
            cutoff=take.get('lowpass_hz')
            if cutoff:
                assert 20 < cutoff < 24000
                audio=sosfiltfilt(butter(4,cutoff,fs=48000,output='sos'),audio,axis=0).astype(np.float32)
            crossfade=0
            if asset['loop']:
                n=min(24000,len(audio)//8);f=np.linspace(0,1,n,dtype=np.float32)[:,None]
                audio=np.concatenate([audio[-n:]*(1-f)+audio[:n]*f,audio[n:-n]])
                crossfade=n/48000
            else:
                n=min(240,len(audio)//8);audio[:n]*=np.linspace(0,1,n)[:,None];audio[-n:]*=np.linspace(1,0,n)[:,None]
            if asset['category'] not in ('ambience','ui','alert','skill') and asset['id'] not in ('S03a','S03b'):audio=audio.mean(axis=1,keepdims=True)
            rms=float(np.sqrt(np.mean(audio**2)));peak=float(np.max(np.abs(audio)))
            target=-27 if asset['loop'] else (-23 if asset['category'] in ('ui','skill') else -21)
            target=asset.get('review_target_rms_dbfs',target)
            gain=min(10**(target/20)/max(rms,1e-9),10**(-3/20)/max(peak,1e-9),4)
            audio*=gain
            preview=folder/(id_+'.wav');sf.write(preview,audio,48000,subtype='PCM_24')
            # Measure encoded delivery waveform, not just the in-memory float buffer.
            delivered,delivery_rate=sf.read(preview,dtype='float32',always_2d=True)
            true_peak=float(np.max(np.abs(resample_poly(delivered,4,1))))
            assert true_peak<1 and delivery_rate==48000
            rms_by_window=[float(np.sqrt(np.mean(block**2))) for block in np.array_split(delivered,max(1,round(len(delivered)/4800)))]
            record=dict(id=id_,asset_id=asset['id'],seed=take['seed'],prompt=meta['prompt'],status='generated',human_review='pending',
                raw=dict(path=str(raw.relative_to(a.output)),sha256=sha(raw)),preview=dict(path=str(preview.relative_to(a.output)),sha256=sha(preview)),
                source_generation=meta,source_peak=float(envelope.max()),source_clipped_samples=int(np.count_nonzero(np.abs(samples)>=1)),
                duration_seconds=len(delivered)/48000,channels=delivered.shape[1],sample_rate=delivery_rate,
                sample_peak_dbfs=20*np.log10(max(float(np.max(np.abs(delivered))),1e-9)),
                rms_dbfs=20*np.log10(max(float(np.sqrt(np.mean(delivered**2))),1e-9)),true_peak_4x_dbfs=20*np.log10(max(true_peak,1e-9)),
                rms_windows_dbfs=[20*np.log10(max(v,1e-9)) for v in rms_by_window],
                lowpass_hz=cutoff,target_rms_dbfs=target,crop_seconds=[left/rate,right/rate],gain_db=20*np.log10(gain),loop_crossfade_seconds=crossfade,
                loop_points_frames=[0,len(delivered)] if asset['loop'] else None,
                duration_review_required=not asset['loop'] and len(delivered)/48000>asset['target_seconds']*1.75,
                loop_seam_review='pending' if asset['loop'] else 'not_applicable')
            (folder/(id_+'.json')).write_text(json.dumps(record,ensure_ascii=False,indent=2)+'\n')
    print('Prepared',sum(len(x['candidates']) for x in batch['assets']),'candidates')
if __name__=='__main__':main()
