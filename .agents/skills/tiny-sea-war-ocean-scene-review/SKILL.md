---
name: tiny-sea-war-ocean-scene-review
description: Create, adjust, export, and review TinySeaWar ocean scene art variants. Use when working on the 5 weather x 4 time ocean palettes, scene-layered ocean Shader parameters, rain/mist/lightning/foam tuning, or when the user asks to generate a contact sheet/overview image for manual art review.
---

# TinySeaWar Ocean Scene Review

## Workflow

1. Start in the TinySeaWar repository and check `git status --short` to protect unrelated work.
2. Read the current scene art sources as needed:
   - `docs/43_scene_art_design.md` for style, weather/time design, and acceptance rules.
   - `docs/48_scene_art_mvp_implementation.md` for current runtime scene implementation.
   - `data/environments/ocean_palettes.json` for palette assets.
   - `assets/environments/ocean/common/ocean_surface.gdshader` and `scripts/presentation/battle/ocean_surface.gd` for scene-layered implementation.
3. Keep the implementation parameterized. Prefer one ocean Shader plus palette JSON values over separate full-screen background images, but do not rely on color changes alone.
4. Preserve the 20 formal palette IDs:
   - Weather rows: `clear`, `cloudy`, `overcast`, `rain`, `thunderstorm`.
   - Time columns: `day`, `dawn`, `dusk`, `night`.
   - ID format: `{weather}_{time}`, for example `rain_night`.
5. Keep legacy aliases usable unless explicitly removing them: `day_clear`, `cloudy`, `dusk`.

## Palette Tuning

Use `data/environments/ocean_palettes.json` as the art asset source of truth. Each formal palette should include:

```text
display_name
time_of_day
weather
base_texture
deep_color
surface_color
shallow_color
highlight_color
cloud_color
warm_reflection_color
wave_strength
sparkle_strength
cloud_opacity
warm_reflection_strength
animation_speed
ai_texture_strength
foam_strength
rain_strength
mist_strength
lightning_strength
cloud_scale
cloud_cutoff
cloud_softness
wave_scale
foam_coverage
rain_angle
rain_density
rain_line_strength
rain_ripple_strength
squall_strength
```

Use these layer meanings:

- Time controls base color, brightness, color temperature, reflection color, and night readability.
- Weather controls the rendering profile: cloud scale, cloud edge hardness, wave scale, foam coverage, rain angle/density, ripples, mist, squall shadows, and lightning.
- Rain and thunderstorm must remain readable; lower rain opacity or mist before brightening UI or combat colors.
- Lightning should be cold white/blue and intermittent, not red/orange warning color.
- If a 20-palette sheet looks like tint-only variation, revise the weather profile fields before adding more color tweaks.

## Generate Review Sheet

Run the bundled script from the repository root:

```bash
.agents/skills/tiny-sea-war-ocean-scene-review/scripts/export_ocean_review_sheet.sh
```

Default output:

```text
/tmp/tinyseawar_ocean_review/ocean_20_palette_contact_sheet.png
```

Useful options:

```bash
.agents/skills/tiny-sea-war-ocean-scene-review/scripts/export_ocean_review_sheet.sh \
  --out-dir /tmp/tinyseawar_ocean_review \
  --size 960x540 \
  --camera 2048,1152
```

After generation, display the contact sheet in the final response with Markdown image syntax using the absolute path.

## Validation

After palette or Shader edits, run:

```bash
git diff --check
godot --headless --path . --script scripts/tests/scene_presentation_test.gd
```

For broader confidence after runtime changes, also run:

```bash
godot --headless --path . --script scripts/tests/test_runner.gd
```

If rendering previews, use non-headless Godot because the QA screenshot path may need the real renderer:

```bash
godot --path . --script scripts/tests/render_scene_qa.gd -- \
  --size=1920x1080 \
  --palette=rain_night \
  --output=/tmp/tinyseawar_ocean_rain_night.png \
  --camera=2048,1152
```

CoreAudio warnings during macOS render export are acceptable when the command exits successfully and the PNG is saved.
