# Aurora / Warspite 新角色美术流水线测试报告

## 测试范围

- Aurora / 阿芙乐尔号：苏系 2级轻巡，支援、探照、士气光环方向。
- Warspite / 厌战号：英系 3级战列，主炮压制、远距瞄准、皇家防护方向。
- 输入来源：两名角色当前试产汇总图与独立 UI 图。
- 输出范围：UI 立绘、头像、技能图标、战场本体、舰装、武器节点、动画关键帧、特效参考、绑定点与动画/特效配置。

## 输出结果

| 角色 | PNG 输出 | 配置 JSON | 自动检查 |
| --- | ---: | ---: | --- |
| Aurora | 37 | 4 | RGBA 正常，JSON 可解析，manifest 无裁剪警告 |
| Warspite | 39 | 4 | RGBA 正常，JSON 可解析，manifest 无裁剪警告 |

配置文件包括：

- `*_meta_bind_points.json`
- `*_anim_config.json`
- `*_vfx_config.json`
- `*_postprocess_manifest.json`

## 视觉 QA 结论

### Aurora

可用度：中高。

- 角色半身、头像、技能 cut-in、战场本体、舰装底座和炮塔节点都能作为 MVP 资产继续使用。
- 动画关键帧在修正初始裁剪框后，已经去掉右侧相邻帧残片。
- 探照灯、信号灯、炮焰等角色特征清晰，符合轻巡支援定位。
- 仍需轻微清理：`aurora_vfx_support_ring_03` 右侧有一条黑色残片；`aurora_vfx_morale_aura` 偏小偏淡，后续可重新生成或增强。

### Warspite

可用度：中高。

- 战场本体、舰装底座、三组主炮、测距仪、雷达节点都比较稳定，适合进入绑定/战斗原型阶段。
- UI 立绘、头像、技能图标与角色气质一致，战列舰身份辨识度强。
- 动画关键帧裁剪稳定，没有明显主体截断。
- 主要问题集中在特效：炮焰、水花、弹道有多段序列被保留在同一张图中；`warspite_vfx_splash_sequence` 左上角有源图残片。若运行时需要逐帧特效，应继续拆成单帧资产。

## 流水线评估

这轮验证说明新流水线已经适合处理角色主体类资产：

- 用初始框作为提示，再自动寻找相交前景组件，可以避免裁剪框压到角色本体。
- 透明边缘、主体居中、绑定点配置和 manifest 记录都能稳定产出。
- 对 UI、舰装、武器节点、动画关键帧的效果明显优于固定框裁剪。

当前短板在特效图：

- 单个特效和多段序列需要不同策略，不能全部用同一种组件合并逻辑。
- 后续建议为每个资产增加 `component_policy`：`single`、`sequence`、`allow_multi`。
- 对 `sequence` 类型，应自动拆为 `frame_01`、`frame_02`、`frame_03`，并单独做边缘/居中检查。

## 产物索引

- Aurora 输出目录：`assets/characters/aurora/processed/`
- Warspite 输出目录：`assets/characters/warspite/processed/`
- 合并视觉 QA 图：`assets/characters/qa/edge_qa_aurora_warspite_contact.png`
- Aurora 单独 QA 图：`assets/characters/qa/edge_qa_aurora_contact.png`
- Warspite 单独 QA 图：`assets/characters/qa/edge_qa_warspite_contact.png`

