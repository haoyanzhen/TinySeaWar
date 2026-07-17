# 角色美术资产生产与验收管线

> **功能与边界**：本文是角色源图、拆件、透明化、配置生成、批处理和 QA 的生产流程真源。通用资产包由 `docs/40_art_direction_design.md` 定义，个体视觉重点由 `docs/41_character_art_design.md` 定义，运行时语义接口由 `docs/45_art_asset_interface_design.md` 定义，当前完成度只见 `docs/00_project_status.md`。本文不维护角色数值、公共战斗 VFX、运行时完成状态或场景环境资产流程。

## 1. 目标

将 AI 生成的角色美术汇总图，稳定转为可进入游戏绑定测试的单件透明资产和配置数据。

管线采用半自动方案：

```text
试产 sheet
-> 程序清背景、拆件、补 padding、生成配置
-> 人工视觉确认
-> 程序生成/更新 QA 报告
-> 进入绑定和战斗场景测试
```

人工目检可以由支持本地图片和预览页的审查工具执行，但必须记录审查人、产物和 `pass/polish/blocker` 结论；不得仅凭脚本退出码代替视觉确认。

## 2. 输入

### 2.1 资产契约

`docs/40_art_direction_design.md` 的「单角色美术资产清单」是生成、后处理和验收的唯一契约。流水线不得以「源图中没有」作为忽略必需资产的理由。

全身立绘必须从已验收的角色设定稿输出到正式处理目录，不得只留在 `concept/` 中。

每个角色保留试产母版：

```text
assets/characters/{id}/concept/
assets/characters/{id}/ui/
assets/characters/{id}/battle/
assets/characters/{id}/vfx/
assets/characters/{id}/meta/
```

核心输入文件：

```text
{id}_concept_full.png
{id}_ui_sheet.png
{id}_battle_asset_grid.png
{id}_anim_{state}_4f_sheet.png
{id}_vfx_reference_sheet.png
{id}_trial_log.md
```

新生成角色默认使用 `4x2` 战斗拆件母版和五张 `2x2` 动画母版：`idle`、`move`、`attack`、`hit`、`firepower` 每个状态单独一张四帧 sheet，帧序为左上、右上、左下、右下。动画母版必须使用 Q 版/SD 战场单位比例，匹配 `battle_body_r` 的战场读图尺度；不得生成全身立绘、半身立绘或技能 cut-in 比例。动画帧只包含角色本体、附着舰装、武器后坐、贴近炮口的开火火光、局部烟火、局部航迹/扫描/光环和姿态变化；飞出的炮弹、鱼雷、导弹、舰载机、深水炸弹、长曳光、长尾迹和大水柱等子物体必须交给公共战斗表现或运行时节点，不烘焙进角色动画母版。旧试产角色和过渡批次允许继续读取 `{id}_anim_5x4_master.png`，但它只是兼容输入；批处理工具必须同时识别五张 `2x2` 与旧 `5x4` 两条合法路线。

半身立绘和技能 cut-in 可以作为独立源图提供；缺省时允许从已验收全身锚点自动派生构图，但正式输出仍必须包含对应独立文件。

## 3. 配置

第二期角色以角色级计划作为强制生产契约；第一期兼容包可以在缺少计划时继续使用已验收的舰种模板：

```text
assets/characters/{id}/postprocess_plan.json
```

配置内容：

- 源 sheet 路径。
- crop box。
- 输出文件名。
- 资产类型和标签。
- pivot。
- 绑定点。
- 动画状态。
- VFX 用途。
- padding 和 edge-fix 策略。

第二期角色将该文件作为强制生产契约，另外记录 `phase`、`ship_class`、`skill_role`、`battle_grid_roles`、`mount_instances`、`bindings`、`vfx_roles`、`public_vfx_profiles` 和 `acceptance_rules`。后处理优先读取角色级计划，第一期无该文件时继续使用现有舰种默认模板。

## 4. 程序化步骤

程序应负责：

- 扫描角色目录。
- 清背景时先删除与画布边缘连通的抠图色，再清理被头发、头像框或舰装封闭的高置信度抠图色残留；不得只依赖边缘连通判定，否则封闭区域会留下色块。
- 兼容早期白底 VFX 源图：根据画布边缘识别近白底色，用白底 alpha 恢复而不是全局删除白色；若白底 sheet 内仍嵌有绿色 UI 单元，再叠加高置信度绿幕清理。
- 源图生成时将抠图色视为保留色：角色、舰装和特效不得使用同一高亮色。角色设计必须使用绿色高亮时改用洋红抠图底，反之亦然；后处理不得承担猜测同色像素语义的责任。
- 按配置裁切 sheet。
- 将初始裁剪框视为目标提示，而不是最终边界；在源图 alpha 上查找与初始框相交的前景连通块，合并这些连通块的真实包围盒，再加安全边距得到最终裁剪框。
- 连通块分析可以忽略接近全透明的低 alpha 桥接像素，避免将相邻 UI 件误判为同一主体；该阈值只用于确定裁剪边界，不修改最终输出的原始 alpha 纹理。
- 对明确只应包含一个连通主体的舰装底座、炮塔或 Q 版头像，可在角色规格中显式启用「保留最大前景组件」或「清理小型孤岛」；不得对烟雾、火花、水花等多组件特效全局启用。
- trim alpha。
- 根据 alpha 包围盒和 alpha 加权重心添加平衡透明 padding，使内容尽量位于子图中心。
- 输出 RGBA PNG。
- 生成 `postprocess_manifest.json`。
- 生成 `meta_bind_points.json`。
- 生成 `anim_config.json`。
- 生成 `vfx_config.json`。
- 按需生成 QA 预览页。
- 自动检查 RGBA、空 alpha、贴边、缺文件和 JSON 可解析性。
- 自动检查所有运行时 PNG 的透明安全边距和 alpha 加权视觉重心；任一边贴图或视觉重心偏离画布中心超过 10% 时阻塞交付。
- 自动检查运行时 PNG 的大面积不透明近白底和保留绿幕色；命中阈值时阻塞交付，避免仅凭 RGBA 模式误判为透明资产。
- 按单角色资产契约检查完整性；必需项缺失时将角色包标记为 `incomplete`，即使已有 PNG 都可读也不得通过交付。
- 检查动画和 VFX 配置的引用文件是否存在、舰种数据是否一致，以及绑定点是否在子图边界内并且靠近非透明画面。
- MVP 动画源图默认使用五张 Q 版战场单位 `2x2` 母版，每张一个状态、四格连续四帧；过渡角色也可读取一张 `5x4` 兼容母版。拆分后在 `anim_config.json` 中记录有序帧、FPS 和循环标记。待机/移动使用小幅循环；攻击/受击/火力使用预备、峰值、反馈/后坐和复位。攻击帧最多允许贴近炮口的开火火光或小型局部烟火，不允许出现已发射的炮弹、鱼雷、飞机、深弹或长尾迹等独立子物体。
- 同一状态的四张透明帧需要归一到相同画布尺寸并保持稳定视觉中心，避免 Godot `AnimatedSprite2D` 播放时产生画布跳动。
- 四帧画面驱动角色姿态；精确炮塔旋转、炮口、投射物、后坐位移和 VFX 仍使用 Godot 独立节点与补间。

## 5. 人工视觉确认

程序生成预览页后，审查者必须在可显示本地图片的环境中完成目检。

预览页要求：

- 每张拆件显示在棋盘、深色、浅色三种背景上。
- 每张卡片显示源文件路径。
- 按角色和资产类型分组。

视觉检查项：

- 是否存在矩形白底、灰底、棋盘底或黑底残留。
- 是否有白边、黑边或明显 halo。
- 是否误删白发、白帽、白制服、泡沫、气泡、浅色航迹或发光 VFX。
- 是否裁切过紧。
- 是否切掉角色、舰装、炮口、鱼雷、飞机、VFX 轨迹或 UI 边框。
- 是否保留足够透明 padding。
- 小尺寸下角色和舰种是否仍可读。

输出判断：

- `pass`：可进入绑定测试。
- `polish`：可进入绑定测试，但最终导入前需要美术精修。
- `blocker`：阻塞导入测试，需要重新裁切、修背景或重新生成。

## 6. 输出

正式后处理输出：

```text
assets/characters/{id}/processed/source_alpha/
assets/characters/{id}/processed/ui/
assets/characters/{id}/processed/battle/
assets/characters/{id}/processed/vfx/
assets/vfx/combat/character_templates/{ship_class}/
assets/characters/{id}/processed/anim/
assets/characters/{id}/processed/config/
```

配置输出：

```text
{id}_postprocess_manifest.json
{id}_meta_bind_points.json
{id}_anim_config.json
{id}_vfx_config.json
```

批次 QA 输出建议：

```text
assets/characters/qa/edge_qa_preview.html
assets/characters/qa/edge_qa_report.md
assets/characters/qa/{id}_processed_contact.png
assets/characters/qa/character_roster_processed_contact.png
```

预览页建议支持两种模式：

- 常规模式：使用相对路径引用图片，页面体积小，适合本地服务器或引擎工具中查看。
- 稳定 QA 模式：将 PNG 以 data URI 嵌入 HTML，避免浏览器 `file://` 路径加载失败；适合自动化审查环境读取。批量角色较多时应按角色或资产类型分页，避免单页过大。

## 7. 当前工具入口

当前正式入口：

```bash
python3 tools/art_pipeline/postprocess_generated_character.py enterprise_cv6
python3 tools/art_pipeline/batch_character_art.py enterprise_cv6 --process --preview
python3 tools/art_pipeline/check_character_asset_contract.py
```

工具的当前路径只作生产入口；代码位置总路引仍以 `docs/34_implementation_map.md` 为准。

## 8. 批量生产控制

批量生产使用：

```bash
python3 tools/art_pipeline/batch_character_art.py
python3 tools/art_pipeline/batch_character_art.py bismarck --process --preview
python3 tools/art_pipeline/postprocess_generated_character.py iowa
python3 tools/art_pipeline/batch_character_art.py --phase phase2
python3 tools/art_pipeline/check_character_asset_contract.py --phase phase2
python3 tools/art_pipeline/postprocess_generated_character.py --phase phase2 --roster-contact
```

Dry-run 会检查旧式独立 sheet 或新式母版输入、后处理路由、运行时数据和资产契约。旧试产角色可以继续使用脚本内手写裁剪规格；新生成的标准源图包优先使用 `postprocess_generated_character.py` 自动完成 UI 八格、`4x2` 战斗组件、五张 `2x2` 动画母版、VFX 八格、基础绑定点和配置生成。宽幅 VFX 表按 `2x4` 读取；早期方形白底 VFX 表按 `3x4` 读取前两行的八个运行时角色，避免跨行串图。像素完全一致且已确认属于舰种模板的 VFX 只在 `assets/vfx/combat/character_templates/` 保存一份，角色 `vfx_config` 通过 `shared_class_template` 引用；不同图像自动保留为角色专属覆盖。`--process` 按角色独立执行后处理，单个角色失败不中断后续角色，结果写入：

```text
assets/characters/qa/character_art_batch_report.json
assets/characters/qa/character_art_batch_report.md
```

角色只有在旧式 sheet 路线或新式母版路线至少一条完整、没有非生产来源标记、对应后处理路由可用、后处理契约通过时才标记为 `batch_ready`。图像生成仍需按角色建立和验收风格锚点，不建议在未验收锚点时一次生成整个角色包。全量验收使用 `postprocess_generated_character.py --roster-contact` 生成 24 角色关键资产总览，并保留每名角色的完整 processed contact。

`tools/art_pipeline/build_anchor_derived_mvp_sheets.py` 和 `tools/art_pipeline/build_procedural_animation_master.py` 只能用于 smoke test / placeholder 检查。它们不得写入 `assets/characters/{id}/ui`、`battle`、`vfx` 或 `processed` 等运行时源目录；显式使用 `--allow-placeholder` 时也只能输出到 `assets/characters/qa/*_placeholders/`，并写入 `batch_ready_allowed=false` 的 provenance。缺少真实 gpt-image-2 / reference-image 产物时应保持资产缺失，不生成虚假的正式资产面板。

其中 `--preview` 负责生成视觉检查页，人工确认后再将结果写入 QA 报告。默认后处理应优先保持快路径，不自动生成大体积嵌入式预览页。
