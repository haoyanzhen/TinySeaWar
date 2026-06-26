# cleveland Phase 2 Trial Log

- Source: docs/41_character_art_design.md phase 2.
- Generator: gpt-image-2 through the TinySeaWar art pipeline skill.
- Current status: `blocked_animation_regen`; anchor and non-animation MVP derivatives accepted, but animation master must be regenerated with the Q-version battlefield-unit prompt before production import.
- Style anchor generated on reserved green: four triple main-gun groups, layered anti-air/radar silhouette, no torpedo equipment and no readable text. Automatic review: pass for faction-gate review.
- User accepted the anchor for production.
- Generated strict `4x2` UI sheet and `4x2` battle-component grid from the accepted anchor. Both retain identity, four-main-turret/no-torpedo language, radar and anti-air roles.
- Animation-master generation retries failed at the reference-image service network layer. The 20-frame MVP master was therefore derived from the accepted battle-body cell with deterministic micro-motion; higher-fidelity hand-drawn animation remains polish.
- VFX, bind points, and non-animation manifests remain usable. The animation source is no longer accepted: runtime animation must be Q-version battlefield-unit art and must not bake detached launched shells, torpedoes, aircraft, depth charges, long trails, or large impacts into the character frames.
- Regenerated Q-version animation-master candidate: `assets/characters/cleveland/battle/cleveland_anim_5x4_master_candidate_q_20260625.png`. Quick pre-screen: Q-version battle unit, no torpedo equipment or detached projectiles observed, awaiting human confirmation before import.
- User accepted the Q-version animation master. Previous generated animation masters, animation candidates, processed animation frames, animation alpha source, and animation config were deleted. The accepted Q-version master was promoted to `assets/characters/cleveland/battle/cleveland_anim_5x4_master.png`.
- Boxed-vs-clean split test completed. Clean split produced 20 transparent frames with shared `400x221` canvas and no edge-touching alpha; boxed split retained green/grid context for QA only.
- 2026-06-25 update: the accepted 5x4 route was retired after source-cell truncation risk was identified. Previous animation masters, split QA frames, and derived runtime frames were removed. New source package uses five independent 2x2 animation sheets: idle, move, attack, hit, and firepower.
- Rebuilt MVP source sheets from the accepted full-body style reference: UI 4x2, battle 4x2, five animation 2x2 sheets, and VFX 2x4. The no-torpedo rule remains enforced by the battle roles and VFX roles.
- 2026-06-26 update: the anchor-derived/procedural fallback chain is no longer accepted as a source of formal assets. Placeholder UI, battle, VFX, animation, processed outputs, and contact sheets were removed from the runtime source path. Current status: `source_assets_missing`; batch status: `not_batch_ready`. Keep only the accepted concept anchor, plan, brief, and log until real generated source sheets are available.
