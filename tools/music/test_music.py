import copy
import io
import json
from pathlib import Path
import tempfile
import time
import unittest
from unittest.mock import patch
import wave
import zipfile

import music


class WorkflowTests(unittest.TestCase):
    def setUp(self):
        self.batch=music.read(Path(__file__).with_name('example_batch.json'))
        self.snapshot={'gpu':{'index':0,'uuid':'GPU-test','name':'NVIDIA A100 80GB PCIe',
                             'total_mib':81920,'free_mib':20000}}
        self.tmp=tempfile.TemporaryDirectory();self.addCleanup(self.tmp.cleanup)
        self.root=Path(self.tmp.name)
        self.config={'remote_root':str(self.root),'poll_timeout_seconds':0.01,'poll_interval_seconds':0.001}

    def wav(self,active=2,quiet=0):
        out=io.BytesIO()
        with wave.open(out,'wb') as w:
            w.setnchannels(2);w.setsampwidth(2);w.setframerate(48000)
            w.writeframes((b'\x10\x27\xf0\xd8'*48000)*active+b'\0'*(quiet*48000*4))
        return out.getvalue()

    def test_manifest_rejects_traversal_duplicate_and_random_seed(self):
        for mode in ('path','duplicate','seed'):
            b=copy.deepcopy(self.batch)
            if mode=='path':b['id']='../escape'
            if mode=='duplicate':b['tracks']*=2
            if mode=='seed':b['tracks'][0]['request']['use_random_seed']=True
            with self.assertRaises(AssertionError):music.validate(b)

    def test_repaint_source_and_ranges(self):
        track=self.batch['tracks'][0]
        track['request'].update(task_type='repaint',repainting_start=0,repainting_end=10)
        with self.assertRaises(AssertionError):music.validate(self.batch)
        track['source_audio']={'batch_id':'source','track_id':'song','sha256':'a'*64}
        music.validate(self.batch)
        for start,end in ((-1,10),(10,10),(0,999),(float('nan'),10)):
            track['request'].update(repainting_start=start,repainting_end=end)
            with self.assertRaises(AssertionError):music.validate(self.batch)

    def test_new_repaint_requires_explicit_mask_before_submission(self):
        track=self.batch['tracks'][0]
        track['request'].update(task_type='repaint',repainting_start=0,repainting_end=10)
        track['source_audio']={'batch_id':'source','track_id':'song','sha256':'a'*64}
        with patch.object(music,'api') as api,patch.object(music,'probe') as probe:
            with self.assertRaisesRegex(AssertionError,'explicit interval masks'):
                music.run_batch(self.config,self.batch)
            api.assert_not_called()
            probe.assert_not_called()

    def test_gpu_gate_boundaries_and_arbitrary_duration(self):
        t=self.batch['tracks'][0];h=music.digest(self.batch)
        self.assertTrue(music.gate(self.snapshot,t,h)['allowed'])
        self.snapshot['gpu']['free_mib']=16383
        self.assertFalse(music.gate(self.snapshot,t,h)['allowed'])
        self.snapshot['gpu']['free_mib']=16384
        for duration in (45, 90, 150, 210, 601, 1200):
            t['request']['audio_duration']=duration
            music.validate(self.batch)
            self.assertTrue(music.gate(self.snapshot,t,h)['allowed'])

    def test_invalid_durations_rejected(self):
        for duration in (0, -1, float('inf'), float('nan'), True, '150'):
            self.batch['tracks'][0]['request']['audio_duration']=duration
            with self.assertRaises(AssertionError):music.validate(self.batch)

    def test_approval_is_scoped_and_cannot_cover_falling_capacity(self):
        self.snapshot['gpu']['free_mib']=12000;t=self.batch['tracks'][0];h=music.digest(self.batch)
        a={'batch_sha256':h,'gpu_uuid':'GPU-test','expires_at':time.time()+100,
           'free_floor_mib':12000,'user_decision':'User explicitly approved this batch at this capacity'}
        self.assertTrue(music.gate(self.snapshot,t,h,a)['allowed'])
        for k,v in [('batch_sha256','other'),('gpu_uuid','other'),('expires_at',0),('free_floor_mib',12001),('user_decision','')]:
            changed={**a,k:v}
            self.assertFalse(music.gate(self.snapshot,t,h,changed)['allowed'])

    def test_low_vram_never_posts(self):
        self.snapshot['gpu']['free_mib']=1000
        with patch.object(music,'probe',return_value=self.snapshot),patch.object(music,'api') as api:
            r=music.run_batch(self.config,self.batch)
        self.assertEqual(r['status'],'needs_user_decision');api.assert_not_called()

    def test_uncertain_submit_not_retried(self):
        with patch.object(music,'probe',return_value=self.snapshot),patch.object(music,'api',side_effect=TimeoutError):
            with self.assertRaises(TimeoutError):music.run_batch(self.config,self.batch)
        with patch.object(music,'api') as api:
            with self.assertRaisesRegex(RuntimeError,'submitting'):music.run_batch(self.config,self.batch)
            api.assert_not_called()

    def test_each_song_rechecks_capacity(self):
        second=copy.deepcopy(self.batch['tracks'][0]);second['id']='second'
        self.batch['tracks'].append(second)
        low=copy.deepcopy(self.snapshot);low['gpu']['free_mib']=1000
        sample={'file':'/v1/audio?path=test','dit_model':music.MODEL,'lm_model':music.LM}
        calls=[]
        def api(c,path,payload=None,binary=False):
            calls.append(path)
            if path=='/release_task':return {'data':{'task_id':'first-task'}}
            if path=='/query_result':return {'data':[{'status':1,'result':json.dumps([sample])}]}
            return self.wav()
        with patch.object(music,'probe',side_effect=[self.snapshot,low]),patch.object(music,'api',side_effect=api):
            r=music.run_batch(self.config,self.batch)
        self.assertEqual(r['track'],'second');self.assertEqual(calls.count('/release_task'),1)

    def test_explicit_failure_is_not_retried(self):
        folder=self.root/'outputs'/'batches'/self.batch['id'];folder.mkdir(parents=True)
        music.save(folder/'manifest.json',self.batch)
        slug=self.batch['tracks'][0]['id'];music.save(folder/f'{slug}.state.json',{'phase':'submitted','task_id':'failed-task'})
        with patch.object(music,'api',return_value={'data':[{'status':2}]}):
            with self.assertRaisesRegex(RuntimeError,'generation failed'):music.run_batch(self.config,self.batch)
        with patch.object(music,'api') as api:
            with self.assertRaisesRegex(RuntimeError,'failed'):music.run_batch(self.config,self.batch)
            api.assert_not_called()

    def test_poll_timeout_keeps_task_id(self):
        folder=self.root/'outputs'/'batches'/self.batch['id'];folder.mkdir(parents=True)
        music.save(folder/'manifest.json',self.batch)
        slug=self.batch['tracks'][0]['id'];state=folder/f'{slug}.state.json'
        music.save(state,{'phase':'submitted','task_id':'pending-task'})
        with patch.object(music,'api',return_value={'data':[{'status':0}]}):
            with self.assertRaises(TimeoutError):music.run_batch(self.config,self.batch)
        self.assertEqual(music.read(state),{'phase':'submitted','task_id':'pending-task'})

    def test_resume_same_task_and_complete_not_resubmitted(self):
        folder=self.root/'outputs'/'batches'/self.batch['id'];folder.mkdir(parents=True)
        music.save(folder/'manifest.json',self.batch)
        slug=self.batch['tracks'][0]['id'];music.save(folder/f'{slug}.state.json',{'phase':'submitted','task_id':'old-task'})
        sample={'file':'/v1/audio?path=test','dit_model':music.MODEL,'lm_model':music.LM}
        result={'data':[{'status':1,'result':json.dumps([sample])}]}
        def api(c,path,payload=None,binary=False):
            if path=='/query_result':self.assertEqual(payload,{'task_id_list':['old-task']});return result
            if binary:return self.wav()
            self.fail('Unexpected POST '+path)
        with patch.object(music,'api',side_effect=api),patch.object(music,'probe') as probe:
            self.assertEqual(music.run_batch(self.config,self.batch)['status'],'complete');probe.assert_not_called()
        with patch.object(music,'api') as api:
            music.run_batch(self.config,self.batch);api.assert_not_called()

    def test_changed_batch_refused(self):
        folder=self.root/'outputs'/'batches'/self.batch['id'];folder.mkdir(parents=True)
        music.save(folder/'manifest.json',self.batch)
        self.batch['tracks'][0]['request']['seed']+=1
        with self.assertRaisesRegex(AssertionError,'different content'):music.run_batch(self.config,self.batch)

    def test_long_tail_detected_despite_nonzero_overall_rms(self):
        path=self.root/'test.wav';path.write_bytes(self.wav(active=2,quiet=7))
        r=music.analyze_wav(path,9)
        self.assertGreater(r['rms'],0.01);self.assertEqual(r['trailing_quiet_seconds'],7)
        self.assertIn('long_quiet_tail',r['issues']);self.assertEqual(r['human_status'],'pending')

    def test_review_escapes_script_and_marks_missing_audio(self):
        self.batch['tracks'][0]['title']='</script><script>alert(1)</script>'
        music.save(self.root/'manifest.json',self.batch)
        result=music.review(self.root)
        self.assertEqual(result['flagged'],1)
        page=(self.root/'listen.html').read_text()
        self.assertNotIn('</script><script>alert',page)
        self.assertIn('\\u003c/script>',page)

    def test_fetch_rejects_unlisted_zip_paths(self):
        def remote(c,action,batch,output=None):
            with zipfile.ZipFile(output,'w') as z:z.writestr('../escaped.txt','bad')
        with patch.object(music,'remote',side_effect=remote):
            with self.assertRaisesRegex(AssertionError,'Unexpected archive'):music.fetch({},self.batch,self.root)
        self.assertFalse((self.root.parent/'escaped.txt').exists())

if __name__=='__main__':unittest.main()
