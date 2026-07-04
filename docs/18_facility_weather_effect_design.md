# 设施与天气效果策划

## 1. 文档目标

本文统一整理岸基设施、设施状态、支援任务、水雷、局部环境标识，以及 5 种天气 × 4 个时段的全局战斗效果。目标是让玩家看到的海面、天气层和地图标识，与 Domain 实际采用的侦查、机动、命中和航空条件保持一致。

本文负责玩法含义、信息优先级、首轮数值和组合体验；程序契约见 `docs/35_scene_combat_domain_design.md`，场景表现参数见 `docs/43_scene_art_design.md`，UI 通用规格见 `docs/44_ui_art_design.md`。

核心原则：

- **所见即规则**：关卡使用的 `ocean_palette` 同时确定天气画面与全局战斗条件，不能出现雷雨画面配晴天规则。
- **全局基线、局部变化**：时间天气决定整张地图的基础条件，海雾、飑线、高海况、背风水域等局部区域在此基础上叠加。
- **图标表达语义，不代替场景**：天气层负责氛围和空间感，图标负责快速确认规则边界、设施类型和当前状态。
- **环境创造选择，不制造失控**：天气使用确定修正，不加入随机漂移、随机失火或每 Tick 抖动。
- **玩家与 AI 对称**：双方读取同一全局条件、公开环境区域和设施状态，不给 AI 隐藏天气加成。

---

## 2. 信息层级

场景相关信息按四层表达：

| 层级 | 主要内容 | 表达方式 | 玩家问题 |
| --- | --- | --- | --- |
| 全局时间天气 | 晴朗、多云、阴云、雨、雷雨；白天、凌晨、黄昏、夜间 | 海面、云影、雨线、雾气、闪电；海域名称 | “整场战斗的基础条件是什么？” |
| 局部环境 | 海雾、飑线、高海况、背风、月光、强流、潮汐 | 场景遮罩、边界、小地图环境标识 | “进入这里会发生什么？” |
| 设施类型 | 观察站、岸炮、补给、机场、雷达、通信、水雷控制、维修 | 世界设施资产、小地图设施图标 | “这里能提供什么能力？” |
| 状态与任务 | 激活、压制、恢复、摧毁、服务、侦察、巡逻、空袭、水雷状态 | 状态覆盖层、事件图标、任务图标 | “它现在是否可用，正在做什么？” |

全局天气不使用覆盖全地图的巨大规则边框；局部环境必须显示可判断的边界。设施图标保持类型轮廓，阵营和运行状态由颜色、状态覆盖层和事件提示补充，不为同一设施复制多套难以记忆的主体图标。

---

## 3. 设施图标与效果

### 3.1 八类设施

| 设施 | UI 语义/文件 | 场景资产语义 | 当前战斗效果 |
| --- | --- | --- | --- |
| 海岸观察站 | `ui_marker_facility_coastal_observation_post.png` | `facility.coastal_observation_post.*` | 激活后成为固定光学观察源，范围 1150；受视距、海雾、昼夜和岛岸遮挡影响 |
| 岸防炮 | `ui_marker_facility_coastal_battery.png` | `facility.coastal_battery.*` | 支持敌方锁定激活/己方休眠待激活；耐久与防护引用厌战经典战列舰，单座联装炮引用其 381mm AP/HE；压制或通信失效时停火 |
| 前沿补给点 | `ui_marker_facility_forward_supply_point.png` | `facility.forward_supply_point.*` | 中立休眠，需先占领；同阵营舰低速进入单泊位并连续服务 7 秒，完成装填并缩短 12 秒技能冷却，离泊/受击/压制会中断 |
| 近岸机场 | `ui_marker_facility_coastal_airfield.png` | `facility.coastal_airfield.*` | 敌方激活、不可占领/摧毁；提供侦察、战斗机巡逻和空袭，准备阶段随机场失效取消，已离场任务继续；受天气、冷却、次数及通信限制 |
| 雷达站 | `ui_marker_facility_radar_station.png` | `facility.radar_station.*` | 敌方休眠，由关卡事件激活；1400 范围精确位置雷达接触，不受光学倍率或岛岸阻挡，显式雷达隐身可规避 |
| 通信站 | `ui_marker_facility_communication_station.png` | `facility.communication_station.*` | 作为机场和岸炮的显式依赖；失效时关闭依赖能力，不直接造成伤害或侦查 |
| 水雷控制站 | `ui_marker_facility_mine_control_station.png` | `facility.mine_control_station.*` | 控制绑定雷区的启停和所有权；压制使雷区休眠，摧毁使其失效 |
| 港口维修泊位 | `ui_marker_facility_repair_berth.png` | `facility.repair_berth.*` | 9 秒服务后恢复最大 HP 的 28%，单场最高恢复到最大 HP 的 80% |

设施世界资产位于 `assets/environment/facilities/`，UI 标识位于 `assets/ui/processed/battle/terrain/`，正式语义清单为 `assets/environment/facilities/facility_asset_manifest.json`。

设施操作按职责组合五类模式：区域控制负责取得所有权，靠泊服务负责补给与维修，远程指挥负责机场任务与布雷，自动运行负责岸炮、观察、雷达和通信，战斗处置负责公共攻击产生的压制与摧毁。普通玩家语义统一显示为“控制/占领”；`Activate` 不作为水面舰通用操作，只保留给关卡初始化、脚本事件或明确标记的特殊设施。

设施生命、所有权、运行和交互分别表达：生命为 `Alive | Destroyed`，所有权使用阵营 ID，运行态为 `Dormant | Active | Suppressed | Silent | Disabled`，交互态为 `Idle | Controlling | Contested | Moored | Docked | Servicing | Interrupted`。依赖设施必须同时处于可运行状态并属于同一阵营；压制不改变所有权，恢复时重新检查依赖。不可摧毁设施在数据声明的 HP 下限停止掉血，但继续累计压制伤害并提供受击、伤害受限和压制反馈。

### 3.2 状态与事件图标

| 状态/事件 | 图标 | 使用条件 |
| --- | --- | --- |
| 激活 | `ui_icon_facility_active.png` | 激活完成或设施恢复运行 |
| 夺取 | `ui_icon_facility_seize.png` | 夺取交互开始、进行或所有权变化 |
| 压制 | `ui_icon_facility_suppressed.png` | 能力暂时关闭、压制倒计时进行中 |
| 恢复 | `ui_icon_facility_recovered.png` | 压制结束并恢复到此前运行态 |
| 摧毁 | `ui_icon_facility_destroyed.png` | HP 归零并进入不可逆摧毁态 |
| 服务中断 | `ui_icon_facility_service_interrupted.png` | 舰船离开、受击或设施失效导致服务取消 |
| 服务完成 | `ui_icon_facility_service_complete.png` | 补给或维修效果已经结算 |

场景设施额外使用 `facility.state.active/suppressed/offline/servicing` 等覆盖层。事件图标只短暂提示结果，状态覆盖层负责持续表达，二者不能互相替代。

### 3.3 机场任务与水雷

| 类别 | 图标 | 当前效果 |
| --- | --- | --- |
| 航空侦察 | `ui_icon_mission_air_recon.png` | 到达后生成半径 620、持续 18 秒的航空观察区 |
| 战斗机巡逻 | `ui_icon_mission_fighter_patrol.png` | 生成半径 520、持续 22 秒的防护区，区内敌方航空命中 `-0.28` |
| 空袭 | `ui_icon_mission_airstrike.png` | 到达后使用正式航空武器连续结算 3 次 |
| 已知雷区 | `ui_marker_minefield_known.png` | 显示已掌握边界；驶入危险区域触发 420 伤害 |
| 未知雷区 | `ui_marker_minefield_unknown.png` | 仅用于全知调试或未来模糊情报，不向普通阵营泄露真实边界 |
| 失效雷区 | `ui_marker_minefield_disabled.png` | 雷区已被控制站关闭或摧毁，不再触发 |
| 安全航道 | `ui_marker_minefield_safe_channel.png` | 雷区内明确不触发水雷的通行带 |

---

## 4. 局部环境标识与效果

| 环境 | 标识 | 场景资源 | 当前战斗效果 |
| --- | --- | --- | --- |
| 海雾 | `ui_marker_environment_sea_fog.png` | `sea_fog_mask/edge/detail` | 局部光学能见度乘以 `0.62`；不阻挡移动、炮弹或鱼雷 |
| 飑线 | `ui_marker_environment_rain_squall.png` | `rain_squall_mask/edge` | 局部光学能见度乘以 `0.72`，航空条件至少为 `Restricted`，风速 `+6` 并放大鱼雷角误差 |
| 高海况 | `ui_marker_environment_high_sea.png` | `high_sea_foam_mask` | 将局部海况向 4 级插值，最终海况影响航速、命中、航空和鱼雷角误差 |
| 背风水域 | `ui_marker_environment_lee_water.png` | `lee_water_mask` | 最终海况降低 2 级，为恶劣天气下的近岸稳定航路，并缓解鱼雷角误差 |
| 月光水域 | `ui_marker_environment_moonlit_lane.png` | `moonlit_lane_mask` | 局部光学能见度乘以 `1.18`，不穿透岛岸，不创造观察者 |
| 强流 | `ui_marker_environment_strong_current.png` | `strong_current_streak_tile` | 按方向施加基础强度 9 的流速向量，影响舰船、鱼雷和路线成本 |
| 潮汐水域 | `ui_marker_environment_tide.png` | `active_illumination_mask` | `Flood/High` 可进入，`Ebb/Low` 禁止新进入但允许已在区内单位撤离 |
| 区域边界 | `ui_marker_environment_zone_boundary.png` | 程序边线 | 表达规则边界，不代表独立效果 |
| 移动趋势 | `ui_marker_environment_movement_trend.png` | 程序方向提示 | 表达公开漂移方向和短期趋势，不提供未来精确位置 |

局部天气与全局天气采用叠加关系。例如“雨夜中的海雾”先得到雨夜基础能见度，再乘海雾修正并受最低能见度保护；“雷雨中的背风水域”降低最终海况，但不会消除雷雨本身的低能见度和航空限制。

---

## 5. 全局天气效果

全局天气由 `WeatherBattleProfile` 提供基础海况、能见度、通用武器命中和航空条件。数值是 MVP 首轮基线。

| 天气 | 基础海况 | 风速 | 鱼雷 sigma 倍率 | 光学倍率 | 额外命中 | 航空延迟 | 航空条件 | 战术定位 |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | --- | --- |
| 晴朗 | 1 | `2` | `1.00` | `1.00` | `0.00` | `1.00` | Normal | 信息充分、机动稳定，作为标准基线 |
| 多云 | 2 | `4` | `1.35` | `0.96` | `0.00` | `1.04` | Normal | 轻微压低远距离发现，雷击离散小幅增加 |
| 阴云 | 3 | `7` | `1.88` | `0.88` | `-0.02` | `1.10` | Normal | 视距下降并进入 3 级海况，鼓励接近和稳健航路 |
| 雨 | 3 | `9` | `2.00` | `0.76` | `-0.05` | `1.25` | Restricted | 接触距离缩短、航空变慢，雷击可靠性下降 |
| 雷雨 | 5 | `15` | `3.00` | `0.58` | `-0.10` | `1.60` | Severe | 高海况、强风、低能见度和航空受限并存，背风与设施争夺更关键 |

最终海况再应用统一档位：

| 最终海况 | 航速倍率 | 追加命中 | 追加航空延迟 | 航空条件下限 |
| ---: | ---: | ---: | ---: | --- |
| 0-2 | `1.00` | `0.00` | `1.00` | Normal |
| 3 | `0.96` | `-0.04` | `1.10` | 不变 |
| 4 | `0.88` | `-0.10` | `1.30` | Restricted |
| 5 | `0.80` | `-0.16` | `1.60` | Severe |

因此天气本身的观测/操作困难和海况造成的平台困难可以同时存在。环境上下文本身仍由确定规则相加或相乘；唯一新增随机项是鱼雷发射瞬间的独立高斯角误差，它使用战斗固定种子，抽样结果可复现，航行途中不重复抽取。

---

## 6. 时段效果

时段只对光照相关信息和少量操作条件做二级修正，不改变天气身份。

| 时段 | 光学倍率 | 额外命中 | 航空延迟 | 设计含义 |
| --- | ---: | ---: | ---: | --- |
| 白天 | `1.00` | `0.00` | `1.00` | 标准可见度和操作条件 |
| 凌晨 | `1.03` | `0.00` | `1.00` | 较浅、较亮、欣欣向荣；提供很小的光学观察优势 |
| 黄昏 | `0.90` | `-0.01` | `1.05` | 黄红昏沉与低角度光照降低辨识，效果克制 |
| 夜间 | `0.72` | `-0.03` | `1.15` | 显著缩短光学接触距离，月光区和观察站价值上升 |

时段不改变设施 HP、服务收益、水雷伤害和潮汐周期。观察站仍受时段能见度影响；雷达未来使用独立传感器规则，不继承光学倍率。

---

## 7. 二十种组合体验

每个组合的最终数值由“天气 × 时段 × 最终海况 × 局部区域”计算，以下表格描述玩家应感知到的主要差异。

| 天气 | 白天 | 凌晨 | 黄昏 | 夜间 |
| --- | --- | --- | --- | --- |
| 晴朗 | 标准会战，远距离信息完整 | 最明亮清新的侦查窗口 | 轻度昏沉，远射略受影响 | 海况稳定但视距明显缩短，月光航路有价值 |
| 多云 | 轻度遮光的常规战 | 明亮冷青、信息仍较充分 | 云影与暮色叠加，接敌距离收缩 | 稳定海况下的隐蔽机动战 |
| 阴云 | 中海况与压暗视距并存 | 明亮时段缓和阴云压迫 | 昏暗与中海况共同鼓励接近 | 低可见度、中海况，观察站价值明显提高 |
| 雨 | 雨线可见、航空延迟、近距离交战增多 | 较亮雨幕，仍有清楚方向感 | 暖暗雨幕，目标辨识进一步下降 | 雨夜伏击，航空支援慢且接触短暂 |
| 雷雨 | 高海况正面压制，背风路线成为核心 | 冷亮闪电与明亮底色形成短促对比 | 昏沉风暴，机动和远射均显著受限 | 最严苛组合，最低能见度保护生效，航空条件 Severe |

20 种组合不能只靠数值区分：晴朗依赖闪光与疏云，多云依赖成片云影，阴云依赖低云压暗，雨依赖雨线与涟漪，雷雨依赖风暴云、白沫和间歇闪电；时间继续控制亮度、色温和反光。表现参数仍以 `data/environments/ocean_palettes.json` 为真源。

---

## 8. 组合与覆盖规则

一次单位位置的环境结果按以下顺序生成：

```text
Ocean palette ID
  -> 天气基础条件
  -> 时段光照条件
  -> 全图风、潮汐和关卡参数
  -> 局部海雾/飑线/高海况/背风/月光/强流
  -> 最终海况档位
  -> TerrainContext
  -> 侦查、移动、武器、航空、设施和 AI
```

具体叠加规则：

- 光学倍率按乘法叠加，最低为 `0.45`，最高为 `1.25`。
- 武器命中修正按加法叠加。
- 航空延迟按乘法叠加，航空条件取最严重等级。
- 最终海况先由天气基础和局部升降得到，再只应用一次海况档位。
- 背风区只降低海况，不清除雨、雷雨、夜间或海雾造成的其他修正。
- 月光区只提高合法光学观察效率，不穿透硬地形，也不暴露没有观察源的目标。
- 同一局部 `effect_id` 重叠时只取最强区域，不因重复铺设多次叠加。

---

## 9. 玩家反馈与 AI

- HUD 的海域名称继续显示当前 20 套组合名称。
- 小地图在局部环境多边形中心显示对应环境标识，并保留低对比边界。
- 设施小地图图标显示设施类型，世界覆盖层显示 Active、Dormant、Suppressed、Destroyed 等持续状态。
- 关键状态变化通过事件图标和战斗日志反馈；不要求玩家仅从设施贴图猜测规则。
- AI 使用最终 `TerrainContext` 评估接触、路线、背风、潮汐、机场合法性和雷区，不读取 Shader 的雨线、闪电帧或屏幕亮度。

后续 UI 可增加天气效果详情浮层，但首轮实现不能因为缺少浮层而隐藏局部环境边界或错误显示设施状态。

---

## 10. 数据与验收

运行时规则真源：

```text
data/environments/ocean_battle_condition_definitions.json
data/environments/environment_zone_definitions.json
data/facilities/facility_definitions.json
data/facilities/support_mission_definitions.json
data/facilities/minefield_definitions.json
```

表现真源：

```text
data/environments/ocean_palettes.json
assets/environment/weather/
assets/environment/weather/zones/
assets/environment/facilities/
assets/ui/processed/battle/terrain/
```

验收要求：

- 20 个正式 palette 均能解析为唯一的天气与时段条件。
- 正式战斗在创建时锁定 palette；美术 QA 的临时画面切换不改写战斗规则。
- `day_clear`、`cloudy`、`dusk` 旧别名分别保持为 `clear_day`、`cloudy_day`、`cloudy_dusk`。
- 开阔海域即使没有局部环境区，也会受到时间天气规则影响。
- 港湾局部海雾、飑线、背风和月光在全局条件上正确叠加。
- 雷雨夜达到最低光学倍率、5 级海况和 Severe 航空条件；凌晨晴朗具有轻微光学优势。
- 环境标识、设施图标和规则语义可以一一追溯，不存在已显示但无效果或有效果但无合法反馈的关键对象。
