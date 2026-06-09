# Postprocess Batch 01 Summary

## Scope

This batch validates the role-art postprocess pipeline on two Trial Batch 01 representatives:

- `enterprise_cv6`: carrier, level 3.
- `hai_shih`: submarine, level 1.

The original trial sheets remain unchanged. Postprocessed outputs are stored under each character's `processed/` directory.

## Outputs

Enterprise CV-6:

- `processed/source_alpha/`: 7 alpha-cleaned copies of the original trial PNGs.
- `processed/ui/`: half illustration, skill cut-in, portrait, small portrait, and airstrike skill icon.
- `processed/battle/`: battle body, carrier rig base, and 4 aircraft sprites.
- `processed/vfx/`: airstrike markers, aircraft paths, deck lane, wake, splash, and hit sparks.
- `processed/anim/`: idle, move, attack, hit, and firepower keyframe reference crops.
- `processed/config/`: bind points, animation config, VFX config, and postprocess manifest.

Hai Shih:

- `processed/source_alpha/`: 7 alpha-cleaned copies of the original trial PNGs.
- `processed/ui/`: half illustration, skill cut-in, portrait, small portrait, chibi head, expressions, submarine skill icon, and class icon.
- `processed/battle/`: battle body, submarine rig base, torpedo tube, periscope node, and sonar node.
- `processed/vfx/`: wake, underwater shadow, bubbles, torpedo trail, torpedo flash, sonar pulse, periscope glint, ripple, and stealth shimmer.
- `processed/anim/`: idle, move, attack, hit, and firepower keyframe reference crops.
- `processed/config/`: bind points, animation config, VFX config, and postprocess manifest.

## Validation

- Enterprise CV-6 produced 35 RGBA PNGs under `processed/`.
- Hai Shih produced 40 RGBA PNGs under `processed/`.
- Config JSON files validate with `python3 -m json.tool`.
- Representative split assets have non-empty alpha bounds.
- Texture repair pass replaced global near-white removal with border-connected background flood fill. This preserves white hair, white uniforms, foam, pale aircraft trails, and light VFX texture inside the cropped asset.
- Split assets now receive transparent padding after alpha trimming, so no processed split PNG has alpha touching the canvas edge.

## Known Limitations

- Background cleanup is automatic and first-pass quality. The repaired flood-fill method is safer for pale texture, but final import still needs artist review for halos and anti-aliased edges.
- Crop boxes are manually selected from Trial Batch 01 sheets. They are recorded in each postprocess manifest but should be reviewed by an artist before final import.
- Animation crops are keyframe references, not runtime animation curves.
- Binding points are initial estimates. They must be checked in the battle scene before final gameplay tuning.

## Next Step

Use Enterprise CV-6 to validate carrier launch/recovery and airstrike VFX binding. Use Hai Shih to validate submarine torpedo port, sonar origin, underwater shadow, and bubble trail binding.
