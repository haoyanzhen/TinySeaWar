# 敌方 AI 量化与实现规格

## 1. 文档目标

本文将以下四项 AI 设计转换为可以直接编码、配置和测试的首轮量化规格：

- 目标评分。
- 模式切换。
- 技能释放阈值。
- 地图边界处理。

行为语义见 `docs/16_enemy_ai_behavior_design.md`，实现可行性与裁剪见 `docs/17_enemy_ai_implementation_feasibility.md`。

本文数值是首轮原型基线，不是最终平衡。实现后应通过固定种子测试和批量模拟调参。

## 2. 统一量化原则

### 2.1 归一化

所有输入先转换到 `[0, 1]`，最终效用统一为 `[0, 100]`：

```text
clamp01(x) = clamp(x, 0, 1)
score100(x) = clamp(100 * x, 0, 100)
```

好处：

- 不依赖当前射程、地图大小和 HP 的绝对尺度。
- 不同模式可以复用同一套切换阈值。
- 调试日志可以直接比较各分量。

### 2.2 硬门槛与软评分分离

先做硬门槛，再评分。硬门槛失败的候选不得通过高权重补回来。

典型硬门槛：

- 目标存活、阵营合法、当前可见。
- 武器/技能目标类型合法。
- 模式在该舰允许集合中。
- 实际提交攻击或技能命令时满足射程、射角和冷却要求；目标评分本身可以在武器装填期间继续保持目标。
- 移动目标位于合法地图区域。

评分只比较多个合法候选的优劣。

### 2.3 确定性

- 同分使用稳定实体 ID 决胜。
- 首轮不在评分中加入随机扰动。
- 反应差异用决策间隔和确认次数表达，不用随机犯错。
- 所有评分分量和最终选择可写入调试事件。

## 3. 目标评分

### 3.1 两类目标

AI 必须区分：

- `task_target_id`：机动任务目标，可以是射程外的已发现敌舰、保护对象或残影搜索区。
- `attack_target_id`：当前武器攻击目标，必须满足可见性和武器合法性。

二者分别评分。失去侦查时立即清除 `attack_target_id`；`task_target_id` 只能转为最后已知位置任务，不能继续读取目标实时位置。

### 3.2 目标分量

每个合法目标计算以下分量：

| 分量 | 符号 | 范围 | 首轮计算 |
|---|---|---:|---|
| 模式任务价值 | `M` | 0-1 | 查模式—目标类型权重表；旗舰取模式的旗舰覆盖值 |
| 对当前任务的威胁 | `T` | 0-1 | 距保护对象/自身的接近程度、近期伤害和突破方向 |
| 武器适配 | `W` | 0-1 | 当前可用武器对目标类型/装甲厚度的适配 |
| 距离带适配 | `R` | 0-1 | 目标距离与模式期望射程比例的接近程度 |
| 击沉机会 | `K` | 0-1 | `1 - target_hp_ratio` |
| 编组集火 | `F` | 0-1 | 是当前合法编组目标则为 1，否则为 0 |
| 追击成本 | `P` | 0-1 | 距离、转向和脱队成本 |
| 过量伤害 | `O` | 0-1 | 已分配重武器预计伤害 / 目标剩余 HP |

### 3.3 分量公式

#### 模式任务价值 `M`

首轮类型权重：

| 模式 | 驱逐 | 轻巡 | 重巡 | 战列 | 航母 | 潜艇 | 旗舰覆盖值 |
|---|---:|---:|---:|---:|---:|---:|---:|
| `VanguardLine` | 0.95 | 0.75 | 0.45 | 0.35 | 0.55 | 1.00 | 0.65 |
| `TorpedoFlank` | 0.35 | 0.50 | 0.65 | 0.90 | 0.95 | 0.20 | 1.00 |
| `FlagshipRaid` | 0.20 | 0.30 | 0.45 | 0.75 | 0.95 | 0.10 | 1.00 |
| `EscortScreen` | 0.70 | 0.55 | 0.45 | 0.35 | 0.40 | 1.00 | 0.60 |
| `GunlineSupport` | 0.35 | 0.55 | 0.80 | 0.95 | 0.80 | 0.15 | 0.90 |
| `CarrierStandoff` | 0.45 | 0.65 | 0.75 | 0.85 | 0.90 | 0.25 | 1.00 |

```text
M = max(class_weight, flagship_override if target.is_flagship else 0)
```

`EscortScreen` 的最终价值仍主要由威胁 `T` 决定；类型权重只用于威胁相近时排序。

#### 威胁 `T`

```text
proximity = clamp01(1 - distance_to_protectee / threat_radius)
recent_damage = clamp01(damage_from_target_last_6s / (protectee_max_hp * 0.15))
route_threat = 1 if target is between protectee and main threat axis else 0

T = clamp01(
  0.55 * proximity
  + 0.30 * recent_damage
  + 0.15 * route_threat
)
```

- 没有保护对象时，`protectee` 使用自身。
- 第一版若尚未保存按来源近期伤害，`recent_damage` 暂取 0，并把 proximity 权重临时提高到 0.75。
- `threat_radius` 推荐为保护对象主要武器射程与自身侦查距离的较大值。

#### 武器适配 `W`

首轮不重复伤害公式，只使用已经配置的目标类型和 `armor_damage_modifiers`：

```text
armor_fit = clamp01((armor_modifier - 0.20) / 1.05)
reload_ready = clamp01(1 - reload_remaining / base_reload_time)
weapon_fit = armor_fit * (0.60 + 0.40 * reload_ready)

W = max(所有能攻击该目标类型的武器 weapon_fit)
```

- `armor_modifier = 1.25` 时 `armor_fit = 1`。
- `armor_modifier <= 0.20` 时视为不适配。
- 第二阶段可由 `DamageService` 提供只读预估接口，但不得在 AI 中复制伤害公式。

#### 距离带适配 `R`

```text
distance_ratio = distance / primary_effective_range
R = clamp01(1 - abs(distance_ratio - preferred_range_ratio) / range_band_half_width)
```

建议：

| 模式 | `preferred_range_ratio` | `range_band_half_width` |
|---|---:|---:|
| `VanguardLine` | 0.60 | 0.45 |
| `TorpedoFlank` | 0.82 | 0.30 |
| `FlagshipRaid` | 0.72 | 0.35 |
| `EscortScreen` | 0.55 | 0.50 |
| `GunlineSupport` | 0.75 | 0.30 |
| `CarrierStandoff` | 0.85 | 0.45 |

若用于机动任务目标，允许距离超过射程；若用于攻击目标，最终仍必须经过武器射程校验。

#### 追击成本 `P`

```text
distance_cost = clamp01(distance / (primary_effective_range * 1.50))
turn_cost = abs(shortest_angle_to_target) / PI
leash_cost = clamp01(distance_from_group_slot / mode_leash_distance)

P = clamp01(0.45 * distance_cost + 0.30 * turn_cost + 0.25 * leash_cost)
```

#### 过量伤害 `O`

```text
O = clamp01(assigned_heavy_damage / max(target_current_hp, 1))
```

第一版不必精确预测所有在途伤害：

- 每个已发射主炮轮次登记一次保守预计伤害。
- 每个鱼雷波或航空波登记一次预计伤害。
- 自动小口径武器不参与预留。
- 目标隐藏或沉没时清除预留。

### 3.4 最终目标分

默认标准难度：

```text
target_score = clamp(
  100 * (
    0.30 * M
    + 0.22 * T
    + 0.18 * W
    + 0.12 * R
    + 0.10 * K
    + 0.08 * F
    - 0.12 * P
    - 0.12 * O
  ),
  0,
  100
)
```

说明：

- 正向权重合计为 1，便于阅读。
- `P` 和 `O` 是额外惩罚，最多各扣 12 分。
- 模式可以覆盖权重，但正向权重必须归一化为 1。
- 首轮权重范围建议限制在 `0-0.45`，避免单项完全支配结果。

### 3.5 攻击目标切换

推荐基线：

```text
target_minimum_hold = 2.0s
target_switch_margin = 12 points
target_switch_confirmations = 2
target_switch_cooldown = 1.5s
```

切换规则：

1. 当前目标非法、沉没或失去侦查：立即清除，不使用滞回。
2. 最短保持时间内不切换，紧急护航目标除外。
3. 新目标分必须至少高于当前目标 12 分。
4. 连续两次 0.5 秒决策都满足才切换。
5. 切换后 1.5 秒内不再次主动切换。

这套滞回能避免两个相近目标每个决策周期互相抢占锁定。

## 4. 模式切换

### 4.1 通用态势分量

| 分量 | 符号 | 计算 |
|---|---|---|
| HP 安全度 | `H` | `clamp01((hp_ratio - 0.20) / 0.60)` |
| 低 HP 压力 | `L` | `1 - H` |
| 局部敌我压力 | `Q` | 见下式 |
| 主要武器就绪 | `W_r` | 主要组内最高 `reload_ready` |
| 有效目标 | `V_t` | 有合法可见任务目标为 1，否则为 0 |
| 视野需求 | `V_n` | `1 - visible_enemy_count / known_alive_enemy_count` |
| 编组凝聚 | `C` | `1 - clamp01(distance_to_slot / leash_distance)` |
| 边界安全 | `B_s` | `1 - boundary_risk` |
| 侧翼路径质量 | `F_q` | 左/右翼候选路径的安全和横向展开评分 |
| 脱离出口质量 | `E_q` | 可用候选脱离方向比例与最佳安全分 |
| 高价值目标暴露 | `X` | 已发现旗舰/航母/高 Cost 主力时为 0.7-1，否则 0 |

局部战力使用 Cost 和剩余 HP，不读取隐藏敌人：

```text
unit_power = cost * hp_ratio
friendly_power = sum(局部友军 unit_power)
visible_enemy_power = sum(局部可见敌军 unit_power)
power_ratio = visible_enemy_power / max(friendly_power, 1)
Q = clamp01((power_ratio - 0.80) / 1.20)
```

局部半径建议为自身主要武器射程的 `1.2` 倍。`known_alive_enemy_count` 只在关卡公开双方名单时使用；若敌方名单不公开，`V_n` 改为“连续无可见目标时间”的归一化值。

其余派生分量统一按以下方式计算：

```text
recent_damage_pressure = clamp01(damage_taken_last_3s / (max_hp * 0.20))

stealth_safety = clamp01(
  (nearest_visible_enemy_distance - current_concealment_distance)
  / max(current_concealment_distance * 0.50, 1)
)

front_threat_present = max(
  当前推进方向前方 120 度内所有可见敌人的 T
)

escort_proximity = clamp01(1 - distance_to_escort / desired_escort_radius)

distance_safety = clamp01(
  (nearest_visible_surface_enemy_distance - known_enemy_attack_range)
  / max(own_primary_range * 0.50, 1)
)
```

- `route_quality`：对候选短航路均匀取 3 个采样点，计算各点边界风险和可见敌方威胁，取 `1 - 平均风险`。
- `current_target_range_fit`：直接使用目标评分中的 `R`。
- `focus_threat`：取近期对自身/保护对象造成伤害的来源威胁 `T` 最大值；没有近期来源时使用局部压力 `Q`。
- `valuable_ghost`：旗舰/航母残影按剩余残影时间归一化；普通舰残影再乘其模式任务价值 `M`。
- `deployment_safety`：`clamp01(1 - 0.60*Q - 0.40*boundary_risk)`。
- `movement_urgency`：边界、局部压力、脱队和任务时限压力的最大值。
- `path_benefit`：候选航路终点的任务效用减当前点任务效用，再从 `[-1, 1]` 映射至 `[0, 1]`。
- `route_quality`、`flank_quality` 和 `exit_quality` 首轮只比较直行、左偏、右偏等有限候选，不建立全图成本图。

`stealth_safety` 只是依据已发现敌舰估算暴露风险。除非玩家也获得“已被发现”提示，否则不得读取敌方 `visible_by_faction` 来精确知道自身是否暴露。

### 4.2 各模式效用

模式不适用于当前舰船时返回 `Invalid`，不参与比较。

```text
DisengageRegroup = 100 * (
  0.45 * L
  + 0.30 * Q
  + 0.15 * boundary_risk
  + 0.10 * recent_damage_pressure
)

ReconAvoid = 100 * (
  0.30 * V_n
  + 0.25 * stealth_safety
  + 0.20 * H
  + 0.15 * route_quality
  + 0.10 * C
)

VanguardLine = 100 * (
  0.30 * H
  + 0.25 * front_threat_present
  + 0.20 * C
  + 0.15 * W_r
  + 0.10 * B_s
)

TorpedoFlank = 100 * (
  0.30 * W_r
  + 0.25 * X
  + 0.20 * F_q
  + 0.15 * H
  + 0.10 * E_q
)

GunlineSupport = 100 * (
  0.25 * H
  + 0.25 * V_t
  + 0.20 * current_target_range_fit
  + 0.15 * W_r
  + 0.15 * C
)

CarrierStandoff = 100 * (
  0.35 * distance_safety
  + 0.25 * V_t
  + 0.20 * B_s
  + 0.20 * escort_proximity
)
```

首轮将 `HoldDecisiveLine` 作为 `GunlineSupport` 的参数变体，将 `FlagshipRaid` 作为 `TorpedoFlank` 在 `X >= 0.8` 时的任务覆盖，不单独增加模式状态。

### 4.3 通用切换算法

推荐基线：

```text
mode_decision_interval = 0.5s
mode_minimum_hold = 4.0s
mode_enter_threshold = 60
mode_exit_threshold = 40
mode_switch_margin = 15
mode_switch_confirmations = 2
mode_recovery_time = 1.5s
```

普通切换：

1. 过滤不允许或硬门槛失败的模式。
2. 计算当前模式和候选模式效用。
3. 当前模式驻留不足 4 秒时保持。
4. 候选模式必须 `>= 60` 且比当前模式高至少 15 分。
5. 连续两次评估满足后切换。
6. 切换后进入 1.5 秒恢复期，只接受紧急打断。

若两次确认期间最佳候选模式发生变化，确认次数清零并从新候选重新累计。

退出滞回：当前模式低于 40 分并持续 1.5 秒，且没有更高分模式时，进入配置的回退模式。

### 4.4 紧急切换

以下事件绕过最短驻留和确认次数：

- `hp_ratio <= 0.20`。
- `boundary_risk >= 0.80`。
- 已发现鱼雷的预测碰撞时间小于公开反应阈值。
- 潜艇氧气耗尽。
- 保护对象在 3 秒内承受超过最大 HP 15% 的伤害。

紧急状态结束不能立刻回原模式，必须满足：

```text
boundary_risk < 0.25
Q < 0.45
连续 1.5s 未触发同类危险
```

然后重新计算所有模式，而不是恢复旧目标点。

## 5. 技能释放阈值

### 5.1 硬门槛

所有技能先检查：

- 冷却为 0。
- 释放者存活且状态允许。
- 目标类型、阵营、可见性和释放距离合法。
- 同一技能没有未消费的同类一次性效果，例如岛风已有 `ExtraShots` 时不重复释放。
- AI 反应延迟已经结束。

硬门槛通过后才计算技能效用。

### 5.2 技能用途标签

技能配置增加一个或多个 `ai_tags`：

```text
Burst
Defense
Recon
Mobility
Escort
AreaSupport
AntiAir
Ambush
```

第一阶段只实现 `Burst`、`Defense`、`Recon`、`Mobility`、`AreaSupport`。其他标签等待对应玩法闭环。

### 5.3 通用技能分量

| 分量 | 范围 | 含义 |
|---|---:|---|
| `target_quality` | 0-1 | 当前目标分 / 100 |
| `primary_ready` | 0-1 | 主要武器装填就绪度 |
| `window_quality` | 0-1 | 射程、射角和预计持续可见时间 |
| `survival_window` | 0-1 | 释放后仍能完成攻击/受益的概率近似 |
| `damage_risk` | 0-1 | 近期承伤和局部压力 |
| `low_hp` | 0-1 | 上节的 `L` |
| `vision_need` | 0-1 | 上节的 `V_n` |
| `coverage` | 0-1 | 实际覆盖单位数 / 期望覆盖数 |
| `stay_probability` | 0-1 | 目标在效果持续时间内留在区域的近似 |
| `non_overlap` | 0-1 | 与友军同类效果不重叠为 1，完全重叠为 0 |

### 5.4 用途效用公式

| 标签 | 效用公式 | 标准释放阈值 |
|---|---|---:|
| `Burst` | `100*(0.35*target_quality + 0.30*primary_ready + 0.20*window_quality + 0.15*survival_window)` | 65 |
| `Defense` | `100*(0.40*damage_risk + 0.35*low_hp + 0.25*focus_threat)` | 55 |
| `Recon` | `100*(0.45*vision_need + 0.35*valuable_ghost + 0.20*deployment_safety)` | 60 |
| `Mobility` | `100*(0.45*movement_urgency + 0.30*path_benefit + 0.25*exit_quality)` | 60 |
| `AreaSupport` | `100*(0.40*coverage + 0.30*target_quality + 0.20*stay_probability + 0.10*non_overlap)` | 65 |

难度只调整阈值和反应延迟：

| 难度 | 阈值修正 | 反应延迟 |
|---|---:|---:|
| 基础 | `+10` | 0.8-1.2s |
| 标准 | `0` | 0.4-0.8s |
| 高级 | `-8` | 0.2-0.5s |

阈值最低不得低于 45，避免高级 AI 冷却好就放。

### 5.5 与主要武器协同

爆发技能额外要求：

```text
expected_fire_delay <= effect_duration * 0.60
```

一次性“下一轮攻击”技能不受持续时间限制，但必须存在预计 6 秒内可形成的合法攻击窗口。

推荐保留规则：

- `Burst` 技能目标效用不足时最多保留 10 秒，之后重新评估，不强制释放。
- 自身 HP 低于 25% 且技能包含生存或机动收益时，解除爆发保留。
- 保护对象沉没、目标类型不存在或战斗即将结束时解除保留。

### 5.6 当前技能示例

#### 岛风 `五联雷暴`

标签：`Burst`、`Ambush`。

释放门槛：

- 鱼雷装填就绪度 `>= 0.75`。
- 存在 6 秒内可进入的合法鱼雷扇面。
- `target_quality >= 0.60`。
- `exit_quality >= 0.40`。
- 当前没有未消费的 `ExtraShots`。

若旗舰在 850 距离、鱼雷就绪、窗口质量 0.9、脱离质量 0.8，则技能效用通常超过 85；若无高价值目标且鱼雷仍在长装填，效用应低于 65。

#### 厌战 `老兵校射`

标签：`Burst`。

- 目标必须在技能自身 730 射程内，而不是只在主炮 1440 射程内。
- AP/HE 已选择适配目标装甲的弹种。
- 主炮装填就绪度 `>= 0.85`。
- 技能成功后下一模拟 Tick 提交主炮命令，不等待下一次 0.5 秒完整决策。

技能和主要武器不能依赖 `command_id` 字符串排序决定先后。AI Runtime State 应记录 `pending_combo = FirePrimaryAfterSkill`；技能命令成功应用后，在下一 Tick 的快速跟进阶段提交主要武器命令。若目标已非法则取消连携，不消耗主要武器装填。

#### 兴登堡 `集中火控网`

标签：`Burst`。

- 10 秒持续时间内预计至少完成 1 轮主炮攻击。
- 当前目标 `W >= 0.55` 且 `R >= 0.45`。
- 若没有合法目标，不因技能是 Self 类型就自动释放。

#### 阿芙乐尔 `探照号令`

标签：`AreaSupport`、`Recon`。

- 区域至少覆盖 1 个合法敌人，或一个高置信残影且主力炮线缺少视野。
- `coverage` 的期望覆盖数首轮设为 2。
- 同区域已有同类效果覆盖超过 60% 时，`non_overlap` 降至 0.2 以下。

## 6. 边界处理

### 6.1 动态安全边距

当前地图是矩形。边界安全距离根据舰船运动能力计算：

```text
omega = deg_to_rad(max(turn_speed, 1))
reference_speed = max(current_speed, max_speed * 0.60)
turn_radius = reference_speed / omega

hard_margin = collision_radius + 12
soft_margin = clamp(
  1.50 * turn_radius + 2.0 * collision_radius,
  96,
  min(map_width, map_height) * 0.12
)
```

以当前数据的全速状态估算：

- 岛风高速且转向快，转弯半径约 59，软边距约 123。
- 大和低速且转向慢，转弯半径约 94，软边距约 205。
- 这比为所有舰船写死同一边距更合理。

### 6.2 边界风险

```text
edge_distance = 舰船中心到四条边的最小距离
edge_now = clamp01((soft_margin - edge_distance) / (soft_margin - hard_margin))

predicted_position = position + velocity * 2.0s
predicted_edge_distance = predicted_position 到边界的最小中心距离
edge_future = clamp01((soft_margin - predicted_edge_distance) / (soft_margin - hard_margin))

outward = max(0, dot(forward_vector, nearest_edge_outward_normal))

boundary_risk = clamp01(
  0.45 * edge_now
  + 0.35 * edge_future
  + 0.20 * edge_now * outward
)
```

矩形最近边法线：

- 左边 `(-1, 0)`。
- 右边 `(1, 0)`。
- 上边 `(0, -1)`。
- 下边 `(0, 1)`。

### 6.3 响应区间

| `boundary_risk` | 行为 |
|---:|---|
| `< 0.35` | 不干预模式航向 |
| `0.35-0.65` | 给朝外候选方向增加边界惩罚 |
| `0.65-0.80` | 强制偏向沿边界切向的两个候选方向 |
| `>= 0.80` | 触发 `BoundaryEscape` 紧急打断 |

候选方向边界惩罚：

```text
boundary_heading_penalty = 100 * boundary_risk^2
```

`BoundaryEscape`：

1. 在顺时针/逆时针两个边界切向中选择转向角更小、离威胁更远的一侧。
2. 目标点设置在软边界内侧，沿切向前进 `max(soft_margin, speed * 2s)`。
3. 风险低于 0.25 并持续 1.5 秒后解除。
4. 解除后重新计算模式和航路，不恢复指向边界外的旧航点。

Domain 的 `_clamp_to_map()` 继续作为最终硬保护，但正常 AI 不应依赖 clamp 才转向。

当前 `_clamp_to_map()` 只钳制单位中心。实现边界硬约束时应增加考虑 `collision_radius` 的单位版本，使舰体不会跨出地图；投射物和区域瞄准仍可按各自规则使用原坐标钳制。

### 6.4 角落处理

同时接近两条边时：

- 合成两个内向法线形成角落逃生方向。
- 若该方向正对主要可见威胁，则在两个单边切向中选风险较低者。
- 航母和低转向战列提前在 `boundary_risk >= 0.65` 时转出。
- 侧翼模式的路径评分对软边界内航点额外扣 20-40 分，避免把贴边当默认最优路径。

## 7. 数据配置建议

首轮不要实现任意公式解释器。程序内保留上述稳定公式，JSON 只配置权重和阈值。

AI 模式示例：

```json
{
  "id": "ai.mode.torpedo_flank",
  "target_weights": {
    "mission": 0.30,
    "threat": 0.22,
    "weapon_fit": 0.18,
    "range_fit": 0.12,
    "kill": 0.10,
    "focus": 0.08,
    "pursuit_penalty": 0.12,
    "overkill_penalty": 0.12
  },
  "preferred_range_ratio": 0.82,
  "range_band_half_width": 0.30,
  "target_switch_margin": 12,
  "minimum_hold_time": 4.0,
  "mode_enter_threshold": 60,
  "mode_switch_margin": 15,
  "fallback_mode_id": "ai.mode.disengage_regroup"
}
```

技能只增加：

```json
{
  "ai_tags": ["Burst", "Ambush"],
  "ai_policy_id": "ai.skill_policy.torpedo_burst"
}
```

`ai_policy_id` 引用有限的程序策略枚举，不允许在 JSON 中执行表达式。

## 8. 程序结构

建议新增纯逻辑对象：

```text
scripts/application/ai/
  ai_controller.gd
  ai_observation.gd
  ai_runtime_state.gd
  target_scorer.gd
  mode_evaluator.gd
  skill_evaluator.gd
  boundary_steering.gd
```

职责：

- `AIObservation`：构造阵营合法可见信息和己方完整状态。
- `TargetScorer`：输出合法候选、分量明细和最终目标分。
- `ModeEvaluator`：计算模式效用、滞回、确认和紧急打断。
- `SkillEvaluator`：按有限用途策略计算技能效用。
- `BoundarySteering`：给候选航向评分或产生紧急逃生航点。
- `AIController`：组合以上结果并产生标准命令。

不要把这些对象做成 Godot `Node`；使用 `RefCounted` 或静态纯函数，方便无画面测试和批量模拟。

### 8.1 运行时状态

```text
ai_runtime_by_unit[unit_id] = {
  mode_id,
  mode_entered_at,
  mode_candidate_id,
  mode_candidate_confirmations,
  task_target_id,
  attack_target_id,
  target_acquired_at,
  last_target_switch_at,
  active_interrupt,
  interrupt_started_at,
  skill_reserve_reason,
  skill_reserve_started_at,
  pending_combo,
  recent_damage_by_source,
  decision_cooldown
}
```

这些字段属于单场战斗，不写回 Definition。

### 8.2 决策顺序

```text
每个固定模拟 Tick（当前通常 0.1 秒）：
  1. 更新边界风险和即时安全打断
  2. 处理已经确认的技能—主要武器 pending_combo
  3. 仅产生必要的快速跟进命令

每 0.5 秒：
  1. 构造 AIObservation
  2. 更新近期伤害与残影记忆
  3. 汇总 boundary_risk 和其他紧急事件
  4. 处理/维持紧急打断
  5. 计算模式效用并应用滞回
  6. 选择 task_target
  7. 选择 attack_target
  8. 计算移动候选与边界修正
  9. 评估技能
  10. 评估 ManualPrimary 主要武器
  11. 将命令加入下一 Tick 队列
```

自动普通武器继续由现有 `_update_weapons()` 处理。

## 9. 调试事件与统计

建议新增事件：

```text
AITargetChanged
AIModeChanged
AISkillEvaluated
AIPrimaryWindowEvaluated
AIInterruptStarted
AIInterruptEnded
```

不要每个 Tick 记录全部候选。只在以下时机输出分量明细：

- 目标或模式实际切换。
- 技能达到冷却后首次被保留。
- 技能释放。
- 主要武器窗口被接受或连续拒绝超过阈值。
- 边界紧急打断开始/结束。

批量模拟重点指标：

- 每分钟目标切换次数，建议标准 AI 不高于 8 次。
- 每分钟模式切换次数，建议通常不高于 4 次。
- 技能冷却完成后的平均等待时间。
- 主要武器合法窗口利用率。
- 边界软区停留比例，建议低于战斗时间的 12%。
- `BoundaryEscape` 平均持续时间和重复触发次数。

## 10. 自动测试

### 10.1 目标评分

- 不可见目标不进入候选，即使是旗舰。
- `FlagshipRaid` 下已发现旗舰分高于相同距离、HP 的轻巡。
- `VanguardLine` 下接近保护对象的潜艇分高于远处旗舰。
- 新目标只高 11 分时不切换，高 13 分并连续两次确认后切换。
- 固定输入下同分目标由实体 ID 稳定决胜。

### 10.2 模式切换

- 候选高于当前 14 分不切换，高 16 分连续两次后切换。
- 进入模式 4 秒内不因普通评分切换。
- HP 降至 20% 时立即进入脱离，不等待确认。
- 紧急状态结束后不恢复已经非法的旧目标点。

### 10.3 技能

- 技能冷却完成但效用低于阈值时不释放。
- 岛风鱼雷长装填或没有攻击窗口时不释放 `五联雷暴`。
- 厌战目标超出技能 730 射程时不释放 `老兵校射`。
- 兴登堡没有合法目标时不释放 Self 火控技能。
- 阿芙乐尔同类区域效果高度重叠时降低释放效用。

### 10.4 边界

- 同位置、航向和速度下固定得到相同风险。
- 高速高转向舰与低速低转向舰产生不同软边距。
- 预计 2 秒内撞边时风险高于静止在相同位置。
- 角落状态生成向内或沿边切向航点，不生成越界点。
- 风险降至 0.25 以下并持续 1.5 秒后解除紧急状态。

## 11. 推荐实现顺序

1. 纯函数 `clamp01`、角度、距离带和边界风险测试。
2. `AIObservation` 与 `AIRuntimeState`。
3. `TargetScorer`，先替换现有 `_target_score()`。
4. 目标切换滞回和调试事件。
5. `BoundarySteering`，保留 `_clamp_to_map()` 兜底。
6. `ModeEvaluator` 与四个基础模式。
7. `SkillEvaluator` 和当前六个原型技能标签。
8. AI 主要武器命令与技能—武器协同。
9. 批量模拟调参后再加入侧翼雷击模式。

这条顺序能让每一步单独产生可验证收益，不需要一次提交完整 AI 框架。

## 12. 首轮基线汇总

| 参数 | 基线 |
|---|---:|
| 单舰决策间隔 | 0.5s |
| 舰队/编组决策间隔 | 2.0s |
| 目标最短保持 | 2.0s |
| 目标切换优势 | 12 分 |
| 目标切换确认 | 2 次 |
| 模式最短驻留 | 4.0s |
| 模式进入阈值 | 60 分 |
| 模式退出阈值 | 40 分 |
| 模式切换优势 | 15 分 |
| 模式切换确认 | 2 次 |
| 紧急恢复稳定时间 | 1.5s |
| 标准技能阈值 | 55-65 分 |
| 边界预判时间 | 2.0s |
| 边界警告风险 | 0.35 |
| 边界强制转向风险 | 0.65 |
| 边界紧急风险 | 0.80 |
| 边界退出风险 | 0.25 |

这些值应先固定在默认 AI Rule Set 中。至少完成 100 个固定种子批量样本并检查切换频率、技能利用率、主要武器利用率和边界停留后，再开放为关卡难度参数。
