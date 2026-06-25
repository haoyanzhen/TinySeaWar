from __future__ import annotations

import json
from pathlib import Path

import character_roster


ROOT = Path(__file__).resolve().parents[2]
CHAR_ROOT = ROOT / "assets" / "characters"


def shared_prompt(entry: character_roster.CharacterRosterEntry) -> str:
    return f"""2D anime shipgirl tactical naval game asset for TinySeaWar. Original design; do not imitate any existing shipgirl franchise.
Character origin: {entry.prototype}.
Faction: {entry.faction}. MVP ship class: {entry.ship_class_cn}. Level: {entry.level}.
Personality: {entry.personality}. Combat role: {entry.combat_role}.
Core visual direction: {entry.art_direction}.
Required MVP asset focus: {entry.asset_focus}.
No real flags, no political symbols, no readable insignia text, no historical extremist symbols.
Clean readable silhouette, clear ship-class identity, high-quality anime linework, restrained cel shading, consistent face and hair. Character body, rig base, weapons and effect origins must remain visually separable."""


def build_brief(entry: character_roster.CharacterRosterEntry, plan: dict[str, object]) -> str:
    core = shared_prompt(entry)
    battle_roles = ", ".join(plan["battle_grid_roles"])
    vfx_roles = ", ".join(plan["vfx_roles"])
    rules = "\n".join(f"- {rule}" for rule in plan["acceptance_rules"])
    return f"""# {entry.prototype} Phase 2 Generation Brief

## Shared prompt core

{core}

## Style anchor

{core}
Create the definitive full-body style anchor concept on a transparent background. Front three-quarter standing pose, complete outfit and ship rigging visible, generous empty transparent margin, no environment, no ocean, no UI, no text. Show the body, rig base, weapon identity and core accessory clearly; the accepted anchor will be the sole identity reference for all derivative sheets.

## UI 4x2 sheet

Use the accepted style anchor as the only identity reference. Create exactly eight separated cells in a 4x2 grid: portrait, small portrait, chibi head, default expression, serious expression, hit expression, skill icon for `{plan['skill_role']}`, and abstract `{entry.ship_class}` class icon. Flat reserved green background, no text, no overlapping cells.

## Battle 4x2 sheet

Use the accepted style anchor as the only identity reference. Create exactly eight isolated orthographic game assets in a 4x2 grid, in this order: {battle_roles}. Flat reserved green background. Keep every component separated with clear empty margins and readable pivots.

## Animation 5x4 master

Use the accepted style anchor as the only identity reference. Create a chibi / SD battlefield-unit animation master, not a full-body illustration, portrait, half-body, or skill cut-in. The character must use compact Q-version battle-sprite proportions matching the `battle_body_r` style: large readable head, small body, attached rigging and weapon nodes, clear small-scale silhouette. Create a 5-row by 4-column animation master. Rows in order: idle, move, attack, hit, firepower. Each row has anticipation/start, action, feedback/recoil, recovery. Identical face, hair, outfit, rigging, camera, scale, Q-version proportions, and equipment count in all twenty cells. Animate only the chibi character body, attached rigging, weapon recoil, local muzzle flash/fire light, tiny local smoke/spark, local wake, local scan/aura cues, and pose changes. Do not draw separate launched projectiles or detached attack objects: no flying shells, no bullets, no tracer streams, no torpedoes, no missiles, no aircraft, no detached depth charges, no large water impacts, no long projectile trails. Flat reserved green background, no labels, no connected effects between cells.

## VFX 2x4 sheet

Create exactly eight isolated character-specific VFX overlays in a 2x4 grid, in this order: {vfx_roles}. Reusable projectile bodies and impacts are not duplicated. Flat reserved green background, no text, crisp small-scale game VFX shapes.

## Acceptance rules

{rules}
"""


def main() -> int:
    for entry in character_roster.load_roster(phase="phase2"):
        root = CHAR_ROOT / entry.character_id
        plan = json.loads((root / "postprocess_plan.json").read_text(encoding="utf-8"))
        (root / "meta" / f"{entry.character_id}_generation_brief.md").write_text(build_brief(entry, plan), encoding="utf-8")
        trial_path = root / "meta" / f"{entry.character_id}_trial_log.md"
        if not trial_path.exists():
            trial_path.write_text(
                f"# {entry.character_id} Phase 2 Trial Log\n\n"
                "- Source: docs/41_character_art_design.md phase 2.\n"
                "- Generator: gpt-image-2 through the TinySeaWar art pipeline skill.\n"
                "- Current status: style anchor pending.\n"
                "- Derivative generation is blocked until the faction anchor gate is accepted.\n",
                encoding="utf-8",
            )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
