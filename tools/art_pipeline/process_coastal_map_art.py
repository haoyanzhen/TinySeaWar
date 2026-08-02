#!/usr/bin/env python3
"""Prepare, finalize, validate, and review 16:9 coastal map artwork.

The reviewed terrain templates use a 1024 x 1024 local coordinate system. The
source-art preparation contract applies the equivalent world transform
```
world_x = 3072 + (template_x - 512) * 4.86
world_y = 1728 + (template_y - 512) * 3.0375
```
when preparing the delivered artwork. Source masters are 3840 x 2160 and
runtime textures are 1920 x 1080. Runtime placement then uses the separately
reviewed non-uniform display scale (2.6, 3.2).
"""

from __future__ import annotations

import argparse
import json
import math
from pathlib import Path

from PIL import Image, ImageChops, ImageDraw, ImageFilter, ImageFont


ROOT = Path(__file__).resolve().parents[2]
LAND_ROOT = ROOT / "assets/environment/land"
LEGACY_SIZE = (1024, 1024)
SOURCE_SIZE = (3840, 2160)
RUNTIME_SIZE = (1920, 1080)
MAP_SIZE = (6144.0, 3456.0)
LEGACY_WORLD_SCALE = (4.86, 3.0375)
SOURCE_PIXEL_SCALE = (
	LEGACY_WORLD_SCALE[0] / (MAP_SIZE[0] / SOURCE_SIZE[0]),
	LEGACY_WORLD_SCALE[1] / (MAP_SIZE[1] / SOURCE_SIZE[1]),
)
LANCZOS = getattr(Image, "Resampling", Image).LANCZOS
BICUBIC = getattr(Image, "Resampling", Image).BICUBIC

LAND_IDS = [
	"broken_atoll",
	"central_sandbar",
	"crescent_bay",
	"double_island_long_channel",
	"dual_channel_reef_line",
	"harbor_mouth",
	"long_archipelago",
	"offset_large_island",
	"ring_lagoon",
	"scattered_islands",
]
RING_LAGOON_GAP_LEFT = 1640
RING_LAGOON_GAP_RIGHT = 2200
RING_LAGOON_SECONDARY_GAP_WIDTH = 400
RING_LAGOON_NORTHWEST_PASSAGE = ((500, -100), (1500, 760))
RING_LAGOON_NORTHEAST_PASSAGE = ((3340, -100), (2340, 760))


def _selected_land_ids(land_id: str) -> list[str]:
	return [land_id] if land_id else LAND_IDS


def _font(size: int) -> ImageFont.ImageFont:
	for path in (
		"/System/Library/Fonts/PingFang.ttc",
		"/System/Library/Fonts/Supplemental/Arial Unicode.ttf",
	):
		if Path(path).is_file():
			return ImageFont.truetype(path, size)
	return ImageFont.load_default()


def _transform_legacy(image: Image.Image, size: tuple[int, int], scale: tuple[float, float]) -> Image.Image:
	"""Place a legacy square image into a centered 16:9 canvas."""
	image = image.convert("RGBA")
	target_width = max(1, round(LEGACY_SIZE[0] * scale[0]))
	target_height = max(1, round(LEGACY_SIZE[1] * scale[1]))
	resized = image.resize((target_width, target_height), LANCZOS)
	canvas = Image.new("RGBA", size, (0, 0, 0, 0))
	position = ((size[0] - target_width) // 2, (size[1] - target_height) // 2)
	canvas.alpha_composite(resized, position)
	return canvas


def _reference_paths(land_id: str) -> tuple[Path, Path]:
	reference_root = LAND_ROOT / "source/reference_16x9"
	return (
		reference_root / ("land_%s_reference.png" % land_id),
		reference_root / ("land_%s_mask.png" % land_id),
	)


def _corridor_polygon(
	start: tuple[float, float],
	end: tuple[float, float],
	width: float,
) -> list[tuple[float, float]]:
	delta_x = end[0] - start[0]
	delta_y = end[1] - start[1]
	length = math.hypot(delta_x, delta_y)
	if length <= 1e-9:
		raise ValueError("corridor endpoints must be distinct")
	offset_x = -delta_y / length * width * 0.5
	offset_y = delta_x / length * width * 0.5
	return [
		(start[0] + offset_x, start[1] + offset_y),
		(end[0] + offset_x, end[1] + offset_y),
		(end[0] - offset_x, end[1] - offset_y),
		(start[0] - offset_x, start[1] - offset_y),
	]


def _irregular_corridor_polygon(
	start: tuple[float, float],
	end: tuple[float, float],
	width: float,
) -> list[tuple[float, float]]:
	"""Add small deterministic shoreline variation while preserving corridor width."""
	delta_x = end[0] - start[0]
	delta_y = end[1] - start[1]
	length = math.hypot(delta_x, delta_y)
	if length <= 1e-9:
		raise ValueError("corridor endpoints must be distinct")
	normal_x = -delta_y / length
	normal_y = delta_x / length
	steps = (0.0, 0.10, 0.20, 0.30, 0.40, 0.50, 0.60, 0.70, 0.80, 0.90, 1.0)
	left_variation = (0.0, 22.0, -16.0, 29.0, -24.0, 14.0, -28.0, 25.0, -18.0, 20.0, 0.0)
	right_variation = (0.0, -18.0, 25.0, -28.0, 17.0, -23.0, 29.0, -15.0, 22.0, -19.0, 0.0)

	def side_points(sign: float, variation: tuple[float, ...]) -> list[tuple[float, float]]:
		points: list[tuple[float, float]] = []
		for t, jitter in zip(steps, variation):
			center_x = start[0] + delta_x * t
			center_y = start[1] + delta_y * t
			offset = sign * (width * 0.5 + jitter)
			points.append((center_x + normal_x * offset, center_y + normal_y * offset))
		return points

	return side_points(1.0, left_variation) + list(
		reversed(side_points(-1.0, right_variation))
	)


def _carve_ring_lagoon_primary_passages(image: Image.Image) -> Image.Image:
	"""Open the reviewed north/south lagoon entrances without moving the ring."""
	image = image.convert("RGBA")
	alpha = image.getchannel("A")
	carve = Image.new("L", SOURCE_SIZE, 0)
	draw = ImageDraw.Draw(carve)
	draw.polygon([
		(RING_LAGOON_GAP_LEFT, -16),
		(RING_LAGOON_GAP_RIGHT, -16),
		(RING_LAGOON_GAP_RIGHT - 20, 900),
		(RING_LAGOON_GAP_LEFT + 20, 900),
	], fill=255)
	draw.polygon([
		(RING_LAGOON_GAP_LEFT + 20, 1260),
		(RING_LAGOON_GAP_RIGHT - 20, 1260),
		(RING_LAGOON_GAP_RIGHT, SOURCE_SIZE[1] + 16),
		(RING_LAGOON_GAP_LEFT, SOURCE_SIZE[1] + 16),
	], fill=255)
	carve = carve.filter(ImageFilter.GaussianBlur(2.0))
	image.putalpha(ImageChops.subtract(alpha, carve))
	return image


def _carve_ring_lagoon_passages(image: Image.Image) -> Image.Image:
	"""Keep the four reviewed openings and add symmetric northwest/northeast entries."""
	image = _carve_ring_lagoon_primary_passages(image)
	alpha = image.getchannel("A")
	carve = Image.new("L", SOURCE_SIZE, 0)
	draw = ImageDraw.Draw(carve)
	for start, end in (
		RING_LAGOON_NORTHWEST_PASSAGE,
		RING_LAGOON_NORTHEAST_PASSAGE,
	):
		draw.polygon(
			_irregular_corridor_polygon(start, end, RING_LAGOON_SECONDARY_GAP_WIDTH),
			fill=255,
		)
	carve = carve.filter(ImageFilter.GaussianBlur(2.0))
	image.putalpha(ImageChops.subtract(alpha, carve))
	return image


def prepare_references(land_ids: list[str], ring_primary_only: bool = False) -> None:
	reference_root = LAND_ROOT / "source/reference_16x9"
	reference_root.mkdir(parents=True, exist_ok=True)
	for land_id in land_ids:
		legacy_path = LAND_ROOT / ("land_%s.png" % land_id)
		if not legacy_path.is_file():
			raise FileNotFoundError(legacy_path)
		if land_id == "ring_lagoon":
			if ring_primary_only:
				transformed = _carve_ring_lagoon_primary_passages(
					_transform_legacy(Image.open(legacy_path), SOURCE_SIZE, SOURCE_PIXEL_SCALE)
				)
			else:
				current_source = LAND_ROOT / "source/land_ring_lagoon_source.png"
				transformed = (
					Image.open(current_source).convert("RGBA")
					if current_source.is_file()
					else _transform_legacy(Image.open(legacy_path), SOURCE_SIZE, SOURCE_PIXEL_SCALE)
				)
				transformed = _carve_ring_lagoon_passages(transformed)
		else:
			transformed = _transform_legacy(Image.open(legacy_path), SOURCE_SIZE, SOURCE_PIXEL_SCALE)
		mask = transformed.getchannel("A")
		background = Image.new("RGBA", SOURCE_SIZE, (255, 0, 255, 255))
		background.alpha_composite(transformed)
		reference_path, mask_path = _reference_paths(land_id)
		background.convert("RGB").save(reference_path, quality=96)
		mask.save(mask_path)
		print("prepared %s" % reference_path.relative_to(ROOT))


def _cover(image: Image.Image, size: tuple[int, int]) -> Image.Image:
	image = image.convert("RGBA")
	scale = max(size[0] / image.width, size[1] / image.height)
	resized = image.resize((math.ceil(image.width * scale), math.ceil(image.height * scale)), LANCZOS)
	left = (resized.width - size[0]) // 2
	top = (resized.height - size[1]) // 2
	return resized.crop((left, top, left + size[0], top + size[1]))


def _magenta_subject_alpha(image: Image.Image) -> Image.Image:
	"""Build a soft subject matte for a #ff00ff image-generation background."""
	r, g, b = image.convert("RGB").split()
	pixels = []
	channel_values = [
		channel.get_flattened_data() if hasattr(channel, "get_flattened_data") else channel.getdata()
		for channel in (r, g, b)
	]
	for rv, gv, bv in zip(*channel_values):
		magenta_distance = math.sqrt((255 - rv) ** 2 + gv ** 2 + (255 - bv) ** 2)
		alpha = int(max(0.0, min(255.0, (magenta_distance - 18.0) * 4.6)))
		pixels.append(alpha)
	result = Image.new("L", image.size)
	result.putdata(pixels)
	return result


def _despill_magenta(image: Image.Image) -> Image.Image:
	"""Turn residual magenta edge spill into the cool blue shoreline palette."""
	r, g, b = image.convert("RGB").split()
	spill = ImageChops.darker(ImageChops.subtract(r, g), ImageChops.subtract(b, g))
	spill = spill.point(lambda value: 0 if value <= 3 else value - 3)
	r = ImageChops.subtract(r, spill.point(lambda value: round(value * 0.90)))
	g = ImageChops.add(g, spill.point(lambda value: round(value * 0.80)))
	return Image.merge("RGB", (r, g, b))


def finalize(raw_dir: Path, land_ids: list[str], ring_primary_only: bool = False) -> None:
	source_root = LAND_ROOT / "source"
	source_root.mkdir(parents=True, exist_ok=True)
	for land_id in land_ids:
		raw_path = raw_dir / ("land_%s_generated.png" % land_id)
		if not raw_path.is_file():
			raise FileNotFoundError(raw_path)
		raw = _cover(Image.open(raw_path), SOURCE_SIZE)
		_, mask_path = _reference_paths(land_id)
		legacy_path = LAND_ROOT / ("land_%s.png" % land_id)
		# The magenta-backed reference exists only to guide image generation.
		# Reuse the original transparent artwork for fallback edge RGB so the
		# reviewed antialiasing cannot carry chroma-key color into the export.
		if land_id == "ring_lagoon":
			if ring_primary_only:
				reference_image = _carve_ring_lagoon_primary_passages(
					_transform_legacy(Image.open(legacy_path), SOURCE_SIZE, SOURCE_PIXEL_SCALE)
				)
			else:
				current_source = LAND_ROOT / "source/land_ring_lagoon_source.png"
				reference_image = (
					Image.open(current_source).convert("RGBA")
					if current_source.is_file()
					else _transform_legacy(Image.open(legacy_path), SOURCE_SIZE, SOURCE_PIXEL_SCALE)
				)
				reference_image = _carve_ring_lagoon_passages(reference_image)
		else:
			reference_image = _transform_legacy(
				Image.open(legacy_path), SOURCE_SIZE, SOURCE_PIXEL_SCALE
			)
		reference_rgb = reference_image.convert("RGB")
		exact_mask = Image.open(mask_path).convert("L")
		raw_alpha = raw.getchannel("A")
		subject_alpha = raw_alpha if raw_alpha.getextrema()[0] == 0 else _magenta_subject_alpha(raw)
		# Keep the generated repaint in solid interior pixels. The reviewed
		# reference owns the antialiased coastline, avoiding any chroma-key
		# fringe while retaining the exact approved silhouette.
		subject_alpha = subject_alpha.point(
			lambda value: 0 if value <= 216 else min(255, round((value - 216) * 255 / 39))
		)
		generated_subject = _despill_magenta(
			Image.composite(raw.convert("RGB"), reference_rgb, subject_alpha)
		)
		source_master = generated_subject.convert("RGBA")
		source_master.putalpha(exact_mask)
		source_path = source_root / ("land_%s_source.png" % land_id)
		runtime_path = LAND_ROOT / ("land_%s_16x9_runtime.png" % land_id)
		source_master.save(source_path)
		source_master.resize(RUNTIME_SIZE, LANCZOS).save(runtime_path)
		print("finalized %s and %s" % (source_path.relative_to(ROOT), runtime_path.relative_to(ROOT)))


def build_contact_sheet(output: Path) -> None:
	cell = (768, 486)
	padding = 28
	title_height = 64
	canvas = Image.new("RGB", (cell[0] * 2 + padding * 3, (cell[1] + title_height) * 5 + padding * 6), (12, 47, 61))
	draw = ImageDraw.Draw(canvas)
	for index, land_id in enumerate(LAND_IDS):
		column = index % 2
		row = index // 2
		left = padding + column * (cell[0] + padding)
		top = padding + row * (cell[1] + title_height + padding)
		runtime_path = LAND_ROOT / ("land_%s_16x9_runtime.png" % land_id)
		image = Image.open(runtime_path).convert("RGBA")
		background = Image.new("RGBA", RUNTIME_SIZE, (23, 91, 105, 255))
		background.alpha_composite(image)
		preview = background.convert("RGB").resize(cell, LANCZOS)
		canvas.paste(preview, (left, top))
		draw.rectangle((left, top, left + cell[0], top + cell[1]), outline=(106, 207, 208), width=2)
		draw.text((left + 8, top + cell[1] + 12), land_id, font=_font(28), fill=(232, 246, 241))
		draw.text((left + 8, top + cell[1] + 43), "6144×3456 · center 3072,1728 · display scale 2.6×3.2", font=_font(16), fill=(141, 192, 194))
	output.parent.mkdir(parents=True, exist_ok=True)
	canvas.save(output)
	print("contact sheet: %s" % output)


def validate(land_ids: list[str]) -> None:
	errors: list[str] = []
	for land_id in land_ids:
		source_path = LAND_ROOT / ("source/land_%s_source.png" % land_id)
		runtime_path = LAND_ROOT / ("land_%s_16x9_runtime.png" % land_id)
		for path, expected_size in ((source_path, SOURCE_SIZE), (runtime_path, RUNTIME_SIZE)):
			if not path.is_file():
				errors.append("missing %s" % path.relative_to(ROOT))
				continue
			image = Image.open(path)
			if image.size != expected_size:
				errors.append("%s has size %s, expected %s" % (path.relative_to(ROOT), image.size, expected_size))
			if image.mode != "RGBA":
				errors.append("%s is %s, expected RGBA" % (path.relative_to(ROOT), image.mode))
			elif image.getchannel("A").getextrema() != (0, 255):
				errors.append("%s does not contain both transparent and opaque pixels" % path.relative_to(ROOT))
		reference_path, mask_path = _reference_paths(land_id)
		if runtime_path.is_file() and mask_path.is_file():
			expected_mask = Image.open(mask_path).convert("L").resize(RUNTIME_SIZE, LANCZOS)
			actual_mask = Image.open(runtime_path).convert("RGBA").getchannel("A")
			difference = ImageChops.difference(expected_mask, actual_mask).getbbox()
			if difference is not None:
				errors.append("%s alpha does not match the reviewed transformed mask" % runtime_path.relative_to(ROOT))
	if errors:
		raise ValueError("\n".join(errors))
	print("PASS: %d coastal source masters and runtime textures" % (len(land_ids) * 2))


def main() -> int:
	parser = argparse.ArgumentParser()
	subparsers = parser.add_subparsers(dest="command", required=True)
	prepare_parser = subparsers.add_parser("prepare-references")
	prepare_parser.add_argument("--land-id", choices=LAND_IDS, default="")
	prepare_parser.add_argument("--ring-primary-only", action="store_true")
	finalize_parser = subparsers.add_parser("finalize")
	finalize_parser.add_argument("--raw-dir", required=True)
	finalize_parser.add_argument("--land-id", choices=LAND_IDS, default="")
	finalize_parser.add_argument("--ring-primary-only", action="store_true")
	contact_parser = subparsers.add_parser("contact-sheet")
	contact_parser.add_argument("--out", default="assets/environment/qa/coastal_maps_16x9_contact_sheet.png")
	validate_parser = subparsers.add_parser("validate")
	validate_parser.add_argument("--land-id", choices=LAND_IDS, default="")
	args = parser.parse_args()
	try:
		if args.command == "prepare-references":
			prepare_references(
				_selected_land_ids(args.land_id),
				bool(args.ring_primary_only),
			)
		elif args.command == "finalize":
			finalize(
				Path(args.raw_dir),
				_selected_land_ids(args.land_id),
				bool(args.ring_primary_only),
			)
		elif args.command == "contact-sheet":
			build_contact_sheet(ROOT / args.out)
		elif args.command == "validate":
			validate(_selected_land_ids(args.land_id))
		return 0
	except (OSError, ValueError) as error:
		print("coastal art pipeline failed: %s" % error)
		return 1


if __name__ == "__main__":
	raise SystemExit(main())
