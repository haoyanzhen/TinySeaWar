# 第二期角色美术资产审计

## 1. 审计结论

截至 2026-06-26，第二期美系首批 4 名角色的正式资产包状态已回退为未完成。此前生成的 UI、战斗拆件、VFX 和动画 sheet 来自锚点派生/程序绘制兜底链，属于 smoke test / placeholder，而非正式 gpt-image-2 / reference-image 产物；这些假资产已从正式源目录和 processed 目录移除。

因此，美系四人当前不得标记为 `batch_ready`。目前仅保留已确认的 `concept/{id}_concept_full.png` 锚点、角色级 `postprocess_plan.json`、生成简报和 trial log，等待真实 UI / 战斗拆件 / 动画 / VFX 源资产重新生成。

其余 20 名第二期角色仍处于阵营锚点门槛之前，未标记为完成。

| 审计项 | 结果 |
| --- | --- |
| 第二期名册 | 24/24 已固定 ID，可用 `phase2` 或 `all` 单独加载 |
| 角色级后处理计划 | 24/24 完成 |
| 生成简报与试产日志 | 24/24 完成，动画口径已改为五张 `2x2` 状态 sheet |
| 运行时数据 | 第二期 ship / weapon / skill / weapon visual 数据可加载 |
| 美系基础风格参考 | 4/4 保留 `concept/{id}_concept_full.png` |
| 美系旧派生资产清理 | 旧 `5x4` 动画母版、候选动画母版、boxed/clean 拆帧 QA、旧 processed 动画与旧派生目录已删除 |
| 美系新源母版 | 0/4 正式源包完整；锚点派生/程序绘制的假源 sheet 已移除 |
| 美系正式 processed 资产 | 0/4；占位派生 processed 包已移除 |
| 美系契约状态 | 4/4 `incomplete`，缺失正式 MVP 资产角色 |
| 美系批处理状态 | 0/4 `batch_ready` |
| Godot phase2 配置验证 | `PASS: 285 phase-two configuration checks` |
| Godot 总回归 | `PASS: 1212 checks` |

## 2. 本轮规则变更

本轮将角色动画生产默认规则从一张 `5x4` 合集改为五张独立 `2x2` 状态 sheet：

- `battle/{id}_anim_idle_4f_sheet.png`
- `battle/{id}_anim_move_4f_sheet.png`
- `battle/{id}_anim_attack_4f_sheet.png`
- `battle/{id}_anim_hit_4f_sheet.png`
- `battle/{id}_anim_firepower_4f_sheet.png`

每张 `2x2` sheet 的帧序为左上、右上、左下、右下。`5x4` 仍作为过渡兼容输入，但不再作为第二期新资产的默认生产格式。

变更原因：

- `5x4` 高密度母版在固定像素尺寸下容易压缩单格内容。
- 可见格线/固定硬切会掩盖源格边界截断风险。
- 五张 `2x2` 能给每个状态更大的有效画布，并降低动作、身份和舰装细节互相挤压的概率。

已同步位置：

- `tiny-sea-war-art-pipeline` skill
- `docs/40_art_direction_design.md`
- `docs/46_art_pipeline_design.md`
- `tools/art_pipeline/build_phase2_generation_briefs.py`
- `tools/art_pipeline/batch_character_art.py`
- `tools/art_pipeline/build_procedural_animation_master.py`
- `tools/art_pipeline/check_character_asset_contract.py` 增加第二期四帧动画姿态变化检查：对每帧主体 alpha 做裁切、缩放、居中注册后比较剪影重合度，避免整体平移、轻微旋转、色调变化或外接闪光造成假通过。
- `tools/art_pipeline/build_anchor_derived_mvp_sheets.py` 和 `tools/art_pipeline/build_procedural_animation_master.py` 已降级为显式 `--allow-placeholder` 的 QA 占位输出，只写入 `assets/characters/qa/*_placeholders/`，不得写正式源目录。
- `tools/art_pipeline/batch_character_art.py` 和 `postprocess_generated_character.py` 增加 source provenance 传递/阻断；`batch_ready_allowed=false` 的来源不能进入 `batch_ready`。

## 3. 美系四人资产状态

| 角色 | 舰种 | 新动画源 | processed 动画 | VFX | 契约 | 备注 |
| --- | --- | --- | --- | --- | --- | --- |
| 弗莱彻 `fletcher` | 驱逐 | 缺失 | 缺失 | 缺失 | incomplete | 仅保留锚点与计划；需真实生成五座单炮、鱼雷管、深弹与声呐资产 |
| 克利夫兰 `cleveland` | 轻巡 | 缺失 | 缺失 | 缺失 | incomplete | 仅保留锚点与计划；需真实生成无雷炮巡、防空、雷达资产 |
| 巴尔的摩 `baltimore` | 重巡 | 缺失 | 缺失 | 缺失 | incomplete | 仅保留锚点与计划；需真实生成无雷重巡、三座重炮、雷达火控资产 |
| 刺尾鱼 `wahoo` | 潜艇 | 缺失 | 缺失 | 缺失 | incomplete | 仅保留锚点与计划；需真实生成无脚蹼潜艇、六艏四艉鱼雷口、声呐、潜望镜和氧气指示资产 |

## 4. 审计产物

- 批处理报告：`assets/characters/qa/character_art_batch_report_phase2.md`
- 契约报告：`assets/characters/qa/character_asset_contract_audit_fletcher_cleveland_baltimore_wahoo.md`
- 第二期总览：`assets/characters/qa/character_roster_processed_contact_phase2.png`
- 单角色联系表：
  - `assets/characters/qa/fletcher_processed_contact.png`
  - `assets/characters/qa/cleveland_processed_contact.png`
  - `assets/characters/qa/baltimore_processed_contact.png`
  - `assets/characters/qa/wahoo_processed_contact.png`

## 5. Blocker 与修复要求

- `fletcher`、`cleveland`、`baltimore`、`wahoo` 当前缺少正式 UI、战斗拆件、动画和 VFX 源资产。锚点派生/程序绘制占位不得用于正式源包。
- 必须重新生成每个角色的正式 `4x2` UI、`4x2` 战斗拆件、五张 `2x2` Q 版战场单位动画母版和 `2x4` VFX 母版。
- 每个状态四帧需要能读出动作阶段：
  - `idle`：呼吸、舰装浮动或轻微站姿变化。
  - `move`：身体前倾、推进/航迹节奏和舰装随动。
  - `attack`：预备、开火峰值、后坐、复位。
  - `hit`：受击收缩、摇晃/火花反馈、恢复。
  - `firepower`：技能/火力动作启动、舰装响应、局部火光或光环、复位。
- 允许贴近炮口的火光和局部烟火；仍不允许飞出的炮弹、鱼雷、舰载机、深弹、长尾迹或大水柱烘焙进角色动画。
- 重新后处理后必须通过 source provenance、资产契约和姿态变化检查，再进入 Computer Use 视觉确认。

## 6. 非阻塞 polish

- 武器节点、技能图标和 VFX 当前以确定性图形表达语义，技术可用；后续可替换为更精细的手绘资产。
- 刺尾鱼的水下阴影/鲨形阴影 VFX 当前偏程序化，建议后续做更自然的低亮蓝黑水下效果。
- 表情差异主要通过锚点裁切和轻微色调变化实现，后续可用参考图服务重绘为更明确的表情。

以上 polish 项不影响后续真实资产生成；当前由正式源资产缺失和非生产来源兜底禁用共同阻止 `batch_ready`。

## 7. 设计债

本轮只完成资产生产与接入，不扩展战斗系统。第二期技能中的部分结构化效果仍保留为运行时设计债：

- 氧气消耗、仅潜航速度和仅潜航隐蔽。
- 实体舰载机 HP、多波次空袭与第二波独立命中。
- 主动鱼雷预警提前、侦察机独立视野和“仅对已侦查目标”条件。
- 武器散布修正、下一轮消耗、目标装甲类别补正和开火破隐比例。

这些项目不影响美系四人的资产路径和运行时发现，但当前动画 blocker 仍需先修复。

## 8. 验证记录

- `python3 tools/art_pipeline/check_character_asset_contract.py fletcher cleveland baltimore wahoo --phase phase2`：4/4 `incomplete`，正式 MVP 资产缺失。
- `python3 tools/art_pipeline/batch_character_art.py fletcher cleveland baltimore wahoo --phase phase2`：4/4 源包缺失，0/4 `batch_ready`。
- `python3 tools/art_pipeline/batch_character_art.py fletcher cleveland baltimore wahoo --phase phase2 --process`：不得运行正式处理，除非真实源资产已生成并通过来源检查。
- `/opt/homebrew/bin/godot --headless --path . -s scripts/tests/phase2_config_test.gd`：`PASS: 285 phase-two configuration checks`。
- `/opt/homebrew/bin/godot --headless --path . -s scripts/tests/test_runner.gd`：`PASS: 1212 checks`。
