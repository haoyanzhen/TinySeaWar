from pathlib import Path
import json
import sys
import tempfile
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import record_codex_builtin_art as recorder
import batch_character_art as batch


class ProductionWorkflowTests(unittest.TestCase):
    def test_prepare_preserves_current_reviews_and_invalidates_only_replaced_source(self):
        with tempfile.TemporaryDirectory() as temporary, patch.object(recorder, 'CHAR_ROOT', Path(temporary)):
            paths = recorder.source_paths('example')
            for path in paths.values():
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_bytes(b'original')
            output = recorder.prepare_source_review('example')
            data = json.loads(output.read_text())
            self.assertTrue(all(item['verdict'] == 'pending' for item in data['sources'].values()))
            for item in data['sources'].values():
                item.update(verdict='pass', reviewer='reviewer', observation='Observed complete object')
            output.write_text(json.dumps(data))
            recorder.prepare_source_review('example')
            self.assertEqual(data, json.loads(output.read_text()))
            paths['anim_hit'].write_bytes(b'replacement')
            paths['anim_move'].unlink()
            recorder.prepare_source_review('example')
            refreshed = json.loads(output.read_text())
            self.assertEqual('pending', refreshed['sources']['anim_hit']['verdict'])
            self.assertEqual('pass', refreshed['sources']['anim_hit']['previous_review']['verdict'])
            self.assertEqual('missing', refreshed['sources']['anim_move']['sha256'])
            self.assertEqual('pass', refreshed['sources']['concept_full']['verdict'])
            recorder.prepare_source_review('example')
            self.assertEqual(refreshed, json.loads(output.read_text()))
            self.assertFalse(output.with_name('example_source_provenance_v2.json').exists())

    def test_review_rejects_nontext_evidence(self):
        for value in [None, 1, [], {}, True, '  ']:
            with self.subTest(value=value):
                review = {'sha256': 'hash', 'verdict': 'pass', 'reviewer': value, 'observation': 'seen'}
                self.assertFalse(recorder.reviewed_source(review, 'hash'))
                review.update(reviewer='reviewer', observation=value)
                self.assertFalse(recorder.reviewed_source(review, 'hash'))

    def test_malformed_review_and_unsafe_identifier_fail_cleanly(self):
        with tempfile.TemporaryDirectory() as temporary, patch.object(recorder, 'CHAR_ROOT', Path(temporary)):
            meta = Path(temporary) / 'example/meta'
            meta.mkdir(parents=True)
            for document in [[], {'character_id': 'example', 'sources': []},
                             {'character_id': 'example', 'sources': {'anim_idle': None}},
                             {'character_id': 'example', 'sources': {'typo': {}}}]:
                (meta / 'example_source_review.json').write_text(json.dumps(document))
                with self.assertRaises(ValueError):
                    recorder.prepare_source_review('example')
            with self.assertRaises(ValueError):
                recorder.source_paths('../outside')

    def test_delivery_gate_cannot_pass_technical_only_or_failed_processing(self):
        inspected = {'batch_ready': True, 'delivery_ready': False}
        self.assertEqual(0, batch.batch_exit_code([inspected]))
        self.assertEqual(1, batch.batch_exit_code([inspected], True))
        inspected['delivery_ready'] = True
        self.assertEqual(0, batch.batch_exit_code([{'status': 'complete', 'inspection': inspected}], True))
        self.assertEqual(1, batch.batch_exit_code([{'status': 'failed', 'inspection': inspected}], True))
        self.assertEqual(1, batch.batch_exit_code([], True))

    def test_tagged_report_preserves_phase_report(self):
        with tempfile.TemporaryDirectory() as temporary, patch.object(batch, 'QA_ROOT', Path(temporary)):
            existing = Path(temporary) / 'character_art_batch_report_phase2.json'
            existing.write_text('keep phase-wide report')
            json_path, markdown_path = batch.write_reports('dry-run', [], 'phase2', 'trial-01')
            self.assertEqual('keep phase-wide report', existing.read_text())
            self.assertTrue(markdown_path.exists())
            self.assertEqual('character_art_batch_report_phase2_trial-01.json', json_path.name)
            with self.assertRaises(ValueError):
                batch.write_reports('dry-run', [], 'phase2', '../escape')


if __name__ == '__main__':
    unittest.main()
