#!/usr/bin/env python3
"""Build deterministic scene-combat terrain, facility, UI, and VFX assets."""

from __future__ import annotations

import json
import math
import random
import shutil
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter

ROOT = Path(__file__).resolve().parents[2]
SCALE = 4
SEED = 20260627
LANCZOS = getattr(Image, "Resampling", Image).LANCZOS


def _canvas(size: int) -> tuple[Image.Image, ImageDraw.ImageDraw]:
	image = Image.new("RGBA", (size * SCALE, size * SCALE), (0, 0, 0, 0))
	return image, ImageDraw.Draw(image)


def _save(image: Image.Image, path: Path, size: int | tuple[int, int]) -> None:
	path.parent.mkdir(parents=True, exist_ok=True)
	target_size = (size, size) if isinstance(size, int) else size
	image.resize(target_size, LANCZOS).save(path)


def _poly(draw: ImageDraw.ImageDraw, points, fill, outline=None, width=1):
	points_scaled = [(int(x * SCALE), int(y * SCALE)) for x, y in points]
	draw.polygon(points_scaled, fill=fill)
	if outline:
		draw.line(points_scaled + [points_scaled[0]], fill=outline, width=width * SCALE, joint="curve")


def _line(draw: ImageDraw.ImageDraw, points, fill, width=1):
	draw.line([(int(x * SCALE), int(y * SCALE)) for x, y in points], fill=fill, width=width * SCALE, joint="curve")


def _ellipse(draw: ImageDraw.ImageDraw, box, fill, outline=None, width=1):
	draw.ellipse(tuple(int(value * SCALE) for value in box), fill=fill, outline=outline, width=width * SCALE)


def _rect(draw: ImageDraw.ImageDraw, box, fill, outline=None, width=1, radius=0):
	box_scaled = tuple(int(value * SCALE) for value in box)
	if radius:
		draw.rounded_rectangle(box_scaled, radius=radius * SCALE, fill=fill, outline=outline, width=width * SCALE)
	else:
		draw.rectangle(box_scaled, fill=fill, outline=outline, width=width * SCALE)


def build_terrain_assets() -> list[dict]:
	rng = random.Random(SEED)
	dir_path = ROOT / "assets/environment/terrain"
	assets = []

	image, draw = _canvas(512)
	_rect(draw, [0, 0, 512, 512], (61, 182, 187, 82))
	for _ in range(110):
		x, y = rng.randrange(512), rng.randrange(512)
		length = rng.randrange(16, 74)
		color = rng.choice([(112, 225, 224, 24), (202, 246, 229, 20), (48, 167, 187, 18)])
		_line(draw, [(x, y), ((x + length) % 560 - 24, y + rng.randrange(-7, 8))], color, rng.choice([1, 1, 2]))
	shallow_path = dir_path / "terrain_shallow_water_fill_tile.png"
	_save(image, shallow_path, 512)
	assets.append(_asset("shallow_water_fill", shallow_path, 512))

	image, draw = _canvas(256)
	for radius in range(118, 18, -3):
		alpha = int(70 * (1.0 - radius / 118.0) ** 1.8)
		_ellipse(draw, [128 - radius, 128 - radius, 128 + radius, 128 + radius], (190, 245, 231, alpha))
	edge_path = dir_path / "terrain_shallow_water_edge_mask.png"
	_save(image.filter(ImageFilter.GaussianBlur(3 * SCALE)), edge_path, 256)
	assets.append(_asset("shallow_water_edge_mask", edge_path, 256))

	for semantic, filename, palette, mode in [
		("reef_sandbar_overlay", "terrain_reef_sandbar_overlay.png", [(215, 205, 146, 105), (83, 139, 124, 90), (237, 228, 180, 75)], "specks"),
		("navigation_channel_overlay", "terrain_navigation_channel_overlay.png", [(91, 190, 202, 34), (183, 234, 224, 28)], "flow"),
		("shore_wet_rock_overlay", "terrain_shore_wet_rock_overlay.png", [(51, 77, 77, 130), (84, 107, 96, 105)], "specks"),
		("shore_sediment_overlay", "terrain_shore_sediment_overlay.png", [(194, 168, 112, 75), (231, 212, 161, 55)], "flow"),
		("shore_breaker_overlay", "terrain_shore_breaker_overlay.png", [(231, 253, 245, 115), (139, 226, 224, 70)], "flow"),
	]:
		image, draw = _canvas(512)
		if mode == "specks":
			for _ in range(150):
				x, y = rng.randrange(512), rng.randrange(512)
				r = rng.randrange(2, 12)
				_ellipse(draw, [x - r * 1.6, y - r, x + r * 1.6, y + r], rng.choice(palette))
		else:
			for _ in range(75):
				x, y = rng.randrange(-40, 500), rng.randrange(512)
				length = rng.randrange(30, 120)
				_line(draw, [(x, y), (x + length * 0.5, y - 5), (x + length, y + 1)], rng.choice(palette), rng.randrange(1, 4))
		path = dir_path / filename
		_save(image.filter(ImageFilter.GaussianBlur(SCALE // 2)), path, 512)
		assets.append(_asset(semantic, path, 512))

	runtime_land = ROOT / "assets/environment/land/land_harbor_mouth_runtime.png"
	shutil.copyfile(ROOT / "assets/environment/land/land_harbor_mouth.png", runtime_land)
	assets.append(_asset("land_harbor_mouth_runtime", runtime_land, 1024))
	return assets


def build_environment_zone_assets() -> list[dict]:
	rng = random.Random(SEED + 1)
	dir_path = ROOT / "assets/environment/weather/zones"
	weather_master_dir = ROOT / "assets/environment/weather"
	rain_master_paths = [
		weather_master_dir / "ocean_weather_storm_shadow_master.png",
		weather_master_dir / "ocean_weather_rain_lines_master.png",
		weather_master_dir / "ocean_weather_rain_ripples_master.png",
	]
	for master_path in rain_master_paths:
		if not master_path.is_file():
			raise FileNotFoundError("Required weather master is missing: %s" % master_path)
	storm_gray = Image.open(rain_master_paths[0]).convert("L").resize((512, 512), LANCZOS)
	rain_gray = Image.open(rain_master_paths[1]).convert("L").resize((512, 512), LANCZOS)
	ripple_gray = Image.open(rain_master_paths[2]).convert("L").resize((512, 512), LANCZOS)
	storm_alpha = storm_gray.point(lambda value: min(155, max(0, int((value - 28) * 1.1))))
	rain_alpha = rain_gray.point(lambda value: min(205, max(0, int((value - 18) * 2.0))))
	ripple_alpha = ripple_gray.point(lambda value: min(165, max(0, int((value - 34) * 6.0))))
	storm_edge_alpha = storm_gray.filter(ImageFilter.GaussianBlur(4.0)).point(
		lambda value: min(105, max(0, int((value - 38) * 0.85)))
	)
	specs = [
		("sea_fog_mask", "environment_sea_fog_mask.png", "cloud", (221, 238, 237, 135)),
		("sea_fog_edge_mask", "environment_sea_fog_edge_mask.png", "ring", (211, 236, 235, 105)),
		("sea_fog_detail_mask", "environment_sea_fog_detail_mask.png", "foam", (223, 242, 239, 54)),
		("rain_squall_mask", "environment_rain_squall_mask.png", "rain", (52, 81, 92, 115)),
		("rain_squall_edge_mask", "environment_rain_squall_edge_mask.png", "ring", (71, 105, 117, 105)),
		("high_sea_foam_mask", "environment_high_sea_foam_mask.png", "foam", (222, 250, 243, 110)),
		("lee_water_mask", "environment_lee_water_mask.png", "flow", (91, 182, 189, 65)),
		("moonlit_lane_mask", "environment_moonlit_lane_mask.png", "lane", (205, 229, 223, 92)),
		("active_illumination_mask", "environment_active_illumination_mask.png", "radial", (224, 240, 215, 115)),
		("strong_current_streak_tile", "environment_strong_current_streak_tile.png", "flow", (130, 217, 213, 82)),
	]
	assets = []
	for semantic, filename, mode, color in specs:
		if mode == "rain":
			image = Image.new("RGBA", (512, 512), (0, 0, 0, 0))
			storm_layer = Image.new("RGBA", image.size, (38, 61, 73, 0))
			storm_layer.putalpha(storm_alpha)
			image.alpha_composite(storm_layer)
			ripple_layer = Image.new("RGBA", image.size, (112, 173, 178, 0))
			ripple_layer.putalpha(ripple_alpha)
			image.alpha_composite(ripple_layer)
			rain_layer = Image.new("RGBA", image.size, (161, 202, 207, 0))
			rain_layer.putalpha(rain_alpha)
			image.alpha_composite(rain_layer)
		elif semantic == "rain_squall_edge_mask":
			image = Image.new("RGBA", (512, 512), (0, 0, 0, 0))
			edge_layer = Image.new("RGBA", image.size, (71, 105, 117, 0))
			edge_layer.putalpha(storm_edge_alpha)
			image.alpha_composite(edge_layer)
			ripple_layer = Image.new("RGBA", image.size, (129, 185, 187, 0))
			ripple_layer.putalpha(ripple_alpha.point(lambda value: int(value * 0.38)))
			image.alpha_composite(ripple_layer)
		else:
			image, draw = _canvas(512)
		if mode == "cloud":
			for _ in range(36):
				x, y = rng.randrange(30, 482), rng.randrange(30, 482)
				rx, ry = rng.randrange(45, 135), rng.randrange(30, 90)
				_ellipse(draw, [x-rx, y-ry, x+rx, y+ry], color)
			image = image.filter(ImageFilter.GaussianBlur(18 * SCALE))
		elif mode == "ring" and semantic != "rain_squall_edge_mask":
			_ellipse(draw, [48, 58, 464, 454], (0, 0, 0, 0), color, 12)
			image = image.filter(ImageFilter.GaussianBlur(8 * SCALE))
		elif mode == "foam":
			for _ in range(90):
				x, y = rng.randrange(-40, 500), rng.randrange(512)
				_line(draw, [(x, y), (x + 32, y - 8), (x + 74, y + 2)], color, rng.choice([1, 2, 3]))
		elif mode == "lane":
			_poly(draw, [(150, 0), (365, 0), (425, 512), (85, 512)], color)
			image = image.filter(ImageFilter.GaussianBlur(28 * SCALE))
		elif mode == "radial":
			for radius in range(220, 10, -5):
				alpha = int(color[3] * (1.0 - radius / 220.0) ** 1.4)
				_ellipse(draw, [256-radius, 256-radius, 256+radius, 256+radius], (*color[:3], alpha))
		else:
			for _ in range(72):
				x, y = rng.randrange(-30, 470), rng.randrange(512)
				_line(draw, [(x, y), (x + rng.randrange(45, 130), y + rng.randrange(-8, 9))], color, rng.choice([1, 2, 3]))
		path = dir_path / filename
		_save(image, path, 512)
		asset = _asset(semantic, path, 512)
		if semantic in {"rain_squall_mask", "rain_squall_edge_mask"}:
			asset["source_masters"] = ["res://%s" % path.relative_to(ROOT).as_posix() for path in rain_master_paths]
			asset["generation_method"] = "weather_master_alpha_composite"
		assets.append(asset)
	return assets


def _facility_sprite(kind: str, destroyed: bool) -> Image.Image:
	image, draw = _canvas(256)
	stone = (66, 75, 72, 245) if not destroyed else (54, 57, 55, 220)
	metal = (104, 119, 111, 255) if not destroyed else (76, 73, 67, 230)
	sand = (167, 151, 105, 235) if not destroyed else (119, 101, 74, 210)
	dark = (35, 52, 53, 255)
	_rect(draw, [48, 64, 208, 200], stone, dark, 4, 18)
	_rect(draw, [59, 75, 197, 189], sand, None, 0, 12)
	if kind == "coastal_observation_post":
		_rect(draw, [86, 92, 170, 166], metal, dark, 3, 8)
		_rect(draw, [105, 66, 151, 104], (72, 91, 87, 255), dark, 3, 6)
		_line(draw, [(128, 65), (128, 35)], (38, 62, 65, 255), 5)
		_ellipse(draw, [118, 27, 138, 43], (144, 191, 190, 255), dark, 2)
	elif kind == "coastal_battery":
		for x in (94, 162):
			_ellipse(draw, [x-27, 98, x+27, 152], metal, dark, 4)
			_line(draw, [(x, 116), (x, 48)], (58, 72, 70, 255), 10)
			_ellipse(draw, [x-10, 104, x+10, 124], (132, 144, 128, 255), dark, 2)
	elif kind == "forward_supply_point":
		for box in ([74, 88, 118, 130], [128, 82, 178, 132], [92, 140, 144, 180]):
			_rect(draw, box, (139, 101, 60, 255), dark, 3, 4)
		for x in (166, 186):
			_ellipse(draw, [x-11, 144, x+11, 184], (92, 111, 105, 255), dark, 3)
	elif kind == "coastal_airfield":
		_rect(draw, [78, 70, 178, 194], (83, 92, 88, 255), (205, 216, 194, 180), 3, 4)
		_line(draw, [(128, 79), (128, 185)], (219, 223, 198, 230), 5)
		_poly(draw, [(128, 105), (142, 135), (171, 143), (171, 152), (139, 150), (133, 175), (123, 175), (117, 150), (86, 152), (86, 143), (114, 135)], (49, 69, 70, 255), dark, 2)
	elif kind == "radar_station":
		_rect(draw, [92, 120, 164, 178], metal, dark, 3, 6)
		_line(draw, [(128, 125), (128, 72)], (52, 70, 69, 255), 5)
		_ellipse(draw, [78, 52, 178, 112], (157, 184, 174, 255), dark, 3)
		_poly(draw, [(78, 82), (178, 82), (152, 109), (104, 109)], (61, 83, 82, 255), dark, 2)
	elif kind == "communication_station":
		_rect(draw, [85, 128, 171, 178], metal, dark, 3, 6)
		_line(draw, [(128, 130), (128, 39)], (48, 67, 67, 255), 6)
		_line(draw, [(128, 54), (90, 126), (166, 126), (128, 54)], (84, 109, 105, 255), 3)
		for y in (64, 86, 108): _line(draw, [(108, y), (148, y)], (148, 176, 167, 255), 3)
	elif kind == "mine_control_station":
		_rect(draw, [78, 100, 178, 174], (80, 91, 85, 255), dark, 4, 12)
		for x in (98, 158):
			_ellipse(draw, [x-15, 68, x+15, 98], (112, 124, 112, 255), dark, 3)
			_ellipse(draw, [x-6, 77, x+6, 89], dark)
		_line(draw, [(98, 83), (128, 55), (158, 83)], (43, 61, 61, 255), 4)
	else:
		_rect(draw, [68, 92, 88, 190], (85, 96, 91, 255), dark, 3)
		_rect(draw, [168, 92, 188, 190], (85, 96, 91, 255), dark, 3)
		_line(draw, [(88, 112), (168, 112)], (58, 78, 77, 255), 8)
		_line(draw, [(175, 108), (144, 60), (126, 60)], (128, 112, 71, 255), 7)
		_rect(draw, [109, 143, 148, 176], (90, 108, 105, 255), dark, 3, 4)
	if destroyed:
		for points in [[(62, 78), (112, 118), (80, 154)], [(194, 86), (147, 129), (190, 179)], [(82, 190), (126, 152), (164, 198)]]:
			_line(draw, points, (37, 37, 34, 235), 7)
		for x, y, r in [(69, 57, 13), (188, 181, 17), (151, 76, 10), (98, 207, 12)]:
			_poly(draw, [(x-r, y+r//2), (x-r//2, y-r), (x+r, y-r//3), (x+r//2, y+r)], (69, 66, 57, 230), dark, 2)
	return image


def build_facility_assets() -> list[dict]:
	dir_path = ROOT / "assets/environment/facilities"
	assets = []
	for kind in ["coastal_observation_post", "coastal_battery", "forward_supply_point", "coastal_airfield", "radar_station", "communication_station", "mine_control_station", "repair_berth"]:
		for state in ("base", "destroyed"):
			path = dir_path / ("facility_%s_%s.png" % (kind, state))
			_save(_facility_sprite(kind, state == "destroyed"), path, 256)
			assets.append(_asset("facility.%s.%s" % (kind, state), path, 256))
	for state, color in {
		"active": (105, 225, 197, 150), "suppressed": (220, 171, 78, 155), "offline": (99, 119, 122, 150),
		"communication_disrupted": (176, 104, 156, 150), "runway_suppressed": (210, 110, 77, 150), "servicing": (106, 184, 223, 150),
	}.items():
		image, draw = _canvas(128)
		_ellipse(draw, [12, 12, 116, 116], (0, 0, 0, 0), color, 7)
		for index in range(4):
			angle = math.tau * index / 4
			_line(draw, [(64 + math.cos(angle)*42, 64 + math.sin(angle)*42), (64 + math.cos(angle)*55, 64 + math.sin(angle)*55)], color, 5)
		path = dir_path / ("facility_state_%s_overlay.png" % state)
		_save(image, path, 128)
		assets.append(_asset("facility.state.%s" % state, path, 128))
	return assets


def _icon(symbol: str, color=(126, 226, 220, 255), warning=False) -> Image.Image:
	image, draw = _canvas(96)
	stroke = (42, 78, 86, 255)
	fill = (219, 247, 241, 235) if not warning else (238, 203, 111, 240)
	_ellipse(draw, [10, 10, 86, 86], (16, 45, 54, 210), stroke, 4)
	if symbol == "waves":
		for y in (36, 50, 64): _line(draw, [(24, y), (36, y-5), (48, y), (60, y-5), (72, y)], color, 4)
	elif symbol == "channel":
		_line(draw, [(32, 70), (32, 26)], fill, 6); _line(draw, [(64, 70), (64, 26)], fill, 6); _poly(draw, [(48, 20), (57, 34), (39, 34)], color)
	elif symbol == "reef":
		_poly(draw, [(23, 63), (33, 36), (49, 29), (72, 59), (61, 73), (38, 70)], fill, stroke, 3)
	elif symbol == "blocked":
		_line(draw, [(27, 27), (69, 69)], fill, 9); _line(draw, [(69, 27), (27, 69)], fill, 9)
	elif symbol == "shell":
		_ellipse(draw, [27, 27, 48, 48], fill, stroke, 3); _line(draw, [(46, 46), (69, 69)], fill, 7); _line(draw, [(66, 28), (28, 66)], (232, 126, 86, 255), 5)
	elif symbol == "collision":
		_poly(draw, [(48, 19), (58, 39), (80, 43), (62, 57), (66, 79), (48, 66), (30, 79), (34, 57), (16, 43), (38, 39)], fill, stroke, 3)
	elif symbol == "fog":
		for box in ([20,35,58,62],[38,27,78,62],[28,45,72,70]): _ellipse(draw, box, fill)
	elif symbol == "rain":
		for x in (32,48,64): _line(draw, [(x, 27), (x-9, 64)], color, 4)
	elif symbol == "foam":
		for y in (38,55): _line(draw, [(22,y),(34,y-6),(48,y),(62,y-6),(75,y)], fill, 4)
	elif symbol == "lee":
		_poly(draw, [(23,67),(40,29),(55,44),(72,29),(68,69)], fill, stroke, 3)
	elif symbol == "moon":
		_ellipse(draw, [28,24,69,68], fill); _ellipse(draw, [42,17,76,55], (16,45,54,255))
	elif symbol == "current":
		_line(draw, [(20,48),(68,48)], fill, 7); _poly(draw, [(68,34),(83,48),(68,62)], fill)
	elif symbol == "tide":
		_line(draw, [(24,58),(72,58)], fill, 5); _poly(draw, [(48,20),(36,39),(60,39)], color); _line(draw, [(48,39),(48,72)], color, 4)
	elif symbol == "boundary":
		for start in range(20, 72, 14): _line(draw, [(start,68),(start+8,68)], fill, 4)
		_poly(draw, [(25,55),(48,24),(72,55)], (0,0,0,0), fill, 4)
	elif symbol == "trend":
		_line(draw, [(20,65),(38,47),(52,55),(76,28)], fill, 6); _poly(draw, [(64,25),(79,24),(77,40)], fill)
	else:
		_poly(draw, [(48,19),(76,72),(20,72)], fill, stroke, 3)
	return image


def build_ui_assets() -> tuple[list[dict], list[dict]]:
	dir_path = ROOT / "assets/ui/processed/battle/terrain"
	export_path = ROOT / "assets/ui/export/2x"
	icons = {
		"ui_marker_shallow_water": "waves", "ui_marker_navigation_channel": "channel", "ui_marker_reef_sandbar": "reef",
		"ui_marker_terrain_collision": "collision", "ui_marker_shell_path_blocked": "shell", "ui_marker_navigation_blocked": "blocked",
		"ui_marker_environment_sea_fog": "fog", "ui_marker_environment_rain_squall": "rain", "ui_marker_environment_high_sea": "foam",
		"ui_marker_environment_lee_water": "lee", "ui_marker_environment_moonlit_lane": "moon", "ui_marker_environment_strong_current": "current",
		"ui_marker_environment_tide": "tide", "ui_marker_environment_zone_boundary": "boundary", "ui_marker_environment_movement_trend": "trend",
	}
	terrain_assets = []
	for name, symbol in icons.items():
		image = _icon(symbol, warning=symbol in {"blocked", "shell", "collision", "reef"})
		path = dir_path / (name + ".png")
		_save(image, path, 96)
		export_path.mkdir(parents=True, exist_ok=True)
		_save(image, export_path / (name + ".png"), 192)
		terrain_assets.append(_asset(name.removeprefix("ui_marker_"), path, 96))

	facility_assets = []
	for kind in ["coastal_observation_post", "coastal_battery", "forward_supply_point", "coastal_airfield", "radar_station", "communication_station", "mine_control_station", "repair_berth"]:
		frame, draw = _canvas(96)
		_ellipse(draw, [8, 8, 88, 88], (16, 45, 54, 220), (112, 211, 205, 255), 4)
		sprite = Image.open(ROOT / "assets/environment/facilities" / ("facility_%s_base.png" % kind)).convert("RGBA").resize((64 * SCALE, 64 * SCALE), LANCZOS)
		frame.alpha_composite(sprite, (16 * SCALE, 16 * SCALE))
		name = "ui_marker_facility_%s" % kind
		path = dir_path / (name + ".png")
		_save(frame, path, 96)
		_save(frame, export_path / (name + ".png"), 192)
		facility_assets.append(_asset("ui.%s" % name.removeprefix("ui_marker_facility_"), path, 96))

	status_icons = {
		"ui_icon_facility_active": "trend", "ui_icon_facility_seize": "channel", "ui_icon_facility_suppressed": "blocked",
		"ui_icon_facility_recovered": "waves", "ui_icon_facility_destroyed": "collision", "ui_icon_facility_service_interrupted": "blocked",
		"ui_icon_facility_service_complete": "trend", "ui_icon_mission_air_recon": "boundary", "ui_icon_mission_fighter_patrol": "current",
		"ui_icon_mission_airstrike": "shell", "ui_marker_minefield_known": "reef", "ui_marker_minefield_unknown": "boundary",
		"ui_marker_minefield_disabled": "blocked", "ui_marker_minefield_safe_channel": "channel",
	}
	for name, symbol in status_icons.items():
		image = _icon(symbol, warning=symbol in {"blocked", "collision", "shell", "reef"})
		path = dir_path / (name + ".png")
		_save(image, path, 96)
		_save(image, export_path / (name + ".png"), 192)
		facility_assets.append(_asset("ui.%s" % name.removeprefix("ui_icon_").removeprefix("ui_marker_"), path, 96))
	return terrain_assets, facility_assets


def build_environment_vfx() -> list[dict]:
	dir_path = ROOT / "assets/vfx/combat/environment"
	assets = []
	for size_name, size, rays in [("small", 128, 12), ("medium", 192, 18), ("large", 256, 25)]:
		image, draw = _canvas(size)
		center = size / 2
		for index in range(rays):
			angle = math.tau * index / rays + (index % 3) * 0.09
			inner = size * 0.12
			outer = size * (0.32 + 0.11 * ((index * 7) % 5) / 4)
			_line(draw, [(center+math.cos(angle)*inner, center+math.sin(angle)*inner), (center+math.cos(angle)*outer, center+math.sin(angle)*outer)], (229, 244, 221, 185), max(2, size // 80))
		_ellipse(draw, [center-size*.18, center-size*.18, center+size*.18, center+size*.18], (101, 119, 96, 130), (238, 247, 223, 210), max(2, size//64))
		path = dir_path / ("vfx_environment_shell_terrain_impact_%s_01.png" % size_name)
		_save(image.filter(ImageFilter.GaussianBlur(SCALE // 3)), path, size)
		assets.append(_asset("environment.shell_terrain_impact.%s" % size_name, path, size))
	image, draw = _canvas(192)
	for radius in (65, 48, 31): _ellipse(draw, [96-radius, 96-radius*.45, 96+radius, 96+radius*.45], (0,0,0,0), (205,246,237,180), 5)
	for index in range(20):
		angle = math.tau * index / 20
		_ellipse(draw, [96+math.cos(angle)*58-4, 96+math.sin(angle)*28-4, 96+math.cos(angle)*58+4, 96+math.sin(angle)*28+4], (192,240,232,190))
	path = dir_path / "vfx_environment_torpedo_terrain_impact_01.png"
	_save(image, path, 192)
	assets.append(_asset("environment.torpedo_terrain_impact", path, 192))
	for name, symbol in [("mine_trigger", "collision"), ("mine_sweep", "waves")]:
		path = dir_path / ("vfx_environment_%s_01.png" % name)
		_save(_icon(symbol, warning=name == "mine_trigger"), path, 192)
		assets.append(_asset("environment.%s" % name, path, 192))
	return assets


def _asset(semantic: str, path: Path, size: int | tuple[int, int]) -> dict:
	width, height = (size, size) if isinstance(size, int) else size
	return {"semantic": semantic, "path": "res://%s" % path.relative_to(ROOT).as_posix(), "size": [width, height], "alpha": True}


def _write_manifest(path: Path, family: str, assets: list[dict]) -> None:
	path.parent.mkdir(parents=True, exist_ok=True)
	path.write_text(json.dumps({"schema_version": 1, "asset_family": family, "generated_by": "tools/terrain/build_scene_combat_assets.py", "assets": assets}, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


def _update_combat_manifest(vfx_assets: list[dict]) -> None:
	path = ROOT / "assets/vfx/combat/qa/combat_vfx_asset_manifest.json"
	document = json.loads(path.read_text(encoding="utf-8"))
	document["assets"] = [item for item in document.get("assets", []) if not str(item.get("semantic", "")).startswith("environment.")]
	for asset in vfx_assets:
		document["assets"].append({"semantic": asset["semantic"], "category": "environment", "file": asset["path"].removeprefix("res://"), "source": "codex_procedural", "width": asset["size"][0], "height": asset["size"][1], "alpha": True})
	path.write_text(json.dumps(document, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


def main() -> None:
	terrain_assets = build_terrain_assets()
	zone_assets = build_environment_zone_assets()
	facility_assets = build_facility_assets()
	terrain_ui_assets, facility_ui_assets = build_ui_assets()
	vfx_assets = build_environment_vfx()
	dependency_path = ROOT / "assets/environment/facilities/facility_dependency_node.png"
	_save(_icon("current"), dependency_path, 96)
	facility_assets.append(_asset("facility.dependency.node", dependency_path, 96))
	_write_manifest(ROOT / "assets/environment/terrain/terrain_asset_manifest.json", "terrain and nearshore", terrain_assets + terrain_ui_assets + vfx_assets)
	_write_manifest(ROOT / "assets/environment/facilities/facility_asset_manifest.json", "shore facilities", facility_assets + facility_ui_assets)
	_write_manifest(ROOT / "assets/environment/weather/zones/environment_zone_asset_manifest.json", "local environment zones", zone_assets)
	_update_combat_manifest(vfx_assets)


if __name__ == "__main__":
	main()
