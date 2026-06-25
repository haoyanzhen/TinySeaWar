# wahoo Phase 2 Trial Log

- Source: docs/41_character_art_design.md phase 2.
- Generator: gpt-image-2 through the TinySeaWar art pipeline skill.
- Current status: `blocked_animation_regen`; corrected anchor and non-animation MVP derivatives accepted, but animation master must be regenerated with the Q-version battlefield-unit prompt before production import.
- Style anchor generated on reserved green: low submarine silhouette, six bow and four stern torpedo ports, sonar/periscope pieces, shark-cape identity and blue-orange oxygen indicator. Automatic review: pass for faction-gate review.
- User review rejected swim fins on submarine footwear. Anchor edited to compact waterproof tactical boots while preserving character identity and six-bow/four-stern tube layout; corrected anchor accepted for production.
- Character-specific VFX was generated. After repeated reference-image endpoint failures, identity-bearing MVP UI and battle sheets were derived directly from the accepted corrected anchor; the fore/aft torpedo nodes preserve the explicit `6+4` count.
- The 20-frame MVP animation master was derived from the accepted battle-body cell. Expression differentiation and higher-fidelity hand-drawn animation remain polish items.
- Postprocess and contract audit previously completed structurally, but the animation source is no longer accepted: runtime animation must be Q-version battlefield-unit art and must not bake detached launched shells, torpedoes, aircraft, depth charges, long trails, or large impacts into the character frames. All accepted non-animation character views keep tactical boots and contain no foot-mounted swim fins.
- Regenerated Q-version animation-master candidate: `assets/characters/wahoo/battle/wahoo_anim_5x4_master_candidate_q_20260625.png`. Quick pre-screen: Q-version low submarine unit, no foot flippers and no detached torpedo body observed, awaiting human confirmation before import.
- User accepted the Q-version animation master. Previous generated animation masters, animation candidates, processed animation frames, animation alpha source, and animation config were deleted. The accepted Q-version master was promoted to `assets/characters/wahoo/battle/wahoo_anim_5x4_master.png`.
- Boxed-vs-clean split test completed. Clean split produced 20 transparent frames with shared `400x221` canvas and no edge-touching alpha; boxed split retained green/grid context for QA only.
