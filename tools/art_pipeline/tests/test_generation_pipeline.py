from __future__ import annotations

import base64
from io import BytesIO
import json
from pathlib import Path
from types import SimpleNamespace
import sys
import tempfile
import unittest

import httpx
from openai import OpenAI
from PIL import Image, ImageDraw


ART_PIPELINE = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ART_PIPELINE))

import build_phase2_generation_briefs as brief_builder  # noqa: E402
import character_roster  # noqa: E402
import generate_character_art as generator  # noqa: E402
import generation_contract as contract  # noqa: E402
import postprocess_generated_character as postprocess  # noqa: E402


def png_bytes(mode: str, background: tuple[int, ...]) -> bytes:
    image = Image.new(mode, (64, 64), background)
    draw = ImageDraw.Draw(image)
    fill = (30, 80, 160, 255) if mode == "RGBA" else (30, 80, 160)
    draw.rectangle((16, 16, 47, 47), fill=fill)
    output = BytesIO()
    image.save(output, format="PNG")
    return output.getvalue()


class RawResponse:
    def __init__(self, payload: bytes, request_id: str = "req_test") -> None:
        self.headers = {"x-request-id": request_id}
        self._parsed = SimpleNamespace(
            data=[SimpleNamespace(b64_json=base64.b64encode(payload).decode("ascii"))]
        )

    def parse(self) -> SimpleNamespace:
        return self._parsed


class FakeImageMethods:
    def __init__(self, payload: bytes) -> None:
        self.payload = payload
        self.calls: list[tuple[str, dict[str, object]]] = []

    def generate(self, **kwargs: object) -> RawResponse:
        self.calls.append(("generate", kwargs))
        return RawResponse(self.payload)

    def edit(self, **kwargs: object) -> RawResponse:
        self.calls.append(("edit", kwargs))
        return RawResponse(self.payload)


class GenerationContractTests(unittest.TestCase):
    def test_native_alpha_accepts_real_transparency(self) -> None:
        facts = contract.image_facts(png_bytes("RGBA", (0, 0, 0, 0)))

        self.assertEqual([], contract.native_alpha_issues(facts))
        self.assertTrue(facts["has_alpha_channel"])
        self.assertEqual(0, facts["alpha_min"])
        self.assertEqual(255, facts["alpha_max"])

    def test_native_alpha_rejects_painted_checkerboard(self) -> None:
        image = Image.new("RGB", (64, 64), (230, 230, 230))
        draw = ImageDraw.Draw(image)
        for y in range(0, 64, 8):
            for x in range(0, 64, 8):
                if (x // 8 + y // 8) % 2:
                    draw.rectangle((x, y, x + 7, y + 7), fill=(170, 170, 170))
        output = BytesIO()
        image.save(output, format="PNG")

        issues = contract.native_alpha_issues(contract.image_facts(output.getvalue()))

        self.assertIn("source has no alpha channel", issues)
        self.assertTrue(any("transparent" in issue for issue in issues))

    def test_center_padding_keeps_faint_alpha_off_canvas_edge(self) -> None:
        image = Image.new("RGBA", (32, 32), (0, 0, 0, 0))
        image.putpixel((0, 15), (40, 80, 120, 1))
        ImageDraw.Draw(image).rectangle((8, 8, 23, 23), fill=(40, 80, 120, 255))

        centered = postprocess.center_alpha_with_padding(image, 4)
        left, top, right, bottom = centered.getchannel("A").getbbox()

        self.assertGreaterEqual(left, 4)
        self.assertGreaterEqual(top, 4)
        self.assertGreaterEqual(centered.width - right, 4)
        self.assertGreaterEqual(centered.height - bottom, 4)

    def test_legacy_fallback_requires_explicit_activation_and_reason(self) -> None:
        provenance = {
            "generation_policy": {
                "legacy_fallback": {
                    "authorized": True,
                    "activation": "--allow-legacy-chroma-fallback",
                    "reason": "two native-alpha attempts failed",
                    "native_failures": ["attempt 1: opaque", "attempt 2: opaque"],
                }
            }
        }
        self.assertTrue(contract.legacy_fallback_authorized(provenance))
        provenance["generation_policy"]["legacy_fallback"]["reason"] = ""
        self.assertFalse(contract.legacy_fallback_authorized(provenance))

    def test_only_frozen_pre_migration_package_skips_new_provenance(self) -> None:
        # Test historical shapes, not live art that can legitimately migrate.
        with tempfile.TemporaryDirectory() as temporary:
            manifest = Path(temporary) / "manifest.json"
            manifest.write_text(json.dumps({"schema_version": 1}))
            self.assertTrue(contract.is_frozen_legacy_package("fletcher", manifest))
            self.assertFalse(contract.is_frozen_legacy_package("belfast", manifest))
            manifest.write_text(json.dumps({
                "schema_version": 2, "source_provenance": {"schema_version": 1},
            }))
            self.assertTrue(contract.is_frozen_legacy_package("jervis", manifest))
            self.assertFalse(contract.is_frozen_legacy_package("belfast", manifest))
            manifest.write_text(json.dumps({
                "schema_version": 2, "source_provenance": {"schema_version": 2},
            }))
            for cid in ["fletcher", "jervis", "belfast"]:
                self.assertFalse(contract.is_frozen_legacy_package(cid, manifest))

    def test_derivative_requires_reviewed_anchor_hash(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            anchor = Path(temporary) / "anchor.png"
            anchor.write_bytes(png_bytes("RGBA", (0, 0, 0, 0)))
            provenance = {
                "schema_version": 2,
                "source_images": [
                    {
                        "role": "concept_full",
                        "sha256": generator.sha256_path(anchor),
                        "technical_qa_verdict": "pass",
                        "qa_verdict": "pending",
                    }
                ],
            }

            self.assertIn(
                "style anchor semantic QA verdict must be pass",
                generator.accepted_anchor_issues(provenance, anchor),
            )
            provenance["source_images"][0]["qa_verdict"] = "pass"
            self.assertEqual([], generator.accepted_anchor_issues(provenance, anchor))

    def test_strict_policy_requires_complete_verified_source_inventory(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            source_images = []
            for role in sorted(contract.EXPECTED_SOURCE_ROLES):
                path = root / f"{role}.png"
                path.write_bytes(png_bytes("RGBA", (0, 0, 0, 0)))
                facts = contract.image_facts(path)
                source_images.append(
                    {
                        "role": role,
                        "path": path.name,
                        "generation_route": contract.NATIVE_ALPHA_ROUTE,
                        "model": "gpt-image-2.5-sunburst",
                        "quality": "high",
                        "size_control": "1024x1024",
                        "background_control": "transparent",
                        "output_format": "PNG",
                        "endpoint": "/v1/images/generations" if role == "concept_full" else "/v1/images/edits",
                        "request_id": f"req_{role}",
                        "sha256": "same-hash",
                        "raw_response_sha256": "same-hash",
                        "accepted_source_is_raw_response": True,
                        "technical_qa_verdict": "pass",
                        "alpha": {
                            "has_alpha_channel": facts["has_alpha_channel"],
                            "min": facts["alpha_min"],
                            "max": facts["alpha_max"],
                            "transparent_canvas_ratio": facts["transparent_canvas_ratio"],
                            "transparent_border_ratio": facts["transparent_border_ratio"],
                        },
                    }
                )
            provenance = {
                "schema_version": 2,
                "generation_policy": {
                    "primary_route": contract.NATIVE_ALPHA_ROUTE,
                    "legacy_fallback": {
                        "authorized": False,
                        "activation": "--allow-legacy-chroma-fallback",
                        "reason": "",
                        "native_failures": [],
                    }
                },
                "generation": {
                    "requested_model": "gpt-image-2.5-sunburst",
                    "actual_model": "gpt-image-2.5-sunburst",
                    "output_format": "PNG",
                },
                "source_images": source_images,
            }

            self.assertEqual([], contract.strict_source_policy_issues(provenance, root))
            source_images[0]["request_id"] = "not-exposed"
            self.assertTrue(
                any(
                    "request ID is not verified" in issue
                    for issue in contract.strict_source_policy_issues(provenance, root)
                )
            )

    def test_strict_policy_accepts_codex_builtin_native_alpha(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            source_images = []
            for role in sorted(contract.EXPECTED_SOURCE_ROLES):
                path = root / f"{role}.png"
                path.write_bytes(png_bytes("RGBA", (0, 0, 0, 0)))
                facts = contract.image_facts(path)
                source_images.append(
                    {
                        "role": role,
                        "path": path.name,
                        "generation_route": contract.CODEX_BUILTIN_ROUTE,
                        "model": contract.CODEX_BUILTIN_MODEL,
                        "quality": "Codex account-managed",
                        "size_control": "Codex account-managed",
                        "background_control": "transparent",
                        "output_format": "PNG",
                        "endpoint": "codex_builtin_imagegen",
                        "sha256": "same-hash",
                        "raw_response_sha256": "same-hash",
                        "accepted_source_is_raw_response": True,
                        "technical_qa_verdict": "pass",
                        "alpha": {
                            "has_alpha_channel": facts["has_alpha_channel"],
                            "min": facts["alpha_min"],
                            "max": facts["alpha_max"],
                            "transparent_canvas_ratio": facts["transparent_canvas_ratio"],
                            "transparent_border_ratio": facts["transparent_border_ratio"],
                        },
                    }
                )
            provenance = {
                "schema_version": 2,
                "generation_policy": {
                    "primary_route": contract.CODEX_BUILTIN_ROUTE,
                    "legacy_fallback": {"authorized": False},
                },
                "generation": {
                    "requested_model": contract.CODEX_BUILTIN_MODEL,
                    "actual_model": contract.CODEX_BUILTIN_MODEL,
                    "generation_tool": "Codex built-in ImageGen",
                    "output_format": "PNG",
                },
                "source_images": source_images,
            }

            self.assertEqual([], contract.strict_source_policy_issues(provenance, root))

    def test_api_request_sets_native_transparency_controls(self) -> None:
        methods = FakeImageMethods(png_bytes("RGBA", (0, 0, 0, 0)))
        client = SimpleNamespace(images=SimpleNamespace(with_raw_response=methods))

        payload, request_id, endpoint = generator.request_image(
            client,
            prompt="test",
            model="gpt-image-2.5-sunburst",
            quality="high",
            size="1024x1024",
            background="transparent",
            reference=None,
        )

        self.assertTrue(payload)
        self.assertEqual("req_test", request_id)
        self.assertEqual("/v1/images/generations", endpoint)
        method, kwargs = methods.calls[0]
        self.assertEqual("generate", method)
        self.assertEqual("transparent", kwargs["background"])
        self.assertEqual("png", kwargs["output_format"])
        self.assertEqual("gpt-image-2.5-sunburst", kwargs["model"])

    def test_openai_sdk_serializes_native_controls_for_generate_and_edit(self) -> None:
        image_payload = png_bytes("RGBA", (0, 0, 0, 0))
        requests: list[tuple[str, bytes]] = []

        def handler(request: httpx.Request) -> httpx.Response:
            requests.append((request.url.path, request.content))
            return httpx.Response(
                200,
                headers={"x-request-id": "req_transport"},
                json={"created": 0, "data": [{"b64_json": base64.b64encode(image_payload).decode("ascii")}]},
            )

        with httpx.Client(transport=httpx.MockTransport(handler)) as http_client:
            client = OpenAI(api_key="test", base_url="https://unit.test/v1", http_client=http_client)
            generator.request_image(
                client,
                prompt="test",
                model="gpt-image-2.5-sunburst",
                quality="high",
                size="1024x1024",
                background="transparent",
                reference=None,
            )
            with tempfile.TemporaryDirectory() as temporary:
                reference = Path(temporary) / "anchor.png"
                reference.write_bytes(image_payload)
                generator.request_image(
                    client,
                    prompt="edit test",
                    model="gpt-image-2.5-sunburst",
                    quality="high",
                    size="1024x1024",
                    background="transparent",
                    reference=reference,
                )

        generate_path, generate_body = requests[0]
        self.assertEqual("/v1/images/generations", generate_path)
        generate_json = json.loads(generate_body)
        self.assertEqual("transparent", generate_json["background"])
        self.assertEqual("png", generate_json["output_format"])
        edit_path, edit_body = requests[1]
        self.assertEqual("/v1/images/edits", edit_path)
        self.assertIn(b'name="background"', edit_body)
        self.assertIn(b"transparent", edit_body)
        self.assertIn(b'name="output_format"', edit_body)
        self.assertIn(b"png", edit_body)

    def test_postprocess_preserves_native_alpha_and_green_art(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            path = Path(temporary) / "native.png"
            image = Image.new("RGBA", (64, 64), (0, 0, 0, 0))
            ImageDraw.Draw(image).rectangle((16, 16, 47, 47), fill=(0, 255, 0, 255))
            image.save(path)

            processed = postprocess.remove_generated_background(
                path,
                allow_legacy_background=False,
            )

            self.assertEqual((0, 255, 0, 255), processed.getpixel((32, 32)))
            self.assertEqual((0, 0, 0, 0), processed.getpixel((0, 0)))

    def test_legacy_cleanup_requires_explicit_permission(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            path = Path(temporary) / "legacy.png"
            path.write_bytes(png_bytes("RGB", (0, 255, 0)))

            with self.assertRaises(ValueError):
                postprocess.remove_generated_background(path, allow_legacy_background=False)
            processed = postprocess.remove_generated_background(path, allow_legacy_background=True)
            self.assertEqual(0, processed.getpixel((0, 0))[3])

    def test_default_brief_has_no_chroma_background_instruction(self) -> None:
        entry = character_roster.roster_by_id("phase2")["belfast"]
        plan_path = generator.CHAR_ROOT / entry.character_id / "postprocess_plan.json"
        plan = json.loads(plan_path.read_text(encoding="utf-8"))

        brief = brief_builder.build_brief(entry, plan)

        self.assertNotIn("reserved green", brief.lower())
        self.assertNotIn("green background", brief.lower())
        self.assertIn('background: "transparent"', brief)

    def test_legacy_provenance_uses_versioned_native_brief(self) -> None:
        self.assertEqual(
            generator.CHAR_ROOT / "jervis" / "meta" / "jervis_generation_brief_v2.md",
            brief_builder.generation_brief_path("jervis"),
        )
        self.assertEqual(
            generator.CHAR_ROOT / "jervis" / "meta" / "jervis_source_provenance_v2.json",
            generator.source_provenance_path("jervis"),
        )

    def test_versioned_briefs_preserve_legacy_prompt_hashes(self) -> None:
        for character_id in ("jervis", "tashkent", "chapayev", "gangut", "k_21"):
            root = generator.CHAR_ROOT / character_id
            provenance = json.loads(
                (root / "meta" / f"{character_id}_source_provenance.json").read_text(
                    encoding="utf-8"
                )
            )
            revision = provenance["generation"]["prompt_revision"]
            with self.subTest(character_id=character_id):
                self.assertEqual(
                    revision["sha256"],
                    generator.sha256_path(generator.ROOT / revision["path"]),
                )
                self.assertTrue(
                    (root / "meta" / f"{character_id}_generation_brief_v2.md").exists()
                )

    def test_all_active_phase2_briefs_use_native_transparency(self) -> None:
        for entry in character_roster.load_roster(phase="phase2"):
            path = brief_builder.generation_brief_path(entry.character_id)
            document = path.read_text(encoding="utf-8")
            with self.subTest(character_id=entry.character_id):
                self.assertIn('background: "transparent"', document)
                self.assertNotIn("Flat reserved green background", document)
                self.assertNotIn("reserved-green margin", document)


if __name__ == "__main__":
    unittest.main()
