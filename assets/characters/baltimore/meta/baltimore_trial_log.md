# baltimore Phase 2 Trial Log

- Source: docs/41_character_art_design.md phase 2.
- Generator: gpt-image-2 through the TinySeaWar art pipeline skill.
- Current status: `blocked_animation_regen`; anchor and non-animation MVP derivatives accepted, but animation master must be regenerated with the Q-version battlefield-unit prompt before production import.
- Style anchor generated on reserved green after transient network retries: three heavy turret groups, radar/rangefinder identity, no torpedo equipment and no readable text. Automatic review: pass for faction-gate review.
- User accepted the anchor for production.
- UI derivative generation retries failed at the reference-image service network layer before a usable sheet was returned.
- Character-specific VFX was generated. Identity-bearing MVP UI and battle sheets were then derived directly from the accepted anchor; weapon, radar, anti-air, and wake nodes use deterministic text-free diagrams.
- The 20-frame MVP animation master was derived from the accepted battle-body cell. Distinct red/blue tint states and procedural node styling are recorded as polish candidates, not blockers.
- Postprocess and contract audit previously completed structurally, but the animation source is no longer accepted. The regenerated candidate was also rejected for using full-body illustration proportions instead of Q-version battlefield-unit proportions. The no-torpedo rule remains enforced in the plan and VFX roles.
- Regenerated Q-version animation-master candidate: `assets/characters/baltimore/battle/baltimore_anim_5x4_master_candidate_q_20260625.png`. Quick pre-screen: Q-version battle unit, no longer full-body illustration proportions, no torpedo equipment or detached projectiles observed, awaiting human confirmation before import.
- User accepted the Q-version animation master. Previous generated animation masters, animation candidates, processed animation frames, animation alpha source, and animation config were deleted. The accepted Q-version master was promoted to `assets/characters/baltimore/battle/baltimore_anim_5x4_master.png`.
- Boxed-vs-clean split test completed. Clean split produced 20 transparent frames with shared `400x221` canvas and no edge-touching alpha; boxed split retained green/grid context for QA only.
- 2026-06-25 update: the accepted 5x4 route was retired after source-cell truncation risk was identified. Previous animation masters, split QA frames, and derived runtime frames were removed. New source package uses five independent 2x2 animation sheets: idle, move, attack, hit, and firepower.
- Rebuilt MVP source sheets from the accepted full-body style reference: UI 4x2, battle 4x2, five animation 2x2 sheets, and VFX 2x4. The no-torpedo heavy-cruiser rule remains enforced by the battle roles and VFX roles.
- 2026-06-26 update: the anchor-derived/procedural fallback chain is no longer accepted as a source of formal assets. Placeholder UI, battle, VFX, animation, processed outputs, and contact sheets were removed from the runtime source path. Current status: `source_assets_missing`; batch status: `not_batch_ready`. Keep only the accepted concept anchor, plan, brief, and log until real generated source sheets are available.
