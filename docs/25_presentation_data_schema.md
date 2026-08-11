# 表现配置数据契约

## 1. 文档功能与边界

本文是窗口、镜头、海面 palette、角色绑定点表现校正、投射物外观、武器表现映射和 VFX 播放参数的数据形状真源。视觉目标与资产语义分别见 `docs/40_art_direction_design.md` 至 `docs/45_art_asset_interface_design.md`。

本文字段只影响表现，不得进入 Domain 命中、伤害、射程、弹速、碰撞、侦查、AI 或模拟随机数。

## 2. PresentationSettings

```text
id # settings.presentation
window.logical_size
window.default_size
window.size_options[]
camera.default_zoom
camera.zoom_step
camera.min_visible_size
camera.max_map_visible_fraction
```

- 所有尺寸为正；默认窗口必须包含在候选列表中。
- `camera.zoom_step>1`；可见范围和地图比例必须保持合法。
- 用户选择写入用户偏好，不写回项目 Definition；镜头状态不进入 BattleState。

## 3. OceanPalette

`palettes` 是以 palette ID 为键的对象；每个值使用以下字段：

```text
display_name, time_of_day, weather
base_texture
clear_glint_texture, weather_cloud_texture, foam_texture
rain_line_texture, rain_ripple_texture, storm_shadow_texture
lightning_mask_texture, snow_flake_texture, snow_haze_texture
deep_color, surface_color, shallow_color, highlight_color
cloud_color, warm_reflection_color
wave_strength, sparkle_strength, cloud_opacity
warm_reflection_strength, animation_speed, ai_texture_strength
foam_strength, rain_strength, mist_strength, lightning_strength
cloud_scale, cloud_cutoff, cloud_softness
wave_scale, foam_coverage
rain_angle, rain_density, rain_line_strength, rain_ripple_strength
squall_strength, snow_strength, snow_haze_strength
```

- palette ID 与 `docs/22_scene_environment_data_schema.md` 的战斗条件语义一一对应。
- 贴图字段保存 `res://` 资源路径；路径存在性和资产目录约束由 `docs/45_art_asset_interface_design.md` 拥有。
- 颜色和强度范围由加载校验约束；缺少某天气层时使用显式默认值，不改变战斗条件。

## 4. CharacterBindPointConfig

角色 processed 绑定点配置位于 `assets/characters/{character_id}/processed/config/{character_id}_meta_bind_points.json`：

```text
schema_version
assets
heading_offsets_degrees? # Dictionary<完整战斗资产文件名, float>
```

- `heading_offsets_degrees` 可缺省；未声明的资产查询结果为 `0`。
- 键必须是同一角色 processed battle 目录中已存在的完整资产文件名，例如 `warspite_battle_rig_base.png`，不得使用语义名或资源路径。
- 值以度为单位，必须是有限数且位于 `[-180, 180]`。它只校正贴图母版相对“舰艏向右”零角度的表现朝向，不改变 Domain 航向、碰撞椭圆或战斗结算。
- `ShipUnitView` 必须对战斗部件绘制和属于该资产的绑定点应用同一偏移。配置不是对象时、键无法解析到同角色战斗资产、值不是数值、非有限或超出范围时，资产目录加载失败并报告角色与字段。
- `assets` 内绑定点的语义名称、坐标与资源查询接口见 `docs/45_art_asset_interface_design.md`；本节只拥有配置字段形状与加载校验。

## 5. ProjectileVisualDefinition

```text
id, aliases[]?
projectile_id, projectile_type
sprite, trail_sprite?
trail_profile_id?, impact_profile?, miss_profile?
warning_profile?, fall_profile?, hit_profile?
payload_visual_id?
trail_color?, trail_length?
shell_trail_caliber_pixel_multiplier?
shell_trail_width?, shell_trail_duration?
shell_trail_outer_width_multiplier?, shell_trail_outer_alpha?
shell_trail_head_glow_radius?
shell_trail_afterimage_seconds?, shell_trail_afterimage_samples?
shell_trail_segment_count?
shell_trail_color_key?, shell_trail_color_palette?
scale, rotation_mode
arc_mode?
```

- 宽度、时长、光晕和口径非负；外层宽度倍率至少 `1`；透明度位于 `[0,1]`。
- 残影采样数和尾迹分段数使用加载器允许的有限范围。
- 口径只选择表现档位，不改变 WeaponDefinition；缺失时允许按稳定武器元数据回退，不把显示名解析结果写回数据。

## 6. WeaponVisualDefinition

```text
id, aliases[]?
character_id
weapon_group_id? # 或 weapon_id
weapon_id?
projectile_visual_id
secondary_projectile_visual_id?
fire_animation_state, launch_bind
legacy_launch_bind?, recovery_bind?
muzzle_vfx_role?, impact_vfx_role?
launch_profile?, trail_profile?, impact_profile?
warning_profile?, fall_profile?, hit_profile?, landing_profile?
vfx_role_mappings?
```

角色、武器或武器组、投射物表现和 VFX Profile 引用必须存在；`weapon_group_id` 与 `weapon_id` 至少有一个。公共表现优先按武器类别复用；角色覆盖只声明差异。音频尚无正式设计和运行时资产，不在本契约预留字段。

## 7. VFXPlaybackProfile

```text
id, aliases[]?
sprite?
duration, fps, loop
anchor, z_layer, rotation_mode
scale, follow_owner, blend_mode, fade_out
screen_shake?
```

- `duration/scale` 为正；层级、混合、绑定与跟随策略属于有限枚举。
- VFX 不得直接读取或修改战斗规则；它只消费已经成立的战斗事件。

## 8. 引用与验收

- 表现 ID 唯一，所有武器、投射物、VFX 和资产语义引用可解析。
- 缺失表现可以使用明确公共回退，但不得让配置加载失败静默隐藏规则对象。
- 资产路径、目录和 manifest 结构只由 `docs/45_art_asset_interface_design.md` 维护。
