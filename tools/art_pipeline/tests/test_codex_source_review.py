from pathlib import Path
import json
import sys
import tempfile
import unittest
from unittest.mock import patch

from PIL import Image, ImageDraw

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import record_codex_builtin_art as recorder
import postprocess_trial_sheets as cropper
sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "data"))
import build_phase2_roster_data as roster_builder


class CodexSourceReviewTests(unittest.TestCase):
    def test_visual_rebuild_uses_reviewed_semantics_instead_of_first_role(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            (root / "example").mkdir()
            plan = {
                "vfx_roles": ["guard_aura"],
                "public_vfx_profiles": {"guard_aura": "skill.area"},
                "weapon_binding_rules": {"example_main": {"asset_role": "battle_turret_main_01",
                    "launch_bind": "muzzle_02", "muzzle_vfx_role": "muzzle_flash_large"}},
                "additional_public_vfx_roles": {"muzzle_flash_large": {"semantic": "muzzle_flash.large"}},
            }
            (root / "example/postprocess_plan.json").write_text(json.dumps(plan))
            with patch.object(roster_builder, "PLAN_ROOT", root):
                visual = roster_builder.build_visuals({"example_main": {"character_id": "example",
                    "mount_type": "Gun", "formula": "large_he", "weapon_ids": []}})[0]
            self.assertEqual("muzzle_02", visual["launch_bind"])
            self.assertEqual("muzzle_flash_large", visual["muzzle_vfx_role"])
            self.assertEqual("muzzle_flash.large", visual["vfx_role_mappings"]["muzzle_flash_large"])
            self.assertNotIn("asset_role", visual)

    def test_largest_component_ignores_faint_bridge_but_keeps_soft_edge(self):
        image = Image.new("RGBA", (80, 40))
        draw = ImageDraw.Draw(image)
        draw.rectangle((5, 5, 30, 34), fill=(80, 120, 160, 255))
        draw.rectangle((60, 10, 72, 25), fill=(80, 120, 160, 255))
        draw.line((30, 20, 60, 20), fill=(80, 120, 160, 2))
        image.putpixel((4, 15), (80, 120, 160, 3))
        result = cropper.keep_largest_alpha_component(image)
        self.assertEqual(image.getpixel((4, 15)), result.getpixel((4, 15)))
        self.assertEqual(255, result.getpixel((15, 15))[3])
        self.assertEqual(0, result.getpixel((65, 15))[3])
        self.assertEqual(0, result.getpixel((48, 20))[3])

    def test_review_requires_current_hash_and_explicit_evidence(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            with patch.object(recorder, "ROOT", root), patch.object(recorder, "CHAR_ROOT", root / "assets/characters"):
                paths = recorder.source_paths("example")
                for path in paths.values():
                    path.parent.mkdir(parents=True, exist_ok=True)
                    image = Image.new("RGBA", (32, 32))
                    ImageDraw.Draw(image).rectangle((8, 8, 23, 23), fill="navy")
                    image.save(path)
                meta = root / "assets/characters/example/meta"
                meta.mkdir()
                (meta / "example_generation_brief_v2.md").write_text("Test prompt")
                output = recorder.record_character("example")
                payload = json.loads(output.read_text())
                self.assertFalse(payload["batch_ready_allowed"])
                self.assertTrue(all(item["qa_verdict"] == "pending" for item in payload["source_images"]))
                review = {"character_id": "example", "sources": {
                    role: {"sha256": recorder.sha256_path(path), "verdict": "pass",
                           "reviewer": "test reviewer", "observation": "Explicit test evidence"}
                    for role, path in paths.items()
                }}
                review_path = meta / "example_source_review.json"
                review_path.write_text(json.dumps(review))
                self.assertTrue(json.loads(recorder.record_character("example").read_text())["batch_ready_allowed"])
                review["sources"]["concept_full"]["sha256"] = "stale"
                review_path.write_text(json.dumps(review))
                payload = json.loads(recorder.record_character("example").read_text())
                self.assertFalse(payload["batch_ready_allowed"])
                self.assertEqual("pending", payload["source_images"][0]["qa_verdict"])


if __name__ == "__main__":
    unittest.main()
