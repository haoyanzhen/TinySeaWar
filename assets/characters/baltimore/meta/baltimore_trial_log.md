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
