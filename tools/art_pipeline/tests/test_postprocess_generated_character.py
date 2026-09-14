from __future__ import annotations

import json
from pathlib import Path
import sys
import unittest

from PIL import Image, ImageDraw


ART_PIPELINE = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ART_PIPELINE))

import postprocess_generated_character as pipeline  # noqa: E402
import build_phase2_postprocess_plans as plan_builder  # noqa: E402
import character_roster  # noqa: E402


class VfxCropTests(unittest.TestCase):
    def test_disconnected_components_survive_vfx_crop(self) -> None:
        source = Image.new("RGBA", (240, 120), (0, 0, 0, 0))
        draw = ImageDraw.Draw(source)
        draw.ellipse((12, 28, 52, 68), fill=(255, 255, 255, 255))
        draw.ellipse((184, 44, 228, 88), fill=(0, 224, 255, 255))
        source_alpha_area = sum(value >= pipeline.ALPHA_THRESHOLD for value in source.getchannel("A").getdata())

        cropped, metadata = pipeline.crop_vfx_cell(source, pad=18)

        output_alpha_area = sum(value >= pipeline.ALPHA_THRESHOLD for value in cropped.getchannel("A").getdata())
        self.assertEqual(source_alpha_area, output_alpha_area)
        self.assertEqual("full_cell_alpha_bbox", metadata["auto_crop_method"])
        self.assertEqual(2, metadata["selected_component_count"])
        self.assertTrue(any(pixel[0] > 200 and pixel[3] > 0 for pixel in cropped.getdata()))
        self.assertTrue(any(pixel[2] > 200 and pixel[3] > 0 for pixel in cropped.getdata()))


class PlannedBindingTests(unittest.TestCase):
    def test_explicit_canvas_positions_replace_linear_distribution(self) -> None:
        source = Image.new("RGBA", (200, 120), (0, 0, 0, 0))
        draw = ImageDraw.Draw(source)
        draw.rectangle((12, 8, 188, 112), fill=(255, 255, 255, 255))
        points: dict[str, dict[str, int]] = {}
        plan = {
            "bindings": {"battle_rig_base": ["turret_mount_01", "asw_launch_01"]},
            "binding_positions": {
                "battle_rig_base": {
                    "turret_mount_01": {"x": 0.20, "y": 0.15},
                    "asw_launch_01": {"x": 0.15, "y": 0.75},
                }
            },
        }

        pipeline.add_planned_bindings("battle_rig_base", source, points, plan)

        self.assertLess(points["turret_mount_01"]["x"], 50)
        self.assertLess(points["turret_mount_01"]["y"], 30)
        self.assertLess(points["asw_launch_01"]["x"], 40)
        self.assertGreater(points["asw_launch_01"]["y"], 80)

    def test_jervis_checked_in_plan_matches_plan_builder(self) -> None:
        plan_path = pipeline.CHAR_ROOT / "jervis" / "postprocess_plan.json"
        checked_in = json.loads(plan_path.read_text(encoding="utf-8"))
        generated = plan_builder.build_plan(character_roster.roster_by_id("phase2")["jervis"])
        self.assertEqual(checked_in, generated)

    def test_all_phase2_plan_levels_match_roster(self) -> None:
        for entry in character_roster.load_roster(phase="phase2"):
            plan_path = pipeline.CHAR_ROOT / entry.character_id / "postprocess_plan.json"
            checked_in = json.loads(plan_path.read_text(encoding="utf-8"))
            with self.subTest(character_id=entry.character_id):
                self.assertEqual(int(entry.level.split()[0]), checked_in.get("level"))


if __name__ == "__main__":
    unittest.main()
