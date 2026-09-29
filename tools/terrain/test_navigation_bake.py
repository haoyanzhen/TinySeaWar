"""Same-radius permission derivation must equal a fresh geometry bake."""
import copy
import unittest
from pathlib import Path

from bake_navigation_graph import PROFILES, bake_profile, bake_profiles, restrict_profile
from terrain_geometry import read_json

ROOT = Path(__file__).resolve().parents[2]
SHALLOW = next(p for p in PROFILES if p["id"] == "navigation.profile.standard_shallow")
DEEP = next(p for p in PROFILES if p["id"] == "navigation.profile.standard_deep")


class NavigationBakeTest(unittest.TestCase):
    def test_water_crossing_and_isolated_nodes(self):
        terrain = {"map_size": [640, 640], "obstacles": [], "regions": [
            {"id": "shallow", "priority": 1, "region_type": "ShallowWater", "polygon": [[180, 0], [210, 0], [210, 640], [180, 640]]},
            {"id": "channel", "priority": 2, "region_type": "NavigationChannel", "polygon": [[175, 275], [215, 275], [215, 355], [175, 355]]},
        ]}
        source = bake_profile(terrain, SHALLOW, 128)
        original = copy.deepcopy(source)
        derived = restrict_profile(terrain, source, DEEP)
        self.assertEqual(derived, bake_profile(terrain, DEEP, 128))
        self.assertEqual(source, original)
        self.assertEqual(derived, restrict_profile(terrain, source, DEEP))
        self.assertLess(sum(len(n["neighbors"]) for n in derived["nodes"]), sum(len(n["neighbors"]) for n in source["nodes"]))
        self.assertEqual(len(bake_profiles(terrain, 128)), 4)

    def test_incompatible_radius_is_rejected(self):
        source = {**SHALLOW, "nodes": [], "cell_size": 128}
        with self.assertRaises(ValueError):
            restrict_profile({}, source, {**DEEP, "radius": 46})

    def test_real_maps_match_independent_geometry_bake(self):
        terrains = read_json(ROOT / "data/terrain/terrain_definitions.json")["definitions"]
        graphs = {x["terrain_definition_id"]: x for x in read_json(ROOT / "data/terrain/navigation_definitions.json")["definitions"]}
        for terrain in terrains:
            profiles = {p["id"]: p for p in graphs[terrain["id"]]["profiles"]}
            with self.subTest(terrain=terrain["id"]):
                self.assertEqual(profiles[DEEP["id"]], restrict_profile(terrain, profiles[SHALLOW["id"]], DEEP))
                if terrain["id"] in ["terrain.map.double_island_long_channel_16x9", "terrain.map.ring_lagoon_16x9"]:
                    self.assertEqual(profiles[DEEP["id"]], bake_profile(terrain, DEEP, 128))


if __name__ == "__main__":
    unittest.main()
