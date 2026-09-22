from __future__ import annotations

from contextlib import ExitStack
import json
import hashlib
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch

from PIL import Image, ImageDraw

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import batch_character_art as batch
import postprocess_generated_character as adapter
import postprocess_trial_sheets as legacy
from test_postprocess_generated_character import flattened_pixels


class LegacyCropTests(unittest.TestCase):
    def test_dark_legacy_spill_is_neutralized_without_erasing_outline(self) -> None:
        image = Image.new("RGB", (64, 64), (12, 225, 15))
        ImageDraw.Draw(image).rectangle((20, 20, 43, 43), fill=(20, 70, 30))
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "body.png"
            image.save(path)
            result = adapter.remove_generated_background(path)
            self.assertEqual((20, 30, 30, 255), result.getpixel((31, 31)))
            self.assertEqual(0, result.getpixel((0, 0))[3])

    def test_legacy_vfx_key_recovers_cyan_lines_and_preserves_native_alpha(self) -> None:
        image = Image.new("RGBA", (64, 64), (12, 225, 15, 255))
        ImageDraw.Draw(image).ellipse((15, 15, 48, 48), outline=(40, 245, 150, 255), width=2)
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "vfx" / "old.png"
            path.parent.mkdir()
            image.save(path)
            with self.assertRaisesRegex(ValueError, "not native-alpha"):
                adapter.remove_generated_background(path, allow_legacy_background=False)
            result = adapter.remove_generated_background(path, allow_legacy_background=True)
            self.assertEqual(0, result.getpixel((0, 0))[3])
            self.assertGreater(result.getpixel((31, 15))[3], 100)
            self.assertEqual(image.getpixel((31, 15))[:3], (40, 245, 150))
            image.putpixel((0, 0), (0, 0, 0, 0))
            image.save(path)
            self.assertEqual(image.tobytes(), adapter.remove_generated_background(path).tobytes())

    def test_safety_margin_excludes_neighbor_strip_but_preserves_vfx_islands(self) -> None:
        source = Image.new("RGBA", (180, 160))
        draw = ImageDraw.Draw(source)
        draw.rectangle((20, 20, 150, 35), fill=(255, 0, 0, 255))
        draw.rectangle((40, 42, 70, 100), fill=(0, 255, 0, 255))
        draw.rectangle((95, 50, 110, 65), fill=(0, 0, 255, 255))
        draw.rectangle((38, 42, 39, 100), fill=(0, 255, 0, 5))
        result, metadata = adapter.crop_from_source(source, (45, 48, 105, 90))
        pixels = list(flattened_pixels(result))
        self.assertFalse(any(p[0] == 255 and p[3] for p in pixels))
        self.assertEqual(31 * 59 + 16 * 16, adapter.alpha_pixel_count(result))
        self.assertEqual(2 * 59, sum(p == (0, 255, 0, 5) for p in pixels))
        self.assertEqual(adapter.alpha_pixel_count(result), metadata["source_alpha_pixel_count"])
        self.assertGreater(metadata["source_crop_rectangle_alpha_pixel_count"], metadata["source_alpha_pixel_count"])
        self.assertEqual(1, metadata["excluded_neighbor_components"])

    def test_crossing_grid_boundary_retains_complete_subject(self) -> None:
        source = Image.new("RGBA", (320, 160))
        ImageDraw.Draw(source).rectangle((40, 40, 225, 110), fill=(100, 150, 220, 255))
        # The object crosses the old mathematical x=160 boundary.
        hint = (70, 50, 140, 100)
        result, metadata = adapter.crop_from_source(source, hint)
        reference, _ = legacy.prepare_crop(source, hint)
        self.assertEqual(reference.tobytes(), result.tobytes())
        self.assertEqual(reference.size, result.size)
        self.assertEqual(adapter.alpha_pixel_count(source), adapter.alpha_pixel_count(result))
        self.assertGreater(metadata["final_crop_box"][2], 225)
        self.assertEqual(list(hint), metadata["original_crop_hint"])
        self.assertEqual("connected_components_intersecting_initial_box", metadata["auto_crop_method"])

    def test_authored_hint_does_not_select_intruding_neighbor(self) -> None:
        source = Image.new("RGBA", (320, 320))
        draw = ImageDraw.Draw(source)
        draw.rectangle((30, 30, 110, 190), fill=(255, 0, 0, 255))  # boots cross y=160
        draw.rectangle((50, 220, 120, 285), fill=(0, 0, 255, 255))
        result, metadata = adapter.crop_from_source(source, (60, 230, 100, 270))
        self.assertEqual(1, metadata["selected_component_count"])
        self.assertEqual(71 * 66, adapter.alpha_pixel_count(result))
        self.assertFalse(any(pixel[0] == 255 and pixel[3] for pixel in flattened_pixels(result)))

    def test_vfx_preserves_disconnected_islands_and_native_colors(self) -> None:
        source = Image.new("RGBA", (240, 120))
        draw = ImageDraw.Draw(source)
        draw.rectangle((20, 30, 50, 60), fill=(255, 255, 255, 255))
        draw.rectangle((180, 35, 210, 65), fill=(0, 255, 0, 255))
        result, metadata = adapter.crop_from_source(source, (25, 40, 200, 55))
        self.assertEqual(2, metadata["selected_component_count"])
        self.assertEqual(adapter.alpha_pixel_count(source), adapter.alpha_pixel_count(result))
        self.assertEqual(metadata["source_alpha_pixel_count"], adapter.alpha_pixel_count(result))
        self.assertTrue(any(pixel == (0, 255, 0, 255) for pixel in flattened_pixels(result)))

    def test_legacy_source_ingestion_preserves_native_alpha_byte_for_byte(self) -> None:
        source = Image.new("RGBA", (100, 100))
        draw = ImageDraw.Draw(source)
        draw.rectangle((25, 25, 75, 75), fill=(255, 255, 255, 255))
        draw.rectangle((30, 30, 40, 40), fill=(0, 255, 0, 180))
        self.assertEqual(source.tobytes(), legacy.rgba_with_alpha_from_light_bg(source).tobytes())

    def test_legacy_save_crop_is_unchanged_by_shared_extraction(self) -> None:
        source = Image.new("RGBA", (100, 100))
        ImageDraw.Draw(source).rectangle((30, 30, 60, 60), fill="white")
        image, expected = legacy.prepare_crop(source, (35, 35, 55, 55))
        with tempfile.TemporaryDirectory() as tmp, patch.object(legacy, "ROOT", Path(tmp)):
            out = Path(tmp) / "asset.png"
            actual = legacy.save_crop(source, (35, 35, 55, 55), out)
            self.assertEqual({"file": "asset.png", **expected}, actual)
            with Image.open(out) as saved:
                self.assertEqual(image.tobytes(), saved.tobytes())


class LegacyRoutingTests(unittest.TestCase):
    def setUp(self) -> None:
        self.stack = ExitStack()
        self.addCleanup(self.stack.close)
        self.root = Path(self.stack.enter_context(tempfile.TemporaryDirectory()))
        self.characters = self.root / "assets" / "characters"
        for module in (adapter, legacy):
            self.stack.enter_context(patch.object(module, "ROOT", self.root))
            self.stack.enter_context(patch.object(module, "CHAR_ROOT", self.characters))
        self.character = "tashkent"
        self.paths = adapter.source_paths(self.character)
        self.sheet = Image.new("RGBA", (240, 120))
        ImageDraw.Draw(self.sheet).rectangle((30, 30, 210, 90), fill=(30, 80, 160, 255))
        for key in ("concept_full", "ui_sheet", "battle_grid", "vfx_sheet",
                    *(f"anim_{state}" for state in adapter.ANIMATION_STATES)):
            self.paths[key].parent.mkdir(parents=True, exist_ok=True)
            self.sheet.save(self.paths[key])
        self.spec_path = self.characters / self.character / "meta" / f"{self.character}_crop_specs.json"

    def write_specs(self) -> dict:
        specs = {role: {"source": "ui_sheet", "box": [90, 45, 150, 75]}
                 for role in adapter.required_crop_roles("destroyer", {})}
        self.spec_path.parent.mkdir(parents=True, exist_ok=True)
        self.spec_path.write_text(json.dumps({"character_id": self.character, "crops": specs}))
        return specs

    def test_missing_specs_cannot_silently_fall_back_to_grid(self) -> None:
        self.assertTrue(adapter.has_source_package(self.character))
        self.assertFalse(adapter.can_process(self.character))
        with self.assertRaisesRegex(ValueError, "Missing legacy crop specs"):
            adapter.process_character(self.character)
        self.assertFalse((self.characters / self.character / "processed").exists())

    def test_hash_bound_hints_reject_same_size_replacement_before_output(self) -> None:
        specs = self.write_specs()
        payload = {"character_id": self.character, "crops": specs, "source_sha256": {
            "ui_sheet": hashlib.sha256(self.paths["ui_sheet"].read_bytes()).hexdigest()}}
        self.spec_path.write_text(json.dumps(payload))
        self.assertEqual(specs, adapter.load_crop_specs(self.character, "destroyer", {}))
        changed = self.sheet.copy()
        changed.putpixel((40, 40), (255, 0, 0, 255))
        changed.save(self.paths["ui_sheet"])
        with self.assertRaisesRegex(ValueError, "Stale crop source: ui_sheet"):
            adapter.process_character(self.character)
        self.assertFalse((self.characters / self.character / "processed").exists())

    def test_hash_bound_hints_require_exact_source_coverage(self) -> None:
        specs = self.write_specs()
        for hashes in ({}, {"unknown": "hash"}, []):
            with self.subTest(hashes=hashes):
                self.spec_path.write_text(json.dumps({"character_id": self.character,
                    "crops": specs, "source_sha256": hashes}))
                with self.assertRaisesRegex(ValueError, "crop source_sha256"):
                    adapter.load_crop_specs(self.character, "destroyer", {})

    def test_incomplete_specs_fail_before_any_output(self) -> None:
        specs = self.write_specs()
        del specs["anim_hit_frame_03"]
        self.spec_path.write_text(json.dumps({"character_id": self.character, "crops": specs}))
        with self.assertRaisesRegex(ValueError, "anim_hit_frame_03"):
            legacy.process_character(self.character)
        self.assertFalse((self.characters / self.character / "processed").exists())

    def test_native_sources_use_legacy_engine_for_every_split_role(self) -> None:
        specs = self.write_specs()
        self.assertTrue(adapter.can_process(self.character))
        with patch.object(adapter, "split_grid", side_effect=AssertionError("hard grid cut")), \
             patch.object(legacy, "prepare_crop", wraps=legacy.prepare_crop) as extraction, \
             patch.object(adapter, "build_contact_sheet"):
            adapter.process_character(self.character)
        self.assertEqual(len(specs) + 3, extraction.call_count)
        manifest_path = self.characters / self.character / "processed" / "config" / f"{self.character}_postprocess_manifest.json"
        manifest = json.loads(manifest_path.read_text())
        self.assertEqual("legacy_source_hint_component_split", manifest["method"])
        for output in manifest["outputs"]:
            if output["role"] in specs:
                self.assertEqual("connected_components_intersecting_initial_box", output["crop"]["auto_crop_method"])
                self.assertEqual(adapter.alpha_pixel_count(self.sheet), output["alpha_pixel_count"])

    def test_vfx_cleanup_cannot_drop_components(self) -> None:
        specs = self.write_specs()
        specs["vfx:speed_wake"]["tags"] = ["keep_largest_component"]
        self.spec_path.write_text(json.dumps({"character_id": self.character, "crops": specs}))
        with self.assertRaisesRegex(ValueError, "VFX must retain"):
            adapter.load_crop_specs(self.character, "destroyer", {})

    def test_frozen_recrop_preserves_historical_schema_across_two_rebuilds(self) -> None:
        self.character = "fletcher"
        self.paths = adapter.source_paths(self.character)
        for key in ("concept_full", "ui_sheet", "battle_grid", "vfx_sheet",
                    *(f"anim_{state}" for state in adapter.ANIMATION_STATES)):
            self.paths[key].parent.mkdir(parents=True, exist_ok=True)
            self.sheet.save(self.paths[key])
        base = self.characters / self.character
        self.spec_path = base / "meta" / "fletcher_crop_specs.json"
        self.write_specs()
        (base / "postprocess_plan.json").write_text(json.dumps({
            "character_id": self.character, "manifest_schema_version": 2}))
        manifest_path = base / "processed" / "config" / "fletcher_postprocess_manifest.json"
        manifest_path.parent.mkdir(parents=True)
        manifest_path.write_text(json.dumps({"character_id": self.character, "outputs": []}))
        with patch.object(adapter, "build_contact_sheet"):
            for _ in range(2):
                adapter.process_character(self.character)
                manifest = json.loads(manifest_path.read_text())
                self.assertEqual(1, manifest["schema_version"])
                self.assertNotIn("source_provenance", manifest)
                self.assertTrue(adapter.is_frozen_legacy_package(self.character, manifest_path))

    def test_plan_alone_is_not_a_crop_configuration(self) -> None:
        self.assertFalse(batch.is_configured({"crop_specs": False, "runtime_config": False,
                                             "postprocess_plan": True, "generic_postprocess": False,
                                             "contract_ship_class": True}))

    def test_batch_dispatches_through_legacy_entry(self) -> None:
        inspection = {"postprocess_ready": True, "batch_ready": True}
        with patch.object(batch, "inspect_character", return_value=inspection), \
             patch.object(legacy, "process_character") as process:
            self.assertEqual("complete", batch.process_one(self.character, False)["status"])
        process.assert_called_once_with(self.character)


if __name__ == "__main__":
    unittest.main()
