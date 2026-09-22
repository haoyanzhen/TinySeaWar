# 日本四角色美术生产与管线验证（2026-09-20）

从原剩余 7 名未生产角色中选择同阵营的秋月、高雄、翔鹤、伊-19，覆盖驱逐、重巡、航母与潜艇。

![四角色总览](20260920_japanese_four_overview.png)

## 交付

四人各 9 张 Codex 内置原生 Alpha 源图、52 张角色运行时 PNG，合计 36 / 208；另引用 3 张既有公共 VFX。每人包含 11 张 UI、8 张战斗拆件、5 组四帧动画与 5 张 keyframe、8 张角色 VFX。四套技术契约 complete、逐件视觉 polish、delivery_ready。源图、裁切规格、绑定点、动画/VFX 配置与版本绑定审查均已保存。

当前接受的 36 张源图全部通过原生 Alpha 检查，复制保留原始字节；没有直连 API、API Key 或色键降级。底层模型与请求 ID 未暴露，如实记录为 Codex 托管。生成记录区分初始请求、修订记录与最终源文件哈希；不把初始提示当作最终图像的唯一请求。

## 可靠性结论

**管线适合有人审查的半自动生产，尚不支持无人审查的一次生成交付。** 本批多轮修改后可重复得到合格素材，但不能把接受版本的 Alpha 通过率解释为首次生成成功率。

- 精确装备仍会漂移。秋月鱼雷管数、高雄炮塔/鱼雷架数量、桅杆与光效边缘均发生过错误。高雄新动作修订还经历漏炮、补炮后多炮，逐帧复数后才接受。未把这些结构错误降为 polish。
- 动作门禁有效，但受输入质量影响。拦下秋月攻击、高雄受击；清理邻件后又暴露高雄攻击/技能、伊-19攻击差异不足。重新绘制真实肢体姿态，没有降低 IoU 阈值。邻件碎片可能人为扩大轮廓差异，因此先完成裁切视觉审查再解释指标。
- 裁切仍需逐件标定。过宽提示、源图中对象过近会混入邻栏肖像、炮塔或上下帧碎片。收紧连通块选择提示，重新生成高雄/伊-19 UI 及伊-19攻击的更宽间距版本。UI 单体使用旧核心已有最大组件标签；VFX 未使用该过滤，保留断开水滴、火花与环线。没有网格硬切，也没有恢复抠色。
- 武器表现不能依赖名称猜测。秋月主炮原来会选防空圈，高雄炮击/雷击会选技能线/扇区，伊-19发射会选尾迹/侦查图。本轮使用明确绑定规则和公共发射特效，普通潜艇发射语义为水面发射；标定炮口、管口及基座/甲板点。4 份计划和 9 条武器表现可由生成器完整复现。
- 三背景抽检未见不透明底色或明显脏边。跨状态比例、装配、朝向、动画衔接与公共简化 VFX 的风格融合仍需实机 polish；静态 ready 不代表正式战斗表现验收。

## 验证

| 检查 | 结果 |
|---|---|
| 缺来源/裁切/成品预检 | 按预期退出 1 |
| Python 管线回归 | 53/53 |
| 最终交付门禁 | 4/4，退出 0 |
| 重复构建 | 260/260 SHA-256 相同，交付审查保持有效；244 PNG 含 36 source_alpha，另 16 配置 |
| 生成器复现 | 4 计划、9 武器表现一致 |
| Godot 本批加载 | 227 项，errors=[]，退出 0 |
| Godot 二期全局配置 | 301/302；唯一失败为既有第一期 15 个角色缺 processed/vfx 目录，本批未新增 |

Godot 导入退出 0，受沙箱限制的用户编辑器设置保存警告不影响本批资源加载。使用本地 PNG 完成视觉检查，未宣称浏览器或正式战斗测试通过。

- [最终交付报告](character_art_batch_report_phase2_japanese_four_final.md)
- [初始负向预检](character_art_batch_report_phase2_japanese_four_preflight.md)
- [重复构建完整哈希](20260920_japanese_four_rebuild_check.json)
- 秋月：[逐件](akizuki_processed_contact.png)、[边缘](20260920_japanese_akizuki_edge_backgrounds.png)、[绑定](20260920_japanese_akizuki_bindings.png)
- 高雄：[逐件](takao_processed_contact.png)、[边缘](20260920_japanese_takao_edge_backgrounds.png)、[绑定](20260920_japanese_takao_bindings.png)
- 翔鹤：[逐件](shokaku_processed_contact.png)、[边缘](20260920_japanese_shokaku_edge_backgrounds.png)、[绑定](20260920_japanese_shokaku_bindings.png)
- 伊-19：[逐件](i_19_processed_contact.png)、[边缘](20260920_japanese_i_19_edge_backgrounds.png)、[绑定](20260920_japanese_i_19_bindings.png)

复验：

```sh
uv sync --locked
uv run --locked python -m unittest discover -s tools/art_pipeline/tests -p 'test_*.py'
uv run --locked python tools/art_pipeline/batch_character_art.py --phase phase2 --require-delivery --report-tag japanese_four_final akizuki takao shokaku i_19
godot --headless --path . --script res://tools/art_pipeline/tests/character_batch_asset_load.gd -- akizuki takao shokaku i_19
```

剩余未生产角色为逸仙、长春、海龙；苏联四人的既有返工状态没有因本批通过而改变。
