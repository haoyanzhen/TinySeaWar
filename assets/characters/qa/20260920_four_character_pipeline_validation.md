# 2026-09-20 四角色全量美术生产与管线验证

## 结论

本批选择贝尔法斯特（轻巡）、光辉（航母）、拥护者（潜艇）、定远（战列），覆盖四种舰种的炮塔、鱼雷管组、起降甲板和早期铁甲舰结构。36 张正式源图均由 Codex 内置 ImageGen 请求原生透明 PNG，未使用 API Key、色键抠图或网格硬切。四套资产契约均 `complete`；当前哈希绑定逐件审查为 `polish`，批次 `technical_ready=4/4`、`delivery_ready=4/4`。

**验证证明：有审查人参与的新生产路线可完成整包生成、裁切、配置、验收和 Godot 加载；不证明无人值守生成或完整战斗表现接入。** 本批没有修改关卡、角色数值或战斗组装代码。

## 缺口检查与交付数量

开始时第二期有 15 名未生成角色，本批完成其中 4 名，仍有 11 名没有源包：Z23、纽伦堡、沙恩霍斯特、齐柏林伯爵、秋月、高雄、翔鹤、伊-19、逸仙、长春、海龙。全项目具备 processed manifest 的角色由 33 增至 37；这不是整体美术验收通过人数。苏系塔什干、恰巴耶夫、甘古特、K-21 的既有复验问题未在本批关闭。

每名角色包含：

| 项目 | 数量 | 内容 |
| --- | ---: | --- |
| 原生 Alpha 源图 | 9 | 概念立绘、UI、战斗拆件、五组四帧动作、VFX |
| 明确裁切规格 | 44 | 8 UI、8 战斗件、20 动画帧、8 VFX；按语义物件标定坐标 |
| 运行时 UI PNG | 11 | 全身/派生半身/cut-in、头像、表情、技能和舰种图标 |
| 战斗拆件 PNG | 8 | 本体、底座及舰种专属部件 |
| 动画 PNG | 25 | 20 独立姿态帧 + 5 首帧兼容 keyframe |
| 角色 VFX PNG | 8 | 特效保留全部独立光点、水花、烟和环形组件 |
| 来源 Alpha 副本 | 9 | 后处理可追溯输入，不计入运行时 PNG |

合计 **36 张正式源图、208 张运行时 PNG、36 张 source_alpha 副本**。贝尔法斯特另引用公共中口径炮口与小水花，定远引用公共中/大口径炮口；不复制公共资源。四套动画、挂点、VFX、manifest 配置及 source/delivery review 均已生成。

## 实际发现与修复

1. **自动视觉通过风险**：内置来源登记原先直接写 pass。现从 `meta/{id}_source_review.json` 读取当前 SHA-256、审查人和观察记录；缺失/过期保持 pending，Alpha 通过仅记技术通过。
2. **弱 Alpha 桥接造成串格**：最大组件清理原先把大于 0 的全部像素视作前景。改用现有阈值 8 选主体，并保留其 8px 邻域原有柔边；只对显式单主体规格启用，VFX 禁用。修复贝尔法斯特底座/炮塔互相带入、拥护者表情串格、定远图标和动画邻件残片。
3. **源图本身错误不能靠裁切掩盖**：重绘拥护者尾端截断、定远封闭炮塔、贝尔法斯特缺少第四炮座、光辉 UI 相邻接触、定远 VFX 贴边；光辉受击披风再次返工补全。
4. **动作门禁有效**：重绘贝尔法斯特 idle、光辉 hit/attack、定远 idle。清除邻件残片后部分动作才暴露相似度问题，最终所有状态使用原阈值通过；没有放宽阈值或用平移、缩放替代新姿态。
5. **新包来源识别**：批处理接受仅有 v2 provenance 的新角色，不再误报缺少旧文件。
6. **挂点与特效语义**：实际观察成品炮口、六艏管、甲板与安装座后记录归一化位置。修复贝尔法斯特主炮借用 AA、鱼雷借用扫描扇区、定远主副炮借用守护光环、拥护者发射误用 trail 语义。旧公共驱逐舰“发射闪光”模板含鱼雷弹体，未采用；改用纯公共小水花作瞬间覆盖。
7. **重建一致性**：四名角色的生产坐标/武器规则写入计划生成器；数据生成器尊重显式 weapon_binding_rules 和公共 VFX 引用，避免再次用名字猜测覆盖已审查语义。

## 验证证据

- Python 美术工具回归：**47/47 通过**，包括弱 Alpha 桥、原像素柔边、来源哈希过期、显式武器语义重建。
- [四角色资产契约](character_asset_contract_audit_belfast_illustrious_upholder_dingyuan.md)：4 complete，缺失角色项/数据问题均为 0。
- [四角色批次报告](character_art_batch_report_20260920_four.md)及[机器报告](character_art_batch_report_20260920_four.json)：4 technical_ready、4 delivery_ready，视觉均为 polish。
- Godot 4.6.3 完成新 PNG 导入；日志包含沙盒不能保存用户目录 editor_settings 的错误，导入后独立资源加载检查 **224/224 通过**（208 PNG + 16 配置），退出码 0。
- 二期配置回归 **301/302 通过**；唯一失败为既有第一期 15 个角色缺少 processed/vfx 目录。加载检查的 Autoload 同样会记录该全局已知错误；本批四角色无资源加载失败。
- 最终成品 contact 全量目检，关键本体、底座、表情、动画和 VFX 另作深浅底抽查；逐件结论与当前包哈希保存在各角色 `processed/config/{id}_delivery_review.json`。

复验命令（仓库根目录；受限环境设 `UV_CACHE_DIR=/tmp/tinyseawar-uv-cache`）：

```sh
uv sync --locked
uv run --locked python -m unittest discover -s tools/art_pipeline/tests
uv run --locked python tools/art_pipeline/check_character_asset_contract.py belfast illustrious upholder dingyuan
uv run --locked python tools/art_pipeline/batch_character_art.py --phase phase2 belfast illustrious upholder dingyuan
godot --headless --path . --log-file /tmp/tsw-import.log --import
godot --headless --path . --log-file /tmp/tsw-load.log --script res://tools/art_pipeline/tests/character_batch_asset_load.gd
godot --headless --path . --log-file /tmp/tsw-config.log --script res://scripts/tests/phase2_config_test.gd
```

来源变更后先重审 source_review，再运行来源登记及正式裁切入口；重新生成的交付审查会失效，不能沿用旧 verdict。被拒绝的候选没有进入正式资源目录。

## 剩余边界

- `ShipUnitView._draw_unit_art` 当前只绘制底座与本体/动画层，尚未按 mount_instances 完整实例化独立武器。本批动画明确只含本体，避免生图造成融合炮管；完整舰装组装、炮塔随动、方向偏移、尺寸和动画状态衔接仍需后续实机验收。
- 光辉大幅动作及定远待机存在组间头身比例差异；各图身份一致、主体完整，但最终缩放/播放节奏仍需调校。贝尔法斯特鱼雷模板是封闭弹头/管盖外形，管口识别可继续精修。
- 半身/cut-in 由立绘派生，已满足当前静态图契约，不能据此宣称技能 cut-in 演出完成。新增角色仍未进入正式关卡。
- 47 项回归、Alpha、契约、逐件目检及资源加载共同支持本次交付；任何单一脚本成功都不能代表美术或游戏整体完成。

## 图像证据

[四人总览](20260920_four_character_overview.png)

| 角色 | 全量成品 | 深浅底关键边缘 |
| --- | --- | --- |
| 贝尔法斯特 | [contact](belfast_processed_contact.png) | [边缘](belfast_20260920_edge_review.png) |
| 光辉 | [contact](illustrious_processed_contact.png) | [边缘](illustrious_20260920_edge_review.png) |
| 拥护者 | [contact](upholder_processed_contact.png) | [边缘](upholder_20260920_edge_review.png) |
| 定远 | [contact](dingyuan_processed_contact.png) | [边缘](dingyuan_20260920_edge_review.png) |
