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
submarine_depth_visual.transition_easing
submarine_depth_visual.surface.body_tint
submarine_depth_visual.surface.rig_tint
submarine_depth_visual.surface.underlay_color
submarine_depth_visual.surface.outline_color
submarine_depth_visual.surface.heading_color
submarine_depth_visual.submerged.body_tint
submarine_depth_visual.submerged.rig_tint
submarine_depth_visual.submerged.underlay_color
submarine_depth_visual.submerged.outline_color
submarine_depth_visual.submerged.heading_color
```

- 所有尺寸为正；默认窗口必须包含在候选列表中。
- `camera.zoom_step>1`；可见范围和地图比例必须保持合法。
- `submarine_depth_visual` 只控制可见潜艇的角色本体、舰装、脚下阴影、碰撞轮廓和航向线表现，不改变侦查、碰撞、攻击合法性或接触残影。
- `surface/submerged` 的颜色字段均为 `[r,g,b,a]`，四个分量必须在 `[0,1]`；角色本体与舰装分层调制，血条、名称、选中、锁定和旗舰标记不受其透明度影响。
- `transition_easing` 取 `Linear` 或 `SmoothStep`；转换进度读取快照的 `depth_transition.duration/remaining`，不得在表现配置中另存规则时长。稳定状态直接取对应端点，沉没表现优先于深度色调。
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
- `projectile_type=Aircraft` 的 `sprite` 统一引用公共飞机资产；五类机型使用 `visual.projectile.aircraft.fighter/bomber/torpedo_bomber/scout/asw`，机头向右为零旋转，`scale` 仅为表现初值。阴影复用该贴图 Alpha，由独立节点调制，机体不烘焙阴影或载荷。

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

角色、武器或武器组、投射物表现和 VFX Profile 引用必须存在；`weapon_group_id` 与 `weapon_id` 至少有一个。公共表现优先按武器类别复用；角色覆盖只声明差异。音频采用独立 SoundManifest，不在武器表现配置中复制声音路径。

新航空链按具体 `weapon_id` 优先查询，缺省才按 `weapon_group_id` 查询；同组多种载荷必须有具体武器覆盖，不能以次级贴图字段推断实际武器。机体映射统一指向公共机型，旧角色飞机和回收字段仅保留兼容。`launch_bind=unit_center` 使用单位中心回退；逐波表现生成位置与权威时间线仍服从 Application 投影，不从绑定点重算航程。

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

## 菜单封面与本机偏好（B 方案）

`assets/ui/processed/menu/cover_manifest.json` 使用 `schema_version: 1` 与 `covers` 数组；每项的稳定字段为 `id`、`character_id`、`display_name`、`title`、`category`、`image`。`image` 为仓库相对 PNG 路径，加载时归一为资源路径。`sha256`、`generator`、`model`、`review`、`prompt_brief` 为来源记录，不参与玩法。封面只服务菜单。

GameFlow 的本机 ConfigFile `menu` 节保存 `cover_id`、`reduce_motion`、`auto_view`；与已有 `display` 节互相保留。默认胡德海港、正常动效、允许自动观赏。会话内 `menu_return_page` 保存战后返回页，不属于进度存档或角色解锁。

## 航空持续投影

`Snapshot.aviation: Dictionary[wave_id, Dictionary]`。己方可含 `phase`、`position/heading`、`spawn_position/target_position`、`progress/end_progress`、`remaining`、`character_id/source_weapon_id/source_unit_id`；侦察/巡逻增加 `aircraft_kind/radius`，Physical 增加 `current_hp/max_hp`。敌方只允许当前公开片段白名单；字段缺失不允许通过资产或单位 ID 补查。

公共飞机 visual 可配置 `screen_canvas_width`（逻辑画布像素，缺省36），透明主体约24–28像素；渲染比例受镜头缩放补偿。初版每编队3架装饰，侦察/巡逻1架；这些数量不参与规则结算。炸弹使用该公共机型的 `payload_visual_id`，鱼雷机 A 阶段不生成水中装饰雷。

## 技能立绘闪回配置与偏好

`PresentationSettings.skill_cutin` 仅供表现层使用：`enter_seconds`、`hold_seconds`、`exit_seconds`、`compact_seconds` 为正有限秒数；`width_ratio`、`height_ratio` 为海域比例，上限分别 0.25 / 0.45；`compact_limit` 为 1–3 的整数。正式默认值由 `data/settings/presentation_settings.json` 维护；缺失或非法数值回退默认，上限在控件边界限制。播放行为真源见 `33`。

GameFlow 本机 ConfigFile 新增 `battle.skill_cutin_mode = full | simple | off`；旧配置缺字段或未知值回退 `full`，保存保留 `menu` 与 `display` 等其他节。写入失败保留本次会话选择并向 UI 返回失败，不进入进度存档、Domain 或模拟清单。


## 音效运行时 manifest 与本机设置

`data/audio/sfx_manifest.json` 为 `schema_version: 1` 的独立表现清单，不进入 ConfigRegistry 战斗 Definition、BattleState 或战斗随机源。

- `assets: Dictionary<工单素材ID, SoundAsset>`：`path` 只能位于 `res://assets/audio/sfx/runtime/`；`bus` 为 Combat/Alerts/UI/Ambience；`loop` 为布尔值；`gain_db`、`priority`、`duration` 为混音和播放元数据；`channels`、`crossfade_frames`、`source_sha256`、`sha256` 保存派生验收信息。资产ID复用采用清单中的稳定ID，不从文件名猜语义。
- `weapons` 逐武器ID记录 `fire/mount_type/caliber_mm/aviation_payload`。口径仅用于离线选择声音；胡德未标定口径的“护航副炮”显式使用轻炮族，不虚构武器规则口径。Aviation 的 fire 登记为 A01，但运行时出击由波次独占，旧 WeaponFired 不播放。
- `ships` 逐角色ID记录装备引用和技能ID，`skills` 逐技能ID记录 `sound: null` 与取消原因；实际技能武器事实正常映射。
- `requirements` 和 `cancelled_asset_ids` 是采用范围快照；不因有共享素材恢复已取消触发。
- `mix` 拥有短声部/预留提示声部、环境/飞机循环上限、普通/11v11聚合窗和可听距离、重声部上限、区域受击聚合格、循环淡化、背景压低与恢复，以及低氧/旗舰危急/时间提示的表现阈值。不得改变允许下潜、伤害、侦查或胜负规则。当前精确初值见JSON，人工混音验收后可调整。

本机 `tiny_sea_war_settings.cfg` 的 `audio` 节保存 `Master/Music/Combat/Alerts/UI/Ambience` 的0–1线性音量、`muted`、`music_muted` 和 `frequent_ui`；`music_muted` 只静音 Music 总线。菜单提供总音量、音乐与四类音效音量；战术暂停提供总音量/静音。频繁操作确认可关闭，命令拒绝仍保留。保存保留其他节，写入失败保持会话选择并显示失败。缺字段使用默认；坏资源静默并诊断，不阻塞出击。Headless默认只调度，不自动加载音频或创建播放节点。


## 标题音乐运行时清单

`data/audio/music_manifest.json` 是独立 Presentation 清单，`schema_version: 1`，不进入战斗注册表、状态或随机源。

- `main_theme_id` 引用冷启动主题；缺失时从可用曲目中选首曲。`scene_fade_seconds` 为 `(0,10]` 有限秒数，只用于场景进入/退出。
- `tracks[]` 的 `id/title/path/duration` 为稳定ID、显示名、`res://assets/audio/music/runtime/*.ogg` 路径和实测正时长。ID唯一、路径不允许上级跳转；失效项逐项跳过，耗尽时保持安静。
- `loop_start/loop_end` 定义合法循环范围，当前为完整已采用曲目；`resume_points[]` 为递增有限乐句秒数，均小于实测曲目时长。尚无人工验收点时保持空数组，返回菜单按 `50` 进入下一首。
- `source_sha256/sha256/gain_db/integrated_lufs/true_peak_dbfs/loudness_range_lu` 记录源到编码版对应关系、恒定响度调整和编码后测量。`human_loop_status/human_mix_status` 记录人工验收，不能由自动检测改为通过。
- 加载时校验类型、路径、时长、循环与恢复点；真实设备加载后还检查资源类型和引擎时长。Ogg自身关闭循环；自动轮播在完整曲尾、单曲循环在循环终点、手动下一首在点击时硬切。切歌先立即停止所有旧声部，再以完整曲目增益播放新流，保持标题暂停状态；同一时刻最多播放一路。旧 `crossfade_seconds` 元数据退出正式清单及构建工具，加载不再消费。

会话内保存队列、标题暂停和离开位置，不跨重启保存。播放模式另存于本机 `tiny_sea_war_settings.cfg` 的 `music.playback_mode = sequence | shuffle | single`；`music.rotation_mode = sequence | shuffle` 保存解除单曲循环时的返回方式。缺字段或非法类型/枚举回退shuffle，保存保留audio/menu/display等其他节。模式立即生效，写入失败保留会话选择并向UI显示失败；冷启动仍先播主主题，使用保存的播放模式。标题暂停只冻结标题播放器；Music音量及音乐静音经SoundManager共享本机设置即时生效。无图形进程不加载音频流、不创建音乐播放器、不自动推进音乐时钟。

## 战斗音乐运行时清单

`data/audio/battle_music_manifest.json` 复用标题清单的schema版本、scene_fade_seconds、资源/时长/循环/响度/哈希校验；无main_theme_id。`tracks[].category` 必须为 `battle | victory | defeat`，其他类别不进入战斗池。曲库与标题队列分离，播放器及Music总线共用。

当前Presentation映射：`level.tutorial.*`优先watchful_route/gentle_companions，`level.challenge.l05`优先finale_distant_decisive，其余使用排除finale的五首battle曲；专用资源缺失回退常规池，多候选排除上一局曲目。ID均为catalog中的稳定ID；资源加载失败跳过候选，胜负类别不能互相替代。

每次成功创建场景战斗开始新音乐会话，公开快照phase/result驱动暂停及结算；结果复用BattleResultPresentation分类且每局一次。战斗暂停不停止音乐，线性音量平滑降至0.35；标题暂停与标题播放模式不影响局内。无验收区段时battle按完整时长循环，result播完后安静；human_loop_status/human_mix_status保持pending，不将完整循环视为主体或余韵验收。无图形仅显式advance推进测试时钟，不加载流或创建声部。
