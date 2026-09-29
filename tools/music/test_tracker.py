import copy
import json
from pathlib import Path
import tempfile
import unittest

import music
import tracker


class TrackerTests(unittest.TestCase):
    def setUp(self):
        self.tmp=tempfile.TemporaryDirectory();self.addCleanup(self.tmp.cleanup)
        self.folder=Path(self.tmp.name)
        self.batch=music.read(Path(__file__).with_name('example_batch.json'))
        self.track=self.batch['tracks'][0]
        self.key=self.batch['id']+'/'+self.track['id']
        music.save(self.folder/'manifest.json',self.batch)
        wav=self.folder/(self.track['id']+'.wav');wav.write_bytes(b'fixture audio bytes')
        self.sha=tracker.file_hash(wav)
        music.save(self.folder/'validation_summary.json',[{**self.track,'validation':{'sha256':self.sha,'duration_seconds':90,'issues':[]}}])
        self.registry=tracker.register({'version':1,'records':{}},self.folder)
        self.feedback={'version':1,'batch_id':self.batch['id'],'batch_sha256':music.digest(self.batch),
                       'reviewer':'Tester','exported_at':'2026-09-29T12:00:00Z','tracks':[
            {'id':self.track['id'],'audio_sha256':self.sha,'decision':'revise','notes':'jitter near 20s',
             'timestamps':[20],'loop_checked':False}]}

    def test_import_is_idempotent_and_preserves_history(self):
        r=tracker.import_feedback(self.registry,self.feedback,'browser export')
        r=tracker.import_feedback(r,self.feedback,'browser export')
        self.assertEqual(len(r['records'][self.key]['reviews']),1)
        changed=copy.deepcopy(self.feedback);changed['tracks'][0]['notes']='still jittering'
        changed['exported_at']='2026-09-30T12:00:00Z'
        r=tracker.import_feedback(r,changed,'browser export')
        self.assertEqual(len(r['records'][self.key]['reviews']),2)
        self.assertEqual(r['records'][self.key]['reviews'][0]['notes'],'jitter near 20s')

    def test_wrong_audio_and_batch_rejected_without_partial_write(self):
        before=copy.deepcopy(self.registry)
        for mode in ('audio','batch','time'):
            p=copy.deepcopy(self.feedback)
            if mode=='audio':p['tracks'][0]['audio_sha256']='wrong'
            if mode=='batch':p['batch_sha256']='wrong'
            if mode=='time':p['tracks'][0]['timestamps']=[91]
            with self.assertRaises(AssertionError):tracker.import_feedback(self.registry,p,'browser')
        self.assertEqual(self.registry,before)

    def test_duplicate_rows_rejected(self):
        self.feedback['tracks']*=2
        with self.assertRaisesRegex(AssertionError,'Duplicate'):tracker.import_feedback(self.registry,self.feedback,'browser')
        self.assertFalse(self.registry['records'][self.key]['reviews'])

    def test_older_import_does_not_replace_newer_conclusion(self):
        r=tracker.import_feedback(self.registry,self.feedback,'browser')
        old=copy.deepcopy(self.feedback);old['exported_at']='2026-09-01'
        old['tracks'][0]['decision']='preferred';old['tracks'][0]['notes']='older opinion'
        r=tracker.import_feedback(r,old,'browser')
        self.assertEqual(r['records'][self.key]['reviews'][-1]['decision'],'revise')

    def test_revision_links_parent_but_never_inherits_review(self):
        r=tracker.import_feedback(self.registry,self.feedback,'browser')
        self.batch['id']='new_revision'
        music.save(self.folder/'manifest.json',self.batch)
        r=tracker.register(r,self.folder,parent=self.key)
        child=r['records']['new_revision/'+self.track['id']]
        self.assertEqual(child['parent_id'],self.key)
        self.assertEqual(child['reviews'],[])
        self.assertEqual(r['records'][self.key]['reviews'][-1]['decision'],'revise')

    def test_replacing_audio_under_existing_identity_rejected(self):
        wav=self.folder/(self.track['id']+'.wav');wav.write_bytes(b'new audio')
        with self.assertRaisesRegex(AssertionError,'hash'):tracker.register(self.registry,self.folder)
        # Reusing the batch name with an entirely different track list is also forbidden.
        self.batch['tracks'][0]['id']='another_track'
        music.save(self.folder/'manifest.json',self.batch)
        with self.assertRaisesRegex(AssertionError,'batch changed'):tracker.register(self.registry,self.folder)

    def test_plan_does_not_change_human_verdict(self):
        r=tracker.import_feedback(self.registry,self.feedback,'browser')
        r=tracker.plan(r,self.key,'Reduce violin','high','Codex')
        r=tracker.plan(r,self.key,'Reduce violin','high','Codex')
        self.assertEqual(len(r['records'][self.key]['plans']),1)
        self.assertEqual(r['records'][self.key]['reviews'][-1]['decision'],'revise')

    def test_table_escapes_notes(self):
        self.feedback['tracks'][0]['notes']='<script>bad</script> | text\nnext'
        r=tracker.import_feedback(self.registry,self.feedback,'browser')
        output=self.folder/'registry.md';tracker.render(r,output)
        text=output.read_text()
        self.assertNotIn('<script>',text)
        self.assertIn('&#124;',text)

    def test_untouched_pending_export_cannot_erase_prior_feedback(self):
        r=tracker.import_feedback(self.registry,self.feedback,'browser')
        self.feedback['tracks'][0].update(decision='pending',notes='',timestamps=[])
        self.feedback['exported_at']='2026-10-01'
        r=tracker.import_feedback(r,self.feedback,'browser')
        self.assertEqual(len(r['records'][self.key]['reviews']),1)
        self.assertEqual(r['records'][self.key]['reviews'][0]['decision'],'revise')

if __name__=='__main__':unittest.main()
