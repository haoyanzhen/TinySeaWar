from __future__ import annotations

from io import BytesIO
import json
from pathlib import Path
from typing import Any, BinaryIO

from PIL import Image


NATIVE_ALPHA_ROUTE = "openai_images_api_native_alpha"
CODEX_BUILTIN_ROUTE = "codex_builtin_imagegen_native_alpha"
LEGACY_CHROMA_ROUTE = "explicit_legacy_chroma_fallback"
CODEX_BUILTIN_MODEL = "codex-account-managed-imagegen"
ALLOWED_GPT_IMAGE_MODELS = {
    "gpt-image-2.5-sunburst",
    "gpt-image-2.5-flare",
}
ALLOWED_TRANSPARENT_FORMATS = {"PNG", "WEBP"}
MIN_TRANSPARENT_CANVAS_RATIO = 0.01
MIN_TRANSPARENT_BORDER_RATIO = 0.50
MIN_VISIBLE_CANVAS_RATIO = 0.005
MIN_CHROMA_BORDER_RATIO = 0.50
EXPECTED_SOURCE_ROLES = {
    "concept_full",
    "ui_sheet",
    "battle_grid",
    "anim_idle",
    "anim_move",
    "anim_attack",
    "anim_hit",
    "anim_firepower",
    "vfx_sheet",
}
LEGACY_NO_PROVENANCE_CHARACTERS = {"fletcher", "cleveland", "baltimore", "wahoo"}
LEGACY_SCHEMA1_PROVENANCE_CHARACTERS = {
    "jervis",
    "tashkent",
    "chapayev",
    "gangut",
    "k_21",
}
FROZEN_LEGACY_PACKAGE_CHARACTERS = (
    LEGACY_NO_PROVENANCE_CHARACTERS | LEGACY_SCHEMA1_PROVENANCE_CHARACTERS
)


def is_frozen_legacy_package(character_id: str, manifest_path: Path) -> bool:
    if character_id not in FROZEN_LEGACY_PACKAGE_CHARACTERS or not manifest_path.exists():
        return False
    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    source_provenance = manifest.get("source_provenance")
    if character_id in LEGACY_NO_PROVENANCE_CHARACTERS:
        return int(manifest.get("schema_version", 1)) < 2 and not isinstance(
            source_provenance, dict
        )
    return (
        int(manifest.get("schema_version", 1)) >= 2
        and isinstance(source_provenance, dict)
        and int(source_provenance.get("schema_version", 1)) < 2
    )


def flattened_pixels(image: Image.Image) -> list[Any]:
    method = getattr(image, "get_flattened_data", None)
    if callable(method):
        return list(method())
    return list(image.getdata())


def image_facts(source: Path | bytes | BinaryIO) -> dict[str, Any]:
    if isinstance(source, bytes):
        image_source: Path | BinaryIO = BytesIO(source)
    else:
        image_source = source
    with Image.open(image_source) as image:
        source_mode = image.mode
        source_format = str(image.format or "").upper()
        has_alpha_channel = "A" in image.getbands()
        rgba = image.convert("RGBA")
        alpha = rgba.getchannel("A")
        alpha_min, alpha_max = alpha.getextrema()
        histogram = alpha.histogram()
        pixel_count = sum(histogram)
        transparent_count = histogram[0]
        visible_count = pixel_count - transparent_count

        border_values: list[int] = []
        if rgba.width and rgba.height:
            border_values.extend(flattened_pixels(alpha.crop((0, 0, rgba.width, 1))))
            if rgba.height > 1:
                border_values.extend(flattened_pixels(alpha.crop((0, rgba.height - 1, rgba.width, rgba.height))))
            if rgba.height > 2:
                border_values.extend(flattened_pixels(alpha.crop((0, 1, 1, rgba.height - 1))))
                if rgba.width > 1:
                    border_values.extend(flattened_pixels(alpha.crop((rgba.width - 1, 1, rgba.width, rgba.height - 1))))
        transparent_border_count = sum(value == 0 for value in border_values)

        return {
            "format": source_format,
            "source_mode": source_mode,
            "width": rgba.width,
            "height": rgba.height,
            "has_alpha_channel": has_alpha_channel,
            "alpha_min": alpha_min,
            "alpha_max": alpha_max,
            "transparent_pixel_count": transparent_count,
            "visible_pixel_count": visible_count,
            "transparent_canvas_ratio": transparent_count / pixel_count if pixel_count else 0.0,
            "visible_canvas_ratio": visible_count / pixel_count if pixel_count else 0.0,
            "transparent_border_ratio": (
                transparent_border_count / len(border_values) if border_values else 0.0
            ),
        }


def native_alpha_issues(facts: dict[str, Any]) -> list[str]:
    issues: list[str] = []
    if facts.get("format") not in ALLOWED_TRANSPARENT_FORMATS:
        issues.append(f"source format is {facts.get('format') or 'unknown'}, expected PNG or WEBP")
    if not facts.get("has_alpha_channel"):
        issues.append("source has no alpha channel")
    if facts.get("alpha_min") != 0:
        issues.append(f"source alpha minimum is {facts.get('alpha_min')}, expected 0")
    if int(facts.get("alpha_max", 0)) <= 0:
        issues.append("source alpha is fully transparent")
    if float(facts.get("transparent_canvas_ratio", 0.0)) < MIN_TRANSPARENT_CANVAS_RATIO:
        issues.append("source has no meaningful transparent canvas area")
    if float(facts.get("visible_canvas_ratio", 0.0)) < MIN_VISIBLE_CANVAS_RATIO:
        issues.append("source has no meaningful visible artwork")
    if float(facts.get("transparent_border_ratio", 0.0)) < MIN_TRANSPARENT_BORDER_RATIO:
        issues.append("source canvas border is not predominantly transparent")
    return issues


def chroma_border_ratio(source: Path | bytes | BinaryIO) -> float:
    if isinstance(source, bytes):
        image_source: Path | BinaryIO = BytesIO(source)
    else:
        image_source = source
    with Image.open(image_source) as image:
        rgba = image.convert("RGBA")
        samples: list[tuple[int, int, int, int]] = []
        samples.extend(flattened_pixels(rgba.crop((0, 0, rgba.width, 1))))
        if rgba.height > 1:
            samples.extend(flattened_pixels(rgba.crop((0, rgba.height - 1, rgba.width, rgba.height))))
        if rgba.height > 2:
            samples.extend(flattened_pixels(rgba.crop((0, 1, 1, rgba.height - 1))))
            if rgba.width > 1:
                samples.extend(flattened_pixels(rgba.crop((rgba.width - 1, 1, rgba.width, rgba.height - 1))))
        chroma = sum(
            1
            for red, green, blue, alpha in samples
            if alpha > 0 and green >= 150 and green > red + 70 and green > blue + 70
        )
        return chroma / len(samples) if samples else 0.0


def legacy_chroma_issues(source: Path | bytes | BinaryIO) -> list[str]:
    ratio = chroma_border_ratio(source)
    if ratio < MIN_CHROMA_BORDER_RATIO:
        return [f"legacy fallback border is not a deterministic chroma key ({ratio:.1%})"]
    return []


def legacy_fallback_authorized(provenance: object) -> bool:
    if not isinstance(provenance, dict):
        return False
    policy = provenance.get("generation_policy")
    if not isinstance(policy, dict):
        return False
    fallback = policy.get("legacy_fallback")
    return (
        isinstance(fallback, dict)
        and fallback.get("authorized") is True
        and fallback.get("activation") == "--allow-legacy-chroma-fallback"
        and bool(str(fallback.get("reason", "")).strip())
        and isinstance(fallback.get("native_failures"), list)
        and bool(fallback["native_failures"])
    )


def strict_source_policy_issues(provenance: object, root: Path) -> list[str]:
    if not isinstance(provenance, dict) or int(provenance.get("schema_version", 1)) < 2:
        return []

    issues: list[str] = []
    policy = provenance.get("generation_policy")
    primary_route = policy.get("primary_route") if isinstance(policy, dict) else None
    if primary_route not in {NATIVE_ALPHA_ROUTE, CODEX_BUILTIN_ROUTE}:
        issues.append("source provenance primary route is not native alpha")
    generation = provenance.get("generation")
    if not isinstance(generation, dict):
        return issues + ["source provenance generation metadata missing"]
    if primary_route == NATIVE_ALPHA_ROUTE:
        if generation.get("requested_model") not in ALLOWED_GPT_IMAGE_MODELS:
            issues.append("source provenance model is not an approved GPT Image 2.5 model")
        if generation.get("actual_model") not in ALLOWED_GPT_IMAGE_MODELS:
            issues.append("source provenance actual model is not verified")
    elif primary_route == CODEX_BUILTIN_ROUTE:
        if generation.get("requested_model") != CODEX_BUILTIN_MODEL:
            issues.append("source provenance does not identify the Codex-managed image model")
        if generation.get("actual_model") != CODEX_BUILTIN_MODEL:
            issues.append("source provenance Codex-managed model marker is inconsistent")
        if generation.get("generation_tool") != "Codex built-in ImageGen":
            issues.append("source provenance tool is not Codex built-in ImageGen")
    if generation.get("output_format") not in ALLOWED_TRANSPARENT_FORMATS:
        issues.append("source provenance output format is not PNG or WEBP")

    fallback_allowed = legacy_fallback_authorized(provenance)
    source_images = provenance.get("source_images")
    if not isinstance(source_images, list) or not source_images:
        return issues + ["source provenance image inventory missing"]
    roles = [str(item.get("role", "")) for item in source_images if isinstance(item, dict)]
    missing_roles = sorted(EXPECTED_SOURCE_ROLES - set(roles))
    unexpected_roles = sorted(set(roles) - EXPECTED_SOURCE_ROLES)
    duplicate_roles = sorted(role for role in set(roles) if role and roles.count(role) > 1)
    if missing_roles:
        issues.append(f"source provenance roles missing: {', '.join(missing_roles)}")
    if unexpected_roles:
        issues.append(f"source provenance roles unsupported: {', '.join(unexpected_roles)}")
    if duplicate_roles:
        issues.append(f"source provenance roles duplicated: {', '.join(duplicate_roles)}")
    for item in source_images:
        if not isinstance(item, dict):
            issues.append("source provenance image entry is not an object")
            continue
        role = str(item.get("role", "?"))
        route = item.get("generation_route")
        source_path = root / str(item.get("path", ""))
        if not source_path.exists():
            continue
        required_fields = [
            "model",
            "quality",
            "size_control",
            "background_control",
            "output_format",
            "endpoint",
            "technical_qa_verdict",
        ]
        if route != CODEX_BUILTIN_ROUTE:
            required_fields.append("request_id")
        for field in required_fields:
            if item.get(field) in (None, ""):
                issues.append(f"source generation metadata missing: {role}:{field}")
        if route != CODEX_BUILTIN_ROUTE and str(item.get("request_id", "")).lower() in {"not-exposed", "unknown"}:
            issues.append(f"source request ID is not verified: {role}")
        if item.get("accepted_source_is_raw_response") is not True:
            issues.append(f"accepted source was not recorded as the raw API response: {role}")
        if item.get("raw_response_sha256") != item.get("sha256"):
            issues.append(f"accepted source hash differs from raw API response: {role}")
        if route == NATIVE_ALPHA_ROUTE and item.get("model") not in ALLOWED_GPT_IMAGE_MODELS:
            issues.append(f"source model is not an approved GPT Image 2.5 model: {role}")
        if route == CODEX_BUILTIN_ROUTE and item.get("model") != CODEX_BUILTIN_MODEL:
            issues.append(f"source model is not recorded as Codex account-managed: {role}")
        if item.get("technical_qa_verdict") != "pass":
            issues.append(f"source technical QA did not pass: {role}")
        if route == NATIVE_ALPHA_ROUTE and item.get("endpoint") not in {"/v1/images/generations", "/v1/images/edits"}:
            issues.append(f"source endpoint is not a verified Images API route: {role}")
        facts = image_facts(source_path)
        recorded_alpha = item.get("alpha")
        if not isinstance(recorded_alpha, dict):
            issues.append(f"source alpha facts missing: {role}")
        else:
            expected_alpha = {
                "has_alpha_channel": facts["has_alpha_channel"],
                "min": facts["alpha_min"],
                "max": facts["alpha_max"],
                "transparent_canvas_ratio": facts["transparent_canvas_ratio"],
                "transparent_border_ratio": facts["transparent_border_ratio"],
            }
            for field, expected in expected_alpha.items():
                if recorded_alpha.get(field) != expected:
                    issues.append(f"source alpha facts mismatch: {role}:{field}")
        if route == NATIVE_ALPHA_ROUTE:
            if item.get("background_control") != "transparent":
                issues.append(f"native-alpha source did not request transparent background: {role}")
            if str(item.get("output_format", "")).upper() not in ALLOWED_TRANSPARENT_FORMATS:
                issues.append(f"native-alpha source format is not PNG or WEBP: {role}")
            issues.extend(f"native-alpha source invalid: {role}: {issue}" for issue in native_alpha_issues(facts))
        elif route == CODEX_BUILTIN_ROUTE:
            if item.get("background_control") != "transparent":
                issues.append(f"Codex built-in source did not request transparent output: {role}")
            if item.get("endpoint") != "codex_builtin_imagegen":
                issues.append(f"Codex built-in source endpoint marker is invalid: {role}")
            if str(item.get("output_format", "")).upper() not in ALLOWED_TRANSPARENT_FORMATS:
                issues.append(f"Codex built-in source format is not PNG or WEBP: {role}")
            issues.extend(
                f"Codex built-in native-alpha source invalid: {role}: {issue}"
                for issue in native_alpha_issues(facts)
            )
        elif route == LEGACY_CHROMA_ROUTE:
            if not fallback_allowed:
                issues.append(f"legacy chroma fallback was not explicitly authorized: {role}")
            if item.get("background_control") != "opaque":
                issues.append(f"legacy chroma source did not request opaque background: {role}")
            issues.extend(f"legacy chroma source invalid: {role}: {issue}" for issue in legacy_chroma_issues(source_path))
        else:
            issues.append(f"source generation route is missing or unsupported: {role}")
    return issues
