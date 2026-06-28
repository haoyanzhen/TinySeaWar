#!/usr/bin/env python3
"""Deterministic geometry helpers shared by TinySeaWar terrain tools."""

from __future__ import annotations

import json
import math
from pathlib import Path
from typing import Iterable, Sequence

EPSILON = 1.0e-6


def read_json(path: str | Path) -> dict:
	with Path(path).open("r", encoding="utf-8") as handle:
		return json.load(handle)


def write_json(path: str | Path, payload: dict) -> None:
	target = Path(path)
	target.parent.mkdir(parents=True, exist_ok=True)
	target.write_text(json.dumps(payload, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


def signed_area(points: Sequence[Sequence[float]]) -> float:
	return 0.5 * sum(
		float(points[index][0]) * float(points[(index + 1) % len(points)][1])
		- float(points[(index + 1) % len(points)][0]) * float(points[index][1])
		for index in range(len(points))
	)


def polygon_area(points: Sequence[Sequence[float]]) -> float:
	return abs(signed_area(points))


def ensure_clockwise(points: Sequence[Sequence[float]]) -> list[list[float]]:
	result = [[round(float(point[0]), 3), round(float(point[1]), 3)] for point in points]
	if signed_area(result) > 0.0:
		result.reverse()
	return result


def orientation(a: Sequence[float], b: Sequence[float], c: Sequence[float]) -> float:
	return (float(b[0]) - float(a[0])) * (float(c[1]) - float(a[1])) - (float(b[1]) - float(a[1])) * (float(c[0]) - float(a[0]))


def point_on_segment(point: Sequence[float], a: Sequence[float], b: Sequence[float], epsilon: float = EPSILON) -> bool:
	if abs(orientation(a, b, point)) > epsilon:
		return False
	return (
		min(float(a[0]), float(b[0])) - epsilon <= float(point[0]) <= max(float(a[0]), float(b[0])) + epsilon
		and min(float(a[1]), float(b[1])) - epsilon <= float(point[1]) <= max(float(a[1]), float(b[1])) + epsilon
	)


def segments_intersect(a: Sequence[float], b: Sequence[float], c: Sequence[float], d: Sequence[float], epsilon: float = EPSILON) -> bool:
	o1 = orientation(a, b, c)
	o2 = orientation(a, b, d)
	o3 = orientation(c, d, a)
	o4 = orientation(c, d, b)
	if ((o1 > epsilon and o2 < -epsilon) or (o1 < -epsilon and o2 > epsilon)) and ((o3 > epsilon and o4 < -epsilon) or (o3 < -epsilon and o4 > epsilon)):
		return True
	return (
		(abs(o1) <= epsilon and point_on_segment(c, a, b, epsilon))
		or (abs(o2) <= epsilon and point_on_segment(d, a, b, epsilon))
		or (abs(o3) <= epsilon and point_on_segment(a, c, d, epsilon))
		or (abs(o4) <= epsilon and point_on_segment(b, c, d, epsilon))
	)


def polygon_self_intersections(points: Sequence[Sequence[float]]) -> list[tuple[int, int]]:
	result: list[tuple[int, int]] = []
	count = len(points)
	for first in range(count):
		first_next = (first + 1) % count
		for second in range(first + 1, count):
			second_next = (second + 1) % count
			if first == second or first_next == second or second_next == first:
				continue
			if first == 0 and second_next == 0:
				continue
			if segments_intersect(points[first], points[first_next], points[second], points[second_next]):
				result.append((first, second))
	return result


def point_in_polygon(point: Sequence[float], polygon: Sequence[Sequence[float]]) -> bool:
	inside = False
	x, y = float(point[0]), float(point[1])
	for index, a in enumerate(polygon):
		b = polygon[(index + 1) % len(polygon)]
		if point_on_segment(point, a, b):
			return True
		ay, by = float(a[1]), float(b[1])
		if (ay > y) == (by > y):
			continue
		intersection_x = float(a[0]) + (y - ay) * (float(b[0]) - float(a[0])) / (by - ay)
		if intersection_x >= x:
			inside = not inside
	return inside


def transform_point(point: Sequence[float], position: Sequence[float], scale: Sequence[float], rotation_degrees: float) -> list[float]:
	x = float(point[0]) * float(scale[0])
	y = float(point[1]) * float(scale[1])
	angle = math.radians(float(rotation_degrees))
	cosine, sine = math.cos(angle), math.sin(angle)
	return [round(x * cosine - y * sine + float(position[0]), 3), round(x * sine + y * cosine + float(position[1]), 3)]


def transform_polygon(points: Sequence[Sequence[float]], position: Sequence[float], scale: Sequence[float], rotation_degrees: float, origin: Sequence[float] = (0.0, 0.0)) -> list[list[float]]:
	centered = [[float(point[0]) - float(origin[0]), float(point[1]) - float(origin[1])] for point in points]
	return ensure_clockwise([transform_point(point, position, scale, rotation_degrees) for point in centered])


def bounds(points: Iterable[Sequence[float]]) -> list[float]:
	points_list = list(points)
	return [
		min(float(point[0]) for point in points_list),
		min(float(point[1]) for point in points_list),
		max(float(point[0]) for point in points_list),
		max(float(point[1]) for point in points_list),
	]


def ellipse_polygon(center: Sequence[float], radii: Sequence[float], vertices: int = 24, rotation_degrees: float = 0.0) -> list[list[float]]:
	angle = math.radians(rotation_degrees)
	cosine, sine = math.cos(angle), math.sin(angle)
	points = []
	for index in range(vertices):
		theta = math.tau * float(index) / float(vertices)
		x = math.cos(theta) * float(radii[0])
		y = math.sin(theta) * float(radii[1])
		points.append([float(center[0]) + x * cosine - y * sine, float(center[1]) + x * sine + y * cosine])
	return ensure_clockwise(points)


def sample_polyline(points: Sequence[Sequence[float]], distance: float) -> list[float]:
	"""Return the clamped point at a distance along a deterministic polyline."""
	if not points:
		return [0.0, 0.0]
	remaining = max(0.0, float(distance))
	previous = [float(points[0][0]), float(points[0][1])]
	for raw_current in points[1:]:
		current = [float(raw_current[0]), float(raw_current[1])]
		segment_length = math.hypot(current[0] - previous[0], current[1] - previous[1])
		if segment_length > EPSILON and remaining <= segment_length:
			ratio = remaining / segment_length
			return [previous[0] + (current[0] - previous[0]) * ratio, previous[1] + (current[1] - previous[1]) * ratio]
		remaining -= segment_length
		previous = current
	return previous


def distance_point_to_segment(point: Sequence[float], a: Sequence[float], b: Sequence[float]) -> float:
	px, py = float(point[0]), float(point[1])
	ax, ay = float(a[0]), float(a[1])
	bx, by = float(b[0]), float(b[1])
	dx, dy = bx - ax, by - ay
	denominator = dx * dx + dy * dy
	if denominator <= EPSILON:
		return math.hypot(px - ax, py - ay)
	t = max(0.0, min(1.0, ((px - ax) * dx + (py - ay) * dy) / denominator))
	return math.hypot(px - (ax + dx * t), py - (ay + dy * t))


def circle_clear(point: Sequence[float], radius: float, obstacles: Sequence[dict]) -> bool:
	for obstacle in obstacles:
		polygon = obstacle.get("polygon", [])
		if point_in_polygon(point, polygon):
			return False
		for index, a in enumerate(polygon):
			if distance_point_to_segment(point, a, polygon[(index + 1) % len(polygon)]) <= radius + EPSILON:
				return False
	return True
