from __future__ import annotations

import json
from pathlib import Path
import re

import character_roster


ROOT = Path(__file__).resolve().parents[2]
CHAR_ROOT = ROOT / "assets" / "characters"


def generation_brief_path(character_id: str) -> Path:
    root = CHAR_ROOT / character_id
    legacy_path = root / "meta" / f"{character_id}_generation_brief.md"
    provenance_path = root / "meta" / f"{character_id}_source_provenance.json"
    if provenance_path.exists():
        provenance = json.loads(provenance_path.read_text(encoding="utf-8"))
        if int(provenance.get("schema_version", 1)) < 2:
            return root / "meta" / f"{character_id}_generation_brief_v2.md"
    return legacy_path


def shared_prompt(entry: character_roster.CharacterRosterEntry, plan: dict[str, object]) -> str:
    inventory = json.dumps(plan.get("object_inventory", {}), ensure_ascii=False, sort_keys=True)
    return f"""2D anime shipgirl tactical naval game asset for TinySeaWar. Original design; do not imitate any existing shipgirl franchise.
Character origin: {entry.prototype}.
Faction: {entry.faction}. MVP ship class: {entry.ship_class_cn}. Level: {entry.level}.
Personality: {entry.personality}. Combat role: {entry.combat_role}.
Core visual direction: {entry.art_direction}.
Required MVP asset focus: {entry.asset_focus}.
Expected object inventory from the authoritative postprocess plan: {inventory}.
No real flags, no political symbols, no readable insignia text, no historical extremist symbols.
Clean readable silhouette, clear ship-class identity, high-quality anime linework, restrained cel shading, consistent face and hair. Character body, rig base, weapons and effect origins must remain visually separable."""


def build_brief(entry: character_roster.CharacterRosterEntry, plan: dict[str, object]) -> str:
    core = shared_prompt(entry, plan)
    battle_roles = ", ".join(plan["battle_grid_roles"])
    vfx_roles = ", ".join(plan["vfx_roles"])
    rules = "\n".join(f"- {rule}" for rule in plan["acceptance_rules"])
    return f"""# {entry.prototype} Phase 2 Generation Brief

## Generation route contract

- Primary route: Codex account built-in ImageGen; it does not require a project SDK or user-supplied API key.
- Ask the built-in generator for a transparent PNG (`background: "transparent"` as the generation intent), preserve its accepted output byte-for-byte, and verify the actual PNG Alpha channel and transparent canvas/border pixels before postprocessing.
- Codex-managed model and request identifiers must be recorded honestly as managed/not exposed; they are not replaced with invented Images API model names, endpoints, or request IDs.
- The direct Images API helper remains an explicit fallback for non-Codex batch environments. The legacy chroma-key route remains disabled by default and requires a recorded native-alpha failure reason.

## Shared prompt core

{core}

## Style anchor

{core}
Create the definitive full-body style anchor concept on a transparent background. Front three-quarter standing pose, complete outfit and ship rigging visible, generous empty transparent margin, no environment, no ocean, no UI, no text. Show the body, rig base, weapon identity and core accessory clearly; the accepted anchor will be the sole identity reference for all derivative sheets.

## UI 4x2 sheet

Use the accepted style anchor as the only identity reference. Create exactly eight separated cells in a 4x2 grid: portrait, small portrait, chibi head, default expression, serious expression, hit expression, skill icon for `{plan['skill_role']}`, and abstract `{entry.ship_class}` class icon. True transparent background, no checkerboard, no matte, no text, no overlapping cells.

## Battle 4x2 sheet

Use the accepted style anchor as the only identity reference. Create exactly eight isolated orthographic game assets in a 4x2 grid, in this order: {battle_roles}. True transparent background, no checkerboard or matte. Keep every component separated with clear empty transparent margins and readable pivots.

## Animation 2x2 state sheets

Use the accepted style anchor as the only identity reference. Create five separate chibi / SD battlefield-unit animation sheets, not full-body illustrations, portraits, half-body art, or skill cut-ins. Required files/states: idle, move, attack, hit, firepower. Each state is one 2-row by 2-column sheet ordered top-left, top-right, bottom-left, bottom-right as anticipation/start, action, feedback/recoil, recovery. Use an invisible logical grid: wide empty transparent gutters, no visible borders, no labels, no text. Every cell must contain the complete compact Q-version battle sprite matching the `battle_body_r` style: large readable head, small body, attached rigging and weapon nodes, clear small-scale silhouette, and at least 12% empty transparent margin on all sides. Identical face, hair, outfit, rigging, camera, scale, Q-version proportions, and equipment count in all four cells of each sheet. Animate only the chibi character body, attached rigging, weapon recoil, local muzzle flash/fire light, tiny local smoke/spark, local wake, local scan/aura cues, and pose changes. The four cells must be hand-drawn/generated as distinct key poses; do not duplicate the same character image with only translation, scale, tint, tiny rotation, aura, or external flash changes. Do not draw separate launched projectiles or detached attack objects: no flying shells, no bullets, no tracer streams, no torpedoes, no missiles, no aircraft, no detached depth charges, no large water impacts, no long projectile trails. True transparent background, no checkerboard or matte, no connected effects between cells.

## VFX 2x4 sheet

Create exactly eight isolated character-specific VFX overlays in a 2x4 grid, in this order: {vfx_roles}. Reusable projectile bodies and impacts are not duplicated. True transparent background, no checkerboard or matte, no text, crisp small-scale game VFX shapes.

## Acceptance rules

{rules}
"""


def preserved_appendix(existing: str) -> str:
    acceptance = existing.find("## Acceptance rules")
    if acceptance < 0:
        return ""
    match = re.search(r"^## (?!Acceptance rules).+$", existing[acceptance:], flags=re.MULTILINE)
    if not match:
        return ""
    return existing[acceptance + match.start():].strip()


def main() -> int:
    for entry in character_roster.load_roster(phase="phase2"):
        root = CHAR_ROOT / entry.character_id
        plan = json.loads((root / "postprocess_plan.json").read_text(encoding="utf-8"))
        brief_path = generation_brief_path(entry.character_id)
        appendix = preserved_appendix(brief_path.read_text(encoding="utf-8")) if brief_path.exists() else ""
        brief = build_brief(entry, plan).rstrip()
        if appendix:
            brief += f"\n\n{appendix}"
        brief_path.write_text(brief + "\n", encoding="utf-8")
        trial_path = root / "meta" / f"{entry.character_id}_trial_log.md"
        if not trial_path.exists():
            trial_path.write_text(
                f"# {entry.character_id} Phase 2 Trial Log\n\n"
                "- Source: docs/41_character_art_design.md phase 2.\n"
                "- Generator: GPT Image 2.5 through the native-alpha TinySeaWar art pipeline.\n"
                "- Current status: style anchor pending.\n"
                "- Derivative generation is blocked until the faction anchor gate is accepted.\n",
                encoding="utf-8",
            )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
