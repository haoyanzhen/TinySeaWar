# 德国四角色美术生产与管线验证（2026-09-20）

本轮从剩余 11 名未生产角色中选择 Z23、纽伦堡、沙恩霍斯特和齐柏林伯爵，覆盖驱逐、轻巡、战列、航母四种结构。同阵营便于核对风格一致性，不代表全部舰种或后续批次的一次通过率。

![四角色总览](20260920_german_four_overview.png)

## 交付范围

| 角色 | 原生透明源图 | 角色运行时 PNG | 动作 | 技术契约 | 逐件视觉 | 交付门禁 |
|---|---:|---:|---|---|---|---|
| Z23 | 9 | 52 | 5 组 × 4 帧 | complete | polish | ready |
| 纽伦堡 | 9 | 52 | 5 组 × 4 帧 | complete | polish | ready |
| 沙恩霍斯特 | 9 | 52 | 5 组 × 4 帧 | complete | polish | ready |
| 齐柏林伯爵 | 9 | 52 | 5 组 × 4 帧 | complete | polish | ready |

合计 36 张源图、208 张角色运行时 PNG；另引用 3 张现有公共 VFX，不重复生产。每人 52 张包含 11 张 UI、8 张战斗拆件、20 张动画帧、5 张动画 keyframe 和 8 张角色 VFX。保留逐件裁切规格、生成请求说明、当前哈希源图审查、schema v2 来源、绑定点、动画/VFX 配置及版本绑定交付审查。

生成使用 Codex 内置 ImageGen；没有要求 API Key，没有直连 API 或色键降级。底层模型和请求 ID 未暴露，来源如实记为 Codex 托管。源图复制保持字节不变。当前 36 张源图全部通过原生 Alpha 门禁；这只是接受版本的事实，不是模型总体成功率。

## 可靠性发现及修复

1. **源图语义仍需要人工闭环。** 初版及修订中出现炮廓数量偏差、炮管数量漂移、桅杆/鞋/头发或炮口光边缘截断、纽伦堡攻击动作漏画鱼雷架等问题。分别重新生成/编辑并复查，没有把结构缺陷改标为 polish。会话生成目录最终有 64 张图像输出，其中 36 张为当前接受源图，其余为迭代版本；另遇到一次网络失败后重试。因此本批不能支持“无人审查的一次成图即可交付”。
2. **扩框矩形会串入邻件。** Z23 表情上方混入上一排切条，沙恩霍斯特尾流混入旗标碎片。旧核心只依据选中组件算包围盒，仍复制安全边距中的其他组件。本轮在共用 `prepare_crop` 中排除未与逐件提示相交的邻件，同时保留所有选中组件及原有柔边；不使用网格硬切，也不对 VFX 取最大组件。
3. **面积证据需区分目标和邻件。** manifest 同时记录原始矩形 Alpha 面积、排除邻件组件数、选中源对象面积。VFX 对比选中对象与成品面积；不再把正确清除邻件误报成丢失特效。新增回归验证邻件切条被排除，而两个独立特效岛和低 Alpha 柔边保持。提示仍须覆盖全部预期断开组件，脚本无法代替语义目检。
4. **动画门禁发挥作用。** 首轮处理拦下 Z23 idle、沙恩霍斯特 firepower、齐柏林 move/attack/firepower；后续拦下纽伦堡和沙恩霍斯特 attack。均通过重新生成真实肢体/舰装姿态变化解决，未降低 IoU 门槛。留白修正后再次检查装备数量，防止修一项退化另一项。
5. **静态绑定与 VFX 不能靠名称猜测。** 标定炮口、发射管、转轴、甲板及基座挂点；左向武器不再沿用最右端默认点。纽伦堡主炮/鱼雷、沙恩霍斯特主副炮、齐柏林副炮/航空改为明确角色与公共 VFX 映射，避免发炮播放防空圈、技能线或转向环。4 份计划与 10 条武器表现均可由生成器重建。

## 验证证据

| 检查 | 结果 |
|---|---|
| 缺来源/裁切/成品的预检交付门禁 | 按预期退出 1，未把文件齐全当作交付 |
| Python 美术管线回归 | 53/53 通过；含来源哈希失效、交付 pending/stale、拒绝网格降级、多组件 VFX 与邻件排除 |
| 最终 `--require-delivery` | 4/4，通过且退出 0 |
| 相同输入重复处理 | 260/260 文件 SHA-256 一致：244 张 processed PNG（含 36 张 source_alpha）及 16 份运行时 JSON；交付审查也保持有效 |
| Godot 四角色加载 | 227 项检查，errors=[]，退出 0；211 张 PNG 含 3 张共享 VFX，另 16 份配置 |
| Godot 二期配置检查 | 301/302；唯一失败仍为既有第一期 15 个角色 VFX 目录缺失，本批无新增失败 |

Godot 导入完成且退出 0，但沙箱不允许写用户目录的编辑器设置，日志记录了保存设置警告；资源加载专项已另行通过。本地 HTML 的浏览器访问被 URL 安全策略阻止，未绕过策略；逐件图和三背景边缘通过本地 PNG 查看完成，不宣称浏览器交互预览通过。

- [最终交付报告](character_art_batch_report_phase2_german_four_final.md) / [JSON](character_art_batch_report_phase2_german_four_final.json)
- [初始负向门禁](character_art_batch_report_phase2_german_four_preflight.md)
- [首轮三角色处理拦截记录](character_art_batch_report_phase2_german_four_processed.md)（历史失败，非当前状态）
- [重复构建完整哈希](20260920_german_four_rebuild_check.json)
- Z23：[三背景边缘](20260920_german_z23_edge_backgrounds.png)、[绑定点](20260920_german_z23_bindings.png)、[可手动打开的 HTML](edge_qa_z23.html)
- 纽伦堡：[三背景边缘](20260920_german_nurnberg_edge_backgrounds.png)、[绑定点](20260920_german_nurnberg_bindings.png)、[HTML](edge_qa_nurnberg.html)
- 沙恩霍斯特：[三背景边缘](20260920_german_scharnhorst_edge_backgrounds.png)、[绑定点](20260920_german_scharnhorst_bindings.png)、[HTML](edge_qa_scharnhorst.html)
- 齐柏林：[三背景边缘](20260920_german_graf_zeppelin_edge_backgrounds.png)、[绑定点](20260920_german_graf_zeppelin_bindings.png)、[HTML](edge_qa_graf_zeppelin.html)

复验入口：

```sh
uv sync --locked
uv run --locked python -m unittest discover -s tools/art_pipeline/tests -p 'test_*.py'
uv run --locked python tools/art_pipeline/batch_character_art.py --phase phase2 --require-delivery --report-tag german_four_final z23 nurnberg scharnhorst graf_zeppelin
godot --headless --path . --script res://tools/art_pipeline/tests/character_batch_asset_load.gd -- z23 nurnberg scharnhorst graf_zeppelin
```

需要重新裁切时给批处理添加 `--process --preview`；源图、规格或计划改变后必须重新逐件审查，不能继承旧哈希结论。

## 结论与边界

本批验证支持**有人审查的半自动生产**：原生 Alpha、来源哈希、逐件裁切、契约和交付门禁能够形成可重复的交付链；生成器的精确装备、动作一致性与构图仍不稳定。新增邻件排除修复已对本批验证，其他历史角色未重处理，不能自动继承本批视觉结论。

素材交付 ready 不等于战斗表现完成。独立武器装配、遮挡侧挂点、左右朝向、跨状态尺寸、动画衔接、Z23 待机蹲姿节奏及正式战斗演出仍待实机验收。四人仍未进入正式第二期关卡。剩余 7 名未生产角色为秋月、高雄、翔鹤、伊-19、逸仙、长春、海龙。
