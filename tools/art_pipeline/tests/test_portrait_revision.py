import json
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch

from PIL import Image, ImageDraw

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import portrait_revision as portraits
import postprocess_trial_sheets as legacy
import postprocess_generated_character as adapter


class PortraitRevisionTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.raw = self.root / "raw.png"
        image = Image.new("RGBA", (701, 923))
        ImageDraw.Draw(image).ellipse((80, 20, 650, 900), fill=(235, 230, 220, 255))
        image.save(self.raw)
        self.reference = self.root / "identity.png"
        image.save(self.reference)
        portraits.register(self.root, "test_ship", self.raw, "unframed portrait", [self.reference], "Inspected test fixture")

    def test_normalized_pair_is_square_and_has_eight_percent_margin(self):
        images = portraits.normalized_portraits(self.raw)
        for semantic, size in portraits.SIZES.items():
            image = images[semantic]
            self.assertEqual((size, size), image.size)
            box = image.getchannel("A").getbbox()
            self.assertGreaterEqual(min(box[0], box[1], size-box[2], size-box[3]), size*.08)
        expected = images["ui_portrait"].convert("RGBa").resize((128,128), Image.Resampling.LANCZOS).convert("RGBA")
        self.assertEqual(expected.tobytes(), images["ui_portrait_small"].tobytes())

    def test_override_replaces_duplicate_old_entries_without_touching_history(self):
        for key in ("outputs", "components"):
            old = "assets/characters/test_ship/processed/ui/test_ship_ui_portrait.png"
            manifest = {key: [{"path": old}, {"file": old}, {"path": "battle/unchanged.png"}],
                        "source_provenance": {"immutable": "legacy"}}
            self.assertTrue(portraits.apply_revision(self.root,"test_ship",manifest))
            self.assertEqual(3, len(manifest[key]))
            self.assertEqual({"immutable":"legacy"},manifest["source_provenance"])
            self.assertEqual("battle/unchanged.png",manifest[key][0]["path"])

    def test_stale_source_cannot_overwrite_existing_outputs(self):
        source, _ = portraits.locations(self.root,"test_ship")
        source.write_bytes(b"changed")
        manifest = {"components":[{"file":"original"}]}
        with self.assertRaises(ValueError): portraits.apply_revision(self.root,"test_ship",manifest)
        self.assertEqual({"components":[{"file":"original"}]},manifest)

    def test_reference_change_and_pending_review_are_rejected(self):
        self.reference.write_bytes(b"changed")
        with self.assertRaises(ValueError): portraits.load_revision(self.root,"test_ship")
        self.raw.replace(self.reference)
        _, path = portraits.locations(self.root,"test_ship")
        data=json.loads(path.read_text());data["source_review"]["verdict"]="pending"
        path.write_text(json.dumps(data))
        with self.assertRaises(ValueError): portraits.load_revision(self.root,"test_ship")

    def test_output_reviews_are_bound_to_actual_pixels(self):
        manifest={"components":[]}
        portraits.apply_revision(self.root,"test_ship",manifest)
        manifest_path=self.root/"assets/characters/test_ship/processed/config/test_ship_postprocess_manifest.json"
        manifest_path.parent.mkdir(parents=True)
        manifest_path.write_text(json.dumps(manifest))
        self.assertEqual(2,len(portraits.validate_revision(self.root,"test_ship")))
        _, path=portraits.locations(self.root,"test_ship");data=json.loads(path.read_text())
        for semantic in portraits.SIZES:
            output=self.root/"assets/characters/test_ship/processed/ui"/f"test_ship_{semantic}.png"
            data["output_reviews"][semantic]={"sha256":portraits.checksum(output),"verdict":"pass","reviewer":"tester","observation":"fixture inspected"}
        path.write_text(json.dumps(data))
        portraits.apply_revision(self.root,"test_ship",manifest)
        manifest_path.write_text(json.dumps(manifest))
        self.assertEqual([],portraits.validate_revision(self.root,"test_ship"))
        output=self.root/"assets/characters/test_ship/processed/ui/test_ship_ui_portrait_small.png"
        Image.new("RGBA",(128,128),(0,0,0,255)).save(output)
        self.assertTrue(portraits.validate_revision(self.root,"test_ship"))

    def test_manifest_output_hash_and_source_cannot_be_stale(self):
        manifest={"outputs":[]}
        portraits.apply_revision(self.root,"test_ship",manifest)
        path=self.root/"assets/characters/test_ship/processed/config/test_ship_postprocess_manifest.json"
        path.parent.mkdir(parents=True)
        for field in ("sha256", "source"):
            data=json.loads(json.dumps(manifest))
            data["outputs"][0][field]="stale"
            path.write_text(json.dumps(data))
            self.assertIn("ui_portrait: manifest output/source hash missing/stale",portraits.validate_revision(self.root,"test_ship"))

    def test_independent_portrait_reviews_survive_unrelated_package_change(self):
        import delivery_review
        manifest={"components":[]}
        portraits.apply_revision(self.root,"test_ship",manifest)
        source, revision_path=portraits.locations(self.root,"test_ship")
        data=json.loads(revision_path.read_text())
        base=source.parents[1]/"processed"
        for semantic in portraits.SIZES:
            data["output_reviews"][semantic]={"sha256":portraits.checksum(base/"ui"/f"test_ship_{semantic}.png"),
                "verdict":"pass","reviewer":"tester","observation":"Actual fixture inspected"}
        revision_path.write_text(json.dumps(data))
        portraits.apply_revision(self.root,"test_ship",manifest)
        config=base/"config";config.mkdir(parents=True)
        (config/"test_ship_postprocess_manifest.json").write_text(json.dumps(manifest))
        extra=base/"ui/other.png";Image.new("RGBA",(64,64),"red").save(extra)
        review_path=delivery_review.write_review(self.root,"test_ship",manifest)
        (config/"unrelated.json").write_text('{"changed":true}')
        delivery_review.write_review(self.root,"test_ship",manifest)
        reviews=json.loads(review_path.read_text())["assets"]
        for semantic in portraits.SIZES:
            self.assertEqual("pass",reviews[f"assets/characters/test_ship/processed/ui/test_ship_{semantic}.png"]["review"]["verdict"])
        self.assertEqual("pending",reviews[str(extra.relative_to(self.root))]["review"]["verdict"])

    def test_both_entrypoints_preserve_new_portrait_after_old_framed_sheet_split(self):
        base = self.root / "assets/characters/test_ship"
        old_sheet = base / "ui/old_ui.png"
        image = Image.new("RGBA", (128, 128), (20, 40, 70, 255))
        ImageDraw.Draw(image).rectangle((4, 4, 123, 123), outline=(255, 20, 20, 255), width=10)
        image.save(old_sheet)
        specs = [legacy.CropSpec("ui/old_ui.png", "processed/ui", f"test_ship_{semantic}.png", (0,0,128,128), ("ui",))
                 for semantic in portraits.SIZES]
        config = {"battle_bind_points": {}, "animation_states": {}, "vfx_roles": {}, "ship_class": "destroyer"}
        with patch.object(legacy,"ROOT",self.root), patch.object(legacy,"CHAR_ROOT",base.parent), \
             patch.dict(legacy.SPECS,{"test_ship":specs}), patch.dict(legacy.CONFIGS,{"test_ship":config}), \
             patch.object(legacy,"write_source_alpha",return_value={}):
            for entrypoint in (legacy.process_character, adapter.process_character):
                entrypoint("test_ship")
                for semantic, expected in portraits.normalized_portraits(self.raw).items():
                    with Image.open(base / "processed/ui" / f"test_ship_{semantic}.png") as actual:
                        self.assertEqual(expected.tobytes(), actual.tobytes())

    def test_both_entrypoints_reject_stale_revision_before_writes(self):
        source, _ = portraits.locations(self.root,"test_ship")
        source.write_bytes(b"changed")
        with patch.object(legacy,"ROOT",self.root), patch.object(adapter,"ROOT",self.root):
            for entrypoint in (legacy.process_character, adapter.process_generated_sources):
                with self.assertRaises(ValueError): entrypoint("test_ship")
        self.assertFalse((source.parents[1] / "processed").exists())

    def test_raw_source_and_generation_provenance_must_remain_consistent(self):
        _, path=portraits.locations(self.root,"test_ship")
        data=json.loads(path.read_text());data["raw_sha256"]="changed"
        path.write_text(json.dumps(data))
        with self.assertRaisesRegex(ValueError,"preserved raw"): portraits.load_revision(self.root,"test_ship")


if __name__ == "__main__": unittest.main()
