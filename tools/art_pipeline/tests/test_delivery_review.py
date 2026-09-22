from __future__ import annotations

import json
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch

from PIL import Image

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import delivery_review as delivery
import batch_character_art as batch


class DeliveryReviewTests(unittest.TestCase):
    def test_cli_rejects_unaccepted_batch_and_checks_every_character(self):
        for status in ("pending", "stale", "blocker", "invalid"):
            with self.subTest(status=status), patch.object(sys, "argv", ["delivery_review", "first", "second"]), \
                    patch.object(delivery, "inspect_review", side_effect=[
                        {"status": status, "accepted": False, "issues": ["test failure"]},
                        {"status": "pass", "accepted": True, "issues": []},
                    ]) as inspect, patch("builtins.print"):
                self.assertEqual(1, delivery.main())
                self.assertEqual(2, inspect.call_count)

    def test_cli_accepts_reviewed_batch(self):
        with patch.object(sys, "argv", ["delivery_review", "example"]), \
                patch.object(delivery, "inspect_review", return_value={
                    "status": "polish", "accepted": True, "issues": []}), patch("builtins.print"):
            self.assertEqual(0, delivery.main())

    def test_cli_prepare_succeeds_with_pending_checklist(self):
        with patch.object(sys, "argv", ["delivery_review", "example", "--prepare"]), \
                patch.object(Path, "read_text", return_value="{}"), \
                patch.object(delivery, "write_review") as write, \
                patch.object(delivery, "inspect_review", return_value={
                    "status": "pending", "accepted": False, "issues": ["pending"]}), patch("builtins.print"):
            self.assertEqual(0, delivery.main())
            write.assert_called_once()

    def setUp(self) -> None:
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        self.character = "test_character"
        self.base = self.root / "assets" / "characters" / self.character
        self.image = self.base / "processed" / "battle" / "body.png"
        self.image.parent.mkdir(parents=True)
        Image.new("RGBA", (32, 32), (30, 60, 90, 128)).save(self.image)
        self.config = self.base / "processed" / "config" / "test_character_anim_config.json"
        self.config.parent.mkdir()
        self.config.write_text('{}')
        self.manifest = {"components": [{"file": str(self.image.relative_to(self.root)),
                                        "source_crop_qa": {"edge_warnings": ["right"]}}]}

    def write(self) -> Path:
        return delivery.write_review(self.root, self.character, self.manifest)

    def accept(self, verdict: str = "pass") -> None:
        path = delivery.review_path(self.root, self.character)
        data = json.loads(path.read_text())
        for entry in data["assets"].values():
            entry["review"] = {"verdict": verdict, "reviewer": "test reviewer",
                               "observation": "Inspected fixture identity, crop edges and bindings."}
        path.write_text(json.dumps(data))

    def inspect(self) -> dict:
        return delivery.inspect_review(self.root, self.character)

    def test_missing_review_does_not_infer_visual_pass(self) -> None:
        self.assertEqual("pending", self.inspect()["status"])
        self.assertFalse(self.inspect()["accepted"])

    def test_shared_report_copies_crop_evidence_and_actual_alpha(self) -> None:
        data = json.loads(self.write().read_text())
        entry = next(iter(data["assets"].values()))
        self.assertEqual(["right"], entry["crop_evidence"]["edge_warnings"])
        self.assertEqual(128, entry["alpha_facts"]["alpha_min"])
        self.assertEqual("pending", self.inspect()["status"])

    def test_unchanged_reprocessing_preserves_explicit_review(self) -> None:
        self.write()
        self.accept("polish")
        self.write()
        self.assertEqual("polish", self.inspect()["status"])
        self.assertTrue(self.inspect()["accepted"])

    def test_changed_config_invalidates_review_then_resets_to_pending(self) -> None:
        self.write()
        self.accept()
        self.config.write_text('{"fps": 10}')
        self.assertEqual("stale", self.inspect()["status"])
        self.write()
        self.assertEqual("pending", self.inspect()["status"])

    def test_changed_source_or_output_invalidates_review(self) -> None:
        for filename in (self.base / "battle" / "source.png", self.image):
            with self.subTest(filename=filename):
                self.write()
                self.accept()
                filename.parent.mkdir(parents=True, exist_ok=True)
                Image.new("RGBA", (33, 33), "red").save(filename)
                self.assertEqual("stale", self.inspect()["status"])

    def test_missing_asset_is_not_silently_removed_from_review(self) -> None:
        self.write()
        self.accept()
        self.image.unlink()
        self.assertFalse(self.inspect()["accepted"])

    def test_blocker_and_unattributed_pass_are_not_accepted(self) -> None:
        path = self.write()
        self.accept("blocker")
        self.assertEqual("blocker", self.inspect()["status"])
        self.accept()
        data = json.loads(path.read_text())
        next(iter(data["assets"].values()))["review"]["reviewer"] = ""
        path.write_text(json.dumps(data))
        self.assertFalse(self.inspect()["accepted"])

    def test_shared_vfx_is_in_inventory_and_change_invalidates_review(self) -> None:
        shared = self.root / "assets" / "vfx" / "shared.png"
        shared.parent.mkdir()
        Image.new("RGBA", (30, 30), "white").save(shared)
        config = self.config.with_name("test_character_vfx_config.json")
        config.write_text(json.dumps({"roles": {"wake": {"file": "assets/vfx/shared.png"}}}))
        data = json.loads(self.write().read_text())
        self.assertIn("assets/vfx/shared.png", data["assets"])
        self.accept()
        Image.new("RGBA", (31, 31), "white").save(shared)
        self.assertEqual("stale", self.inspect()["status"])

    def test_malformed_review_fails_closed(self) -> None:
        path = self.write()
        path.write_text('[]')
        self.assertEqual("invalid", self.inspect()["status"])

    def test_batch_separates_technical_and_visual_acceptance(self) -> None:
        config = {"crop_specs": True, "runtime_config": True, "contract_ship_class": True}
        with patch.object(batch, "ROOT", self.root), \
             patch.object(batch, "source_check", return_value={"complete": True}), \
             patch.object(batch, "configuration_check", return_value=config), \
             patch.object(batch.contract, "audit", return_value={"status": "complete"}):
            inspection = batch.inspect_character(self.character)
            self.assertTrue(inspection["technical_ready"])
            self.assertFalse(inspection["delivery_ready"])
            self.write()
            self.accept()
            self.assertTrue(batch.inspect_character(self.character)["delivery_ready"])


if __name__ == "__main__":
    unittest.main()
