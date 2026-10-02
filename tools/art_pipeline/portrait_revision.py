"""Independent, hash-bound portrait revisions; old character packages stay traceable."""
from __future__ import annotations

import argparse
import hashlib
import json
import math
from pathlib import Path
import shutil

from PIL import Image

from generation_contract import CODEX_BUILTIN_ROUTE, image_facts, native_alpha_issues, flattened_pixels

ROOT = Path(__file__).resolve().parents[2]
REVISION = "20261001_unframed_v1"
SIZES = {"ui_portrait": 512, "ui_portrait_small": 128}


def checksum(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def locations(root: Path, character_id: str) -> tuple[Path, Path]:
    if not character_id or any(c not in "abcdefghijklmnopqrstuvwxyz0123456789_" for c in character_id):
        raise ValueError("invalid character id")
    base = root / "assets/characters" / character_id
    return (base / "ui" / f"{character_id}_portrait_{REVISION}.png",
            base / "meta" / f"{character_id}_portrait_revision.json")


def reviewed(review: dict, digest: str) -> bool:
    return (review.get("sha256") == digest and review.get("verdict") == "pass"
            and all(str(review.get(k, "")).strip() for k in ("reviewer", "observation")))


def load_revision(root: Path, character_id: str) -> dict | None:
    source, path = locations(root, character_id)
    if not path.exists():
        return None
    data = json.loads(path.read_text())
    if data.get("schema_version") != 1 or data.get("character_id") != character_id or data.get("revision") != REVISION:
        raise ValueError("portrait revision identity/schema mismatch")
    if (data.get("generation_route") != CODEX_BUILTIN_ROUTE
            or data.get("background_control") != "transparent"
            or not str(data.get("prompt", "")).strip() or not data.get("references")):
        raise ValueError("portrait generation provenance incomplete/mismatched")
    if data.get("source", {}).get("path") != str(source.relative_to(root)) or not source.exists():
        raise ValueError("portrait revision source missing/mismatched")
    digest = checksum(source)
    if data.get("raw_sha256") != digest:
        raise ValueError("portrait source differs from preserved raw generation")
    if data["source"].get("sha256") != digest or not reviewed(data.get("source_review", {}), digest):
        raise ValueError("portrait source changed or visual review pending")
    issues = native_alpha_issues(image_facts(source))
    if issues:
        raise ValueError("portrait native-alpha gate: " + "; ".join(issues))
    for reference in data.get("references", []):
        ref = (root / reference["path"]).resolve()
        ref.relative_to(root.resolve())
        if not ref.exists() or checksum(ref) != reference["sha256"]:
            raise ValueError("portrait identity/style reference changed")
    return data


def normalized_portraits(source: Path) -> dict[str, Image.Image]:
    with Image.open(source) as opened:
        rgba = opened.convert("RGBA")
        box = rgba.getchannel("A").getbbox()
        if not box:
            raise ValueError("empty portrait")
        bust = rgba.crop(box)
    # Leave extra room for Lanczos ringing, including at 128px. Resize premultiplied
    # alpha so transparent RGB cannot introduce pale/dark fringes.
    scale = min(400 / bust.width, 400 / bust.height)
    dims = (max(1, round(bust.width * scale)), max(1, round(bust.height * scale)))
    bust = bust.convert("RGBa").resize(dims, Image.Resampling.LANCZOS).convert("RGBA")
    regular = Image.new("RGBA", (512, 512))
    regular.paste(bust, ((512 - bust.width) // 2, (512 - bust.height) // 2))
    small = regular.convert("RGBa").resize((128, 128), Image.Resampling.LANCZOS).convert("RGBA")
    return {"ui_portrait": regular, "ui_portrait_small": small}


def asset_entry(root: Path, path: Path, image: Image.Image, source: Path) -> dict:
    alpha = image.getchannel("A")
    box = alpha.getbbox()
    weights = flattened_pixels(alpha)
    total = sum(weights)
    cx = sum((i % image.width + .5) * a for i, a in enumerate(weights)) / total
    cy = sum((i // image.width + .5) * a for i, a in enumerate(weights)) / total
    margins = dict(zip(("left", "top", "right", "bottom"),
                       (box[0], box[1], image.width-box[2], image.height-box[3])))
    with Image.open(source) as original:
        source_box = list(original.getchannel("A").getbbox())
        source_size = list(original.size)
    crop = {"original_crop_hint": [0, 0, *source_size], "final_crop_box": source_box,
            "auto_crop_method": "independent_portrait_alpha_bbox_square_fit",
            "selected_component_samples": [{"bbox": source_box}],
            "output_edge_margins": margins, "cleanup_tags": []}
    return {"role": path.stem.split("_ui_", 1)[-1] if "_ui_" in path.stem else path.stem,
            "path": str(path.relative_to(root)), "file": str(path.relative_to(root)),
            "source": str(source.relative_to(root)), "sha256": checksum(path),
            "size": list(image.size), "mode": "RGBA", "alpha_bbox": list(box),
            "alpha_pixel_count": sum(a > 0 for a in weights), "edge_margins": margins,
            "output_padding": margins, "alpha_centroid": [cx, cy],
            "centroid_offset_normalized": {"x": cx/image.width-.5, "y": cy/image.height-.5},
            "component_tags": ["ui", "portrait_revision"], "crop": crop,
            "source_crop_qa": crop}


def apply_revision(root: Path, character_id: str, manifest: dict) -> bool:
    data = load_revision(root, character_id)
    if data is None:
        return False
    source, revision_path = locations(root, character_id)
    images = normalized_portraits(source)
    base = root / "assets/characters" / character_id / "processed/ui"
    base.mkdir(parents=True, exist_ok=True)
    outputs = []
    for semantic, image in images.items():
        path = base / f"{character_id}_{semantic}.png"
        temporary = path.with_suffix(".png.tmp")
        image.save(temporary, format="PNG")
        temporary.replace(path)
        entry = asset_entry(root, path, image, source)
        entry["role"] = semantic
        outputs.append(entry)
    key = "outputs" if "outputs" in manifest else "components"
    replaced = {entry["path"] for entry in outputs}
    manifest[key] = [entry for entry in manifest.get(key, [])
                     if entry.get("path", entry.get("file")) not in replaced] + outputs
    manifest["portrait_revision"] = {"path": str(revision_path.relative_to(root)),
                                     "sha256": checksum(revision_path)}
    return True


def validate_revision(root: Path, character_id: str) -> list[str]:
    try:
        data = load_revision(root, character_id)
        if data is None:
            return []
        source, _ = locations(root, character_id)
        expected = normalized_portraits(source)
        issues = []
        manifest = {}
        manifest_path = root / "assets/characters" / character_id / "processed/config" / f"{character_id}_postprocess_manifest.json"
        if manifest_path.exists():
            manifest = json.loads(manifest_path.read_text())
            _, revision_path = locations(root, character_id)
            expected_ref = {"path": str(revision_path.relative_to(root)), "sha256": checksum(revision_path)}
            if manifest.get("portrait_revision") != expected_ref:
                issues.append("manifest portrait revision reference missing/stale")
        else:
            issues.append("portrait output manifest missing")
        for semantic, size in SIZES.items():
            path = root / "assets/characters" / character_id / "processed/ui" / f"{character_id}_{semantic}.png"
            with Image.open(path) as image:
                if image.mode != "RGBA" or image.size != (size, size):
                    issues.append(f"{semantic}: expected RGBA {size} square")
                    continue
                if image.tobytes() != expected[semantic].tobytes():
                    issues.append(f"{semantic}: not derived from accepted portrait source")
                box = image.getchannel("A").getbbox()
                if not box or min(box[0], box[1], size-box[2], size-box[3]) < math.ceil(size*.08):
                    issues.append(f"{semantic}: less than 8% transparent margin")
            digest = checksum(path)
            filename = str(path.relative_to(root))
            entries = [entry for entry in manifest.get("outputs", manifest.get("components", []))
                       if entry.get("path", entry.get("file")) == filename]
            if (len(entries) != 1 or entries[0].get("sha256") != digest
                    or entries[0].get("source") != str(source.relative_to(root))):
                issues.append(f"{semantic}: manifest output/source hash missing/stale")
            if not reviewed(data.get("output_reviews", {}).get(semantic, {}), digest):
                issues.append(f"{semantic}: output visual review pending/stale")
        return issues
    except (ValueError, OSError, KeyError, TypeError) as exc:
        return [str(exc)]


def register(root: Path, character_id: str, raw: Path, prompt: str, references: list[Path], observation: str) -> None:
    issues = native_alpha_issues(image_facts(raw))
    if issues:
        raise ValueError("; ".join(issues))
    source, path = locations(root, character_id)
    source.parent.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(raw, source)
    review = {"sha256": checksum(source), "verdict": "pass", "reviewer": "Codex visual inspection",
              "observation": observation}
    data = {"schema_version": 1, "character_id": character_id, "revision": REVISION,
            "scope": "Portraits only; does not migrate or approve the full character package",
            "generation_route": CODEX_BUILTIN_ROUTE, "model": "account-managed/not-exposed",
            "request_id": "not-exposed", "background_control": "transparent",
            "prompt": prompt, "raw_output_path": str(raw), "raw_sha256": checksum(raw),
            "references": [{"path": str(p.relative_to(root)), "sha256": checksum(p)} for p in references],
            "source": {"path": str(source.relative_to(root)), "sha256": checksum(source),
                       "alpha_facts": image_facts(source)}, "source_review": review, "output_reviews": {}}
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(data, ensure_ascii=False, indent=2)+"\n")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("character_id")
    parser.add_argument("--register", type=Path)
    parser.add_argument("--prompt-file", type=Path)
    parser.add_argument("--reference", action="append", type=Path, default=[])
    parser.add_argument("--source-observation")
    parser.add_argument("--review-outputs", help="Record observations after inspecting the actual 512/128px outputs")
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    if args.register:
        if not args.prompt_file or not args.reference or not args.source_observation:
            parser.error("register requires prompt, references and actual visual observation")
        register(ROOT, args.character_id, args.register, args.prompt_file.read_text(), args.reference, args.source_observation)
    if args.check:
        issues = validate_revision(ROOT, args.character_id)
        print(json.dumps({"character_id": args.character_id, "issues": issues}, ensure_ascii=False))
        raise SystemExit(bool(issues))
    _, revision_path = locations(ROOT, args.character_id)
    config = ROOT / "assets/characters" / args.character_id / "processed/config"
    manifest_path = config / f"{args.character_id}_postprocess_manifest.json"
    manifest = json.loads(manifest_path.read_text())
    if args.review_outputs:
        data = load_revision(ROOT, args.character_id)
        for semantic in SIZES:
            output = config.parent / "ui" / f"{args.character_id}_{semantic}.png"
            data["output_reviews"][semantic] = {"sha256": checksum(output), "verdict": "pass",
                "reviewer": "Codex visual inspection", "observation": args.review_outputs}
        revision_path.write_text(json.dumps(data, ensure_ascii=False, indent=2)+"\n")
    apply_revision(ROOT, args.character_id, manifest)
    manifest_path.write_text(json.dumps(manifest, ensure_ascii=False, indent=2)+"\n")
    from delivery_review import write_review
    write_review(ROOT, args.character_id, manifest)
    print(f"portrait revision applied: {args.character_id}")


if __name__ == "__main__":
    main()
