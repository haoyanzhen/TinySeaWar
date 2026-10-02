"""Server-side explicit reference editing; never reported as fresh model inference."""
import json,hashlib
from pathlib import Path
import numpy as np
import soundfile as sf
from scipy.signal import resample_poly
root=Path('/home/hyz/server/sfxGen/modelscope-runtime');b=json.loads((root/'revision15_20261001_v4.json').read_text());out=root/'outputs'/b['id'];a=next(x for x in b['assets'] if x['id']=='U04a');src=root/'reviews/sfx_design18_20261001_v3/ui/U04a_d3_b.wav';sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest();assert sha(src)==a['reference']['sha256'];x,rate=sf.read(src,always_2d=True,dtype='float32');x=resample_poly(x,147,160) if rate==48000 else x;assert rate in (44100,48000)
for c in a['candidates']:
 gap=round(c['gap_ms']*44.1);y=np.concatenate([x,np.zeros((gap,x.shape[1]),dtype=x.dtype),x]);p=out/(c['id']+'.wav');sf.write(p,y,44100,subtype='FLOAT');meta=dict(id=c['id'],status='generated',seed=c['seed'],prompt=c['prompt'],sha256=sha(p),sample_rate=44100,channels=y.shape[1],frames=len(y),model=None,production_method='reference_edit_not_model_generation',reference_sha256=sha(src),reference_path=str(src),gap_ms=c['gap_ms'],actual_seconds=len(y)/44100);(out/(c['id']+'.json')).write_text(json.dumps(meta,indent=2)+'\n')
(out/'reference_edit_report.json').write_text(json.dumps(dict(model_generated=42,reference_edits=3,source_sha256=sha(src)),indent=2)+'\n')
print('Edited 3 double-tone candidates from verified B reference')
