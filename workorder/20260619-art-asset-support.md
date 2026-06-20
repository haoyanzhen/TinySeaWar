# 美术资产支持需求

日期：2026-06-19
主题：动画、VFX 绑定、炮弹/鱼雷/舰载机攻击表现支持

## 背景

当前程序已完成基础战斗规则、操作闭环和 HUD。下一阶段将接入角色动画状态机、VFX 绑定、炮弹/鱼雷/舰载机攻击效果。现有角色动画、VFX 和绑定点已可支持第一版接入，但通用弹体、播放参数和表现映射契约仍需补充。

状态标记：

- [x] 已有运行时资源、配置或程序接口支撑，并已通过当前加载/测试检查。
- [ ] 尚未完成，或只有局部覆盖但缺少完整契约/运行时闭环。

## 需要美术方支持的资源

### 角色美术侧补充

现有七名测试角色的角色资产契约已可支持第一版接入；本工单不要求重新生成角色立绘、头像、基础舰装或五态动画。角色美术侧需要补充的是“现有角色资产如何被程序稳定读取和复用”的语义说明：

- [x] 为每名已接入角色补齐绑定点语义映射表，将试产阶段点名统一映射到本工单的标准语义。
- [x] 为每名已接入角色补齐 VFX role 映射表，将角色专属 role 对齐到公共表现语义，例如 `muzzle_flash.large`、`wake.destroyer_fast`、`torpedo.trail.surface`、`aircraft.path`。
- [x] 航母角色只负责提供甲板、起飞点、回收点、角色专属航空演出覆盖；舰载机单位、编队、受击、坠落和拦截优先走公共航空资产。
- [x] 潜艇角色只负责提供潜艇本体、潜航阴影/气泡/声呐等专属覆盖；潜射鱼雷实体、潜射鱼雷尾迹和水下命中优先走公共潜艇攻击资产。
- [x] 若角色已有可复用的炮焰、尾迹、水花、装甲火花等素材，可作为公共资产生成参考，但不直接把角色目录当作全局真源。

### 高优先级

- [x] 通用炮弹飞行贴图：小口径、中口径、大口径三档。
- [x] 通用炮弹拖尾贴图或可平铺 shell trail 规范。
- [x] 通用鱼雷实体贴图：水面鱼雷、潜射鱼雷两档。
- [x] 通用鱼雷尾迹粒子元素：泡沫点、短浪线、低亮光点和小水花元素。
- [x] 通用命中水花、落水水花、装甲火花。
- [x] 统一并补齐角色炮口、鱼雷口、航迹等绑定点。

### 中优先级

- [x] 通用防空弹幕、航空炸弹、航空鱼雷表现。
- [x] 舰载机单位贴图和编队标识。
- [x] 舰载机受击、坠落、返航、被防空拦截效果。
- [x] 技能释放短时 cut-in 或角色局部演出规则。

### 低优先级

- [x] 多帧复杂爆炸序列：本轮按 MVP 决策改为 2-4 帧固定短动画，复杂长序列后置。
- [x] 多天气专属 VFX：本轮明确后置，当前公共 VFX 保持天气无关。
- [x] 高级沉没动画：本轮明确后置，当前不作为接入阻塞项。

## 需要补充的规格说明

每个 VFX 或弹体表现建议提供：

- [x] `duration`：推荐播放时长。
- [x] `fps` 或 `frame_count`：帧率或帧数。
- [x] `loop`：是否循环。
- [x] `anchor`：锚点语义。
- [x] `z_layer`：推荐渲染层级。
- [x] `rotation_mode`：是否跟随发射方向、目标方向或屏幕方向。
- [x] `scale`：推荐缩放基准。
- [x] `follow_owner`：是否跟随角色或投射物。
- [x] `blend_mode`：普通、加色或其他混合方式。

## 绑定点命名建议

后续新资产建议统一以下语义。旧角色资产如果已经存在不同点名，不必重切图片，但需要在角色配置或映射表中补齐到这些标准语义：

- [x] 炮口：`muzzle_01`、`muzzle_02`、`muzzle_group`
- [x] 鱼雷口：`torpedo_port_01`、`torpedo_port_02`
- [x] 航迹：`wake_origin`
- [x] 舰载机起飞：`aircraft_launch_01`、`aircraft_launch_02`
- [x] 舰载机回收：`aircraft_recovery`
- [x] 技能/扫描：`scan_origin`、`skill_origin`
- [x] 舰装挂点：`rig_mount`

### 当前测试角色绑定点对齐重点

- [x] 企业号：保留 `aircraft_launch_01`、`aircraft_launch_02`、`aircraft_recovery`，补充公共航空 profile 引用。
- [x] 海狮号：将单点 `torpedo_port` 映射为 `torpedo_port_01`，保留 `sonar_origin`、`periscope_point`、`wake_origin`。
- [x] 兴登堡号：保留 `muzzle_01`、`muzzle_02`、`turret_mount_01`、`fire_control_point`，映射到重巡中大口径炮击 profile。
- [x] 岛风号：保留 `torpedo_port_01`、`torpedo_port_02`、`wake_origin`，补充高速鱼雷和驱逐高速航迹 profile 引用。
- [x] 阿芙乐尔号：保留 `muzzle_01`、`searchlight_point`，补充轻巡炮击、防空/支援光束 profile 引用。
- [x] 厌战号、俾斯麦号：保留 `muzzle_01`、`muzzle_02`、`muzzle_group` 和炮塔挂点，映射到战列大口径炮击、重型水柱和装甲火花 profile。

## VFX role 语义建议

角色目录中的 VFX role 应按“角色专属名 -> 公共表现语义 -> 播放 profile”的方式接入。建议先支持以下公共语义：

- [x] 炮击：`muzzle_flash.small`、`muzzle_flash.medium`、`muzzle_flash.large`、`shell.trail.short`、`shell.trail.medium`、`shell.trail.long`
- [x] 命中：`impact.water.small`、`impact.water.medium`、`impact.water.large`、`impact.armor.spark`、`impact.armor.flash`
- [x] 鱼雷：`torpedo.trail.surface`、`torpedo.trail.submerged`、`torpedo.warning.line`、`torpedo.warning.fan`
- [x] 航空：`aircraft.path`、`aircraft.launch_trail`、`aircraft.landing_trail`、`aircraft.airstrike_area`、`aircraft.intercept_hit`、`aircraft.fall`
- [x] 防空：`aa.tracer.light`、`aa.tracer.medium`、`aa.burst.small`
- [x] 潜艇：`submarine.underwater_shadow`、`submarine.bubble_trail`、`submarine.sonar_pulse`
- [x] 航迹：`wake.destroyer_fast`、`wake.cruiser`、`wake.battleship_heavy`、`wake.carrier_wide`、`wake.submarine_low`

## 程序侧配合调整

程序侧将增量扩展资产接口，不重做现有目录：

- [x] 增加动画状态列表查询。
- [x] 增加 VFX role 列表查询。
- [x] 增加单个绑定点查询。
- [x] 增加通用 projectile visual 查询。
- [x] 增加 weapon visual 映射查询。

建议新增配置目录：

- [x] `data/visuals/projectile_visuals.json`
- [x] `data/visuals/weapon_visuals.json`
- [x] `data/visuals/vfx_playback_profiles.json`

## 验收目标

第一阶段验收：

- [x] 角色可在 `idle / move / attack / hit / firepower` 状态间切换。
- [x] 火炮开火能从绑定点播放炮口火光和拖尾。
- [x] 火炮命中或落水能播放水花/装甲火花。
- [x] 鱼雷能显示实体和尾迹。
- [x] VFX 播放不依赖硬编码角色名。

第二阶段验收：

- [x] 舰载机可从航母起飞、编队飞行、攻击、返航。
- [x] 防空拦截有基础表现。
- [x] 航空攻击与水面/潜艇攻击使用统一表现契约。

## 补完结果与剩余说明

本轮已补齐工单的运行时接入缺口：公共战斗 VFX/投射物资产、`data/visuals` 三类配置、七名测试角色绑定点语义映射和 VFX role 映射均已形成可查询契约。

输出位置：

- `assets/vfx/combat/`：公共炮弹、鱼雷、航空、防空、命中、反潜、航迹和技能 VFX 资产。
- `data/visuals/projectile_visuals.json`：公共投射物与舰载机视觉定义。
- `data/visuals/weapon_visuals.json`：角色武器到公共表现 profile 的映射。
- `data/visuals/vfx_playback_profiles.json`：VFX 播放参数。
- `assets/characters/qa/character_runtime_semantic_mappings.md`：七名测试角色绑定点和 VFX role 的标准语义映射。

低优先级的复杂长序列爆炸、多天气专属 VFX 和高级沉没动画已按 MVP 决策后置，不再作为本工单接入阻塞项。
