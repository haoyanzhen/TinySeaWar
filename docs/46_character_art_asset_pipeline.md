# 角色美术资产生产与验收管线

> **功能与边界**：本文是角色源图、拆件、透明化、配置生成、批处理和 QA 的生产流程真源。通用资产包由 `docs/40_art_direction_design.md` 定义，个体视觉重点由 `docs/41_character_art_design.md` 定义，运行时语义接口由 `docs/45_art_asset_interface_design.md` 定义，当前完成度只见 `docs/00_project_status.md`。本文不维护角色数值、公共战斗 VFX、运行时完成状态或场景环境资产流程。

## 1. 目标

将 Codex 账户内置 ImageGen 生成的原生透明角色源图稳定转为可进入游戏绑定测试的单件透明资产和配置数据；非 Codex 环境可显式使用直连 Images API 保底。

管线采用半自动方案：

```text
角色生产契约与风格锚点
-> Codex 账户内置 ImageGen 原生透明 PNG
-> 源图真实 Alpha 与物体完整性门禁
-> 旧裁切管线：逐件规格定位、源图连通块扩框、trim、平衡 padding、生成配置
-> 人工视觉确认
-> 程序生成/更新 QA 报告
-> 进入绑定和战斗场景测试
```

人工目检可以由支持本地图片和预览页的审查工具执行，但必须记录审查人、产物和 `pass/polish/blocker` 结论；不得仅凭脚本退出码代替视觉确认。

## 2. 输入

### 2.1 生成路线

Codex 环境中的新角色默认直接使用账户内置 ImageGen，不要求项目安装 SDK，也不要求用户提供 API Key。风格锚点独立生成；UI、战斗拆件和动画引用已验收锚点；VFX 可按角色语义独立生成。正式源图必须由生成器请求透明 PNG，接受结果复制到角色源目录时保持字节不变，并通过 `tools/art_pipeline/record_codex_builtin_art.py` 写入 schema v2 来源记录。

Codex 内置路线不暴露底层模型名和请求 ID 时，来源记录必须明确写为账户托管/未暴露，不得伪造 GPT Image 模型名、`/v1/images/*` endpoint 或请求 ID。非 Codex 批处理环境可显式使用 `tools/art_pipeline/generate_character_art.py` 直连 Images API；它是可选保底入口，不是 Codex 会话的前置门禁。

只有同时满足“PNG/WebP 带 Alpha 通道、Alpha 最小值为 0、存在非透明主体、画布和边缘有实际透明区”才可进入正式源目录；RGB 棋盘格、白/黑底、全不透明 RGBA 和空 Alpha 都必须阻塞。技术门禁通过后仍需逐图人工物体完整性审查，在结论为 `pass/polish` 前不得 `batch_ready`。

内置生图登记读取 `meta/{id}_source_review.json`：根字段为 `character_id` 与 `sources`，后者按九类源图 role 保存 `sha256`、`verdict`、`reviewer`、`observation`。只有哈希对应当前文件且审查人、观察记录非空时才采纳结论；记录缺失或过期时保持 `pending`。Alpha 技术通过不得自动写成视觉通过。源图更换后先重新目检并更新此记录，再登记来源；成品仍须另行完成第 5.1 节交付审查。

旧色键路线仅是最后保底，默认禁用。只有原生透明尝试失败，并显式提供 `--allow-legacy-chroma-fallback --fallback-reason "..."` 时，才允许请求单一保留绿幕，并在 provenance 中同时写入授权原因和实际原生尝试失败记录。未记录开关、失败原因、原生失败事实或逐图生成路线的绿幕包不得作为新生产资产通过。既有 schema v1 绿幕/白底包继续由后处理兼容读取，但只能表述为历史兼容资产，不能冒充 GPT Image 2.5 原生透明产物。

### 2.2 资产契约

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

源图生成路线与后处理路线独立：Codex 内置原生 Alpha 继续用于生图，所有正式拆件统一进入 `postprocess_trial_sheets.py`。已有角色沿用其中的 `CropSpec`；新增/重建源包在 `meta/{id}_crop_specs.json` 保存逐件源图坐标提示。`postprocess_generated_character.py` 仅适配原生 Alpha、角色计划和 schema v2 配置，实际裁切复用旧管线 `prepare_crop`，不得先按数学网格裁成小图再提取物体。

裁切规格文件示例（坐标仅说明结构，必须根据实际源图标定）：

```json
{
  "character_id": "tashkent",
  "crops": {
    "battle_body_r": {
      "source": "battle_grid",
      "box": [80, 60, 280, 380],
      "tags": []
    }
  }
}
```

`source` 使用源图键 `ui_sheet`、`battle_grid`、`battle_sheet`、`anim_{state}`、`anim_master` 或 `vfx_sheet`；`box` 是整张源图上的整数 `[left, top, right, bottom]` 提示，不是最终裁切边界。`crops` 必须覆盖 UI 七角色及 `class_icon`、计划中的所有战斗角色、`anim_{state}_frame_01..04` 和全部 `vfx:{role}`。独立全身/半身/cut-in 按完整源图进入旧裁切核心；缺省半身与 cut-in 仍允许按第 2 节派生构图。提示框应覆盖目标所需组件并避开邻件；重生成或改变源图布局后必须重新复核，不能直接复用旧坐标或把整格当作目标。`tags` 仅允许逐件显式启用 `keep_largest_component` 或 `remove_small_islands`，VFX 禁止这两种删组件操作。

缺少逐件规格时只报告未配置，不覆盖已有 `processed/`，不退回自动等分。完成角色级 `postprocess_plan.json` 并不等于完成逐件裁切规格。

新标定的规格同时保存根字段 `source_sha256`，按实际引用的源图键记录 SHA-256，并恰好覆盖 `crops` 引用的源图集合。加载时先核验哈希，再创建输出；同尺寸换图也必须重新审查提示框并更新哈希。未带此字段的既有规格保持兼容，不自动替旧坐标背书。

第二期角色将该文件作为强制生产契约，另外记录 `phase`、`ship_class`、`level`、`skill_role`、`battle_grid_roles`、`mount_instances`、`object_inventory`、`bindings`、`binding_positions`、`weapon_binding_rules`、`vfx_roles`、`public_vfx_profiles`、`additional_public_vfx_roles` 和 `acceptance_rules`。后处理优先读取角色级计划，第一期无该文件时继续使用现有舰种默认模板。`level` 必须与 `docs/41_character_art_design.md` 的角色行一致；`object_inventory` 的实例数必须与 `mount_instances` 一致，炮管/鱼雷管等子件数按角色审查需要显式记录。

使用 manifest schema v2 的正式角色还必须提供 `meta/{id}_source_provenance.json` 或版本化的 `meta/{id}_source_provenance_v2.json`，如实记录生成路线、可见的模型/工具/接口信息、尺寸、透明控制、输出格式、提示词修订、参考输入、逐图 Alpha 事实、每张源图的 SHA-256 与人工 `pass/polish/blocker` 结论。直连 API 路线必须记录并校验真实模型、endpoint 与请求 ID；Codex 内置路线则必须使用专用 route 标识，并如实记录底层模型和请求 ID由账户托管且未暴露。两种路线都不得相互冒充。缺失生成 ID、未保留原候选或不可重放步骤应作为可复现性限制记录，但不应阻断透明度、对象完整性和运行时契约均通过的 Codex 内置产物。

现有 9 名旧路线成品只按已入库 manifest 的历史形态冻结兼容：其中 4 名 processed manifest 仍是 schema v1 且没有内嵌来源记录，杰维斯和同批 4 名苏系角色则由 schema v2 manifest 内嵌 schema v1 provenance。该名单只允许这些已有成品继续验证，任何其他角色都不得借用 schema v1。后 5 名必须冻结原 `{id}_generation_brief.md` 和 `{id}_source_provenance.json`，保持历史 SHA-256 不变；brief 生成器会另写 `{id}_generation_brief_v2.md`，新生成入口优先使用 v2 brief，并将重建记录写入 `{id}_source_provenance_v2.json`。显式 `--overwrite` 可逐项重建，但在 v2 九类来源全部生成、审查并重新后处理前保持阻断。不得通过覆盖旧记录或重写旧哈希来伪造迁移完成。

## 4. 程序化步骤

程序应负责：

- 扫描角色目录。
- 原生 Alpha 源图直接保留其像素和透明通道，不再执行绿幕清理，避免误删角色或 VFX 中合法的绿色细节。
- schema v2 原生透明路线如果缺少真实 Alpha 必须立即失败，不允许后处理静默补救。
- 显式授权的旧色键保底以及 schema v1 历史包才允许清背景：先删除与画布边缘连通的抠图色，再清理被头发、头像框或舰装封闭的高置信度抠图色残留；不得只依赖边缘连通判定，否则封闭区域会留下色块。
- 兼容早期白底 VFX 源图：根据画布边缘识别近白底色，用白底 Alpha 恢复而不是全局删除白色；若白底 sheet 内仍嵌有绿色 UI 单元，再叠加高置信度绿幕清理。该能力不得被新生产入口自动选择。
- 使用最后保底色键时将抠图色视为保留色：角色、舰装和特效不得使用同一高亮色；后处理不得承担猜测同色像素语义的责任。
- 按配置裁切 sheet。
- 将初始裁剪框视为目标提示，而不是最终边界；在源图 alpha 上查找与初始框相交的前景连通块，合并这些连通块的真实包围盒，再加安全边距得到最终裁剪框。
- 连通块分析以 Alpha 大于 `8` 的前景忽略近透明桥接。扩框后的安全边距可能带入邻件，裁切核心须排除不与逐件提示相交的邻件组件；保留所有被提示选中的组件及原有柔边，不重着色。邻件周围 `8px` 内不属于选中主体柔边的低 Alpha 像素一并排除。规格须覆盖目标的全部断开组件，不能只标注特效中心。
- 对明确只应包含一个连通主体的舰装底座、炮塔或 Q 版头像，可在角色规格中显式启用「保留最大前景组件」或「清理小型孤岛」；不得对烟雾、火花、水花等多组件特效全局启用。
- 显式 `keep_largest_component` 清理以 Alpha 大于 `8` 的前景选择主体，保留其周围 `8px` 内原有低 Alpha 柔边，清除远处弱桥与邻件；主体保留像素不重着色。此清理会改变被移除邻件的 Alpha，区别于仅用于扩框的连通块分析，必须复核细小配饰是否误删。
- trim alpha。
- 根据 alpha 包围盒和 alpha 加权重心添加平衡透明 padding，使内容尽量位于子图中心。
- 输出 RGBA PNG。
- 生成 `postprocess_manifest.json`；schema v2 对每张来源/运行时图记录 RGBA 模式、alpha 包围盒与面积、来源边距、原始裁切提示、自动裁切方法、选中组件样本、最终裁切框、输出 padding、alpha 加权重心/归一化偏移和组件标签。另记录裁切矩形原始面积、排除邻件组件数和选中源对象面积；VFX 必须核对选中源对象与输出的 alpha 面积一致，并目检提示是否漏选断开的环、火花、烟与水花。
- 生成 `meta_bind_points.json`。
- 生成 `anim_config.json`。
- 生成 `vfx_config.json`。
- 按需生成 QA 预览页。
- 自动检查 RGBA、空 alpha、贴边、缺文件和 JSON 可解析性。
- 自动检查所有运行时 PNG 的透明安全边距和 alpha 加权视觉重心；任一边贴图或视觉重心偏离画布中心超过 10% 时阻塞交付。
- 自动检查运行时 PNG 的大面积不透明近白底和保留绿幕色；命中阈值时阻塞交付，避免仅凭 RGBA 模式误判为透明资产。
- 按单角色资产契约检查完整性；必需项缺失时将角色包标记为 `incomplete`，即使已有 PNG 都可读也不得通过交付。
- 检查动画和 VFX 配置的引用文件是否存在、舰种数据是否一致，以及绑定点是否在子图边界内并且靠近非透明画面。
- 自动推断仅用于没有明确机械节点的试产资产；正式角色可在 `postprocess_plan.json` 的 `binding_positions` 中使用画布归一化坐标覆盖挂点，炮塔、鱼雷与反潜挂点必须叠加到可辨认的底座/投放位置。`weapon_binding_rules` 同时锁定武器表现配置的挂点与发射/命中语义，避免反潜武器误从炮口发射。
- 角色可以在 `additional_public_vfx_roles` 中将公共战斗 VFX 映射为角色可查询的语义角色，只记录引用，不复制公共贴图。
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

### 5.1 统一交付核验清单

保留新管线中已有的来源追溯、真实 Alpha、物体清单、角色级绑定点覆盖、武器/VFX 语义核验、有序动画配置和批处理失败隔离；这些能力不依赖网格切分。新旧后处理入口在完成配置和 manifest 后，统一由 `delivery_review.py` 生成 `processed/config/{id}_delivery_review.json`：

- 对源图、来源记录、裁切规格、生产计划、processed 图像和配置计算 SHA-256，并纳入实际引用的公共 VFX。
- 对每张运行时图记录真实 Alpha 事实、manifest 中的源图裁切证据及待填写的 `review`；旧 manifest 的 `source_crop_qa` 与新 schema v2 的 `crop` 均可读取，不伪造历史生成信息。
- 审查者逐件填写 `verdict`（`pass/polish/blocker`）、`reviewer`、`observation`；初始值永远是 `pending`，不从源图 provenance 或脚本退出码复制 `pass`。观察记录应说明对象/数量、截断与邻件、动作一致性以及挂点/VFX 语义检查结果。
- 任一来源、成品、裁切规格或配置变化后，旧结论显示 `stale`；重新生成清单时恢复 `pending`。包内容完全不变时可保留原逐件结论。清单未覆盖全部图像、缺少审查人/观察记录或存在 blocker 时不允许视觉通过。
- 批处理明确输出 `technical_ready`、`visual_review` 和 `delivery_ready`。旧 `batch_ready` 字段仅作为 `technical_ready` 的兼容别名；`delivery_ready` 要求技术检查通过且逐件视觉审查为当前版本的 `pass/polish`，只表示可进入绑定测试，不能替代引擎实机验收。

已有资产可单独补清单而不重切：

```bash
uv run --locked python tools/art_pipeline/delivery_review.py tashkent --prepare
uv run --locked python tools/art_pipeline/delivery_review.py tashkent
```

该清单不承担自动识别肢体、炮管数量或机械语义的职责；输出透明边距和 Alpha 面积只能证明像素事实，不能证明未发生源图截断或串件。

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

内置路线可先运行 `uv run --locked python tools/art_pipeline/record_codex_builtin_art.py {id} --prepare-review` 创建九类源图审查清单。此命令允许源包尚未齐全，缺图记为 `missing/pending`；同哈希的有效审查保留，更换或删除源图仅使该项回到 pending，并保留上一条证据供追溯。它不登记来源、不自动判定视觉通过，也不裁切图片。填写审查结论后去掉 `--prepare-review` 才正式登记；审查人和观察必须为非空字符串，非法结构或未知 role 直接拒绝。

交付验收使用显式门禁，建议同时为批次报告命名：

```bash
uv run --locked python tools/art_pipeline/batch_character_art.py --phase phase2 --require-delivery --report-tag trial_01 belfast illustrious upholder dingyuan
godot --headless --path . --log-file /tmp/character-art-load.log --script res://tools/art_pipeline/tests/character_batch_asset_load.gd -- belfast illustrious upholder dingyuan
```

`--require-delivery` 仅当技术与当前版本逐件视觉审查都通过时返回 0；默认仍兼容技术门禁。空批次、处理失败、视觉 pending/blocker/stale 均不能满足交付门禁。报告同时记录 `required_gate` 与 `gate_passed`。`--report-tag` 在原 phase 报告名后追加标识，避免单批验收覆盖全期报告；同名标识重复执行则更新该批报告。标识只允许小写字母、数字、下划线和连字符。

独立 `delivery_review.py` 检查所有指定角色后，只要任一视觉审查未通过就返回非零退出码；`--prepare` 成功生成待审清单仍返回 0，不表示交付通过。正式自动化继续使用同时覆盖技术与视觉的 `batch_character_art.py --require-delivery`。

Godot 加载检查接受 `--` 后的角色 ID，省略时兼容四角色试产默认名单；检查本地 PNG、四类配置身份、五状态四帧引用、挂点资产及公共 VFX 引用。缺失/空 UI、battle、anim 目录失败；仅引用公共 VFX 时允许没有本地 vfx 目录。该检查是导入与引用检查，不能替代契约检查或实机演出验收。

Codex 生图使用账户内置 ImageGen，完成逐图审查后用 `record_codex_builtin_art.py` 登记；下列 `generate_character_art.py` 命令仅是非 Codex 环境的显式 API 保底示例。正式后处理统一使用旧裁切入口：

```bash
uv sync --locked
uv run --locked python tools/art_pipeline/build_phase2_generation_briefs.py
uv run --locked python tools/art_pipeline/generate_character_art.py belfast --batch anchor --dry-run
uv run --locked python tools/art_pipeline/generate_character_art.py belfast --batch anchor
uv run --locked python tools/art_pipeline/generate_character_art.py belfast --record-review concept_full --verdict pass --observation "identity and exact object inventory accepted"
uv run --locked python tools/art_pipeline/generate_character_art.py belfast --batch ui
uv run --locked python tools/art_pipeline/generate_character_art.py belfast --role vfx_sheet --allow-legacy-chroma-fallback --fallback-reason "two native-alpha responses failed the alpha gate"
uv run --locked python tools/art_pipeline/postprocess_trial_sheets.py enterprise_cv6
uv run --locked python tools/art_pipeline/batch_character_art.py enterprise_cv6 --process --preview
uv run --locked python tools/art_pipeline/check_character_asset_contract.py
uv run --locked python -m unittest discover -s tools/art_pipeline/tests -p 'test_*.py' -v
```

只有显式直连 API 生成才需要 SDK 与环境变量 `OPENAI_API_KEY`；Codex 内置生图及旧裁切不要求 API Key，密钥不得写入仓库、命令参数、日志或 provenance。图像处理使用 Pillow。项目统一由根目录 `pyproject.toml`、`uv.lock` 和 `.python-version` 管理 Python 3.12 的 `.venv`；安装、生成、后处理、审计和单测必须使用 `uv sync --locked` 与 `uv run --locked python`，不得使用裸 `python3` 或向 Conda/系统环境重复安装依赖。

工具的当前路径只作生产入口；代码位置总路引仍以 `docs/34_implementation_map.md` 为准。

## 8. 批量生产控制

生成非锚点批次前，脚本会核验 schema v2 中锚点的技术结论、人工 `pass` 结论和文件哈希；只存在锚点文件但未审查不得生成下游资产。

批量生产使用：

```bash
uv run --locked python tools/art_pipeline/batch_character_art.py
uv run --locked python tools/art_pipeline/generate_character_art.py belfast --batch ui
uv run --locked python tools/art_pipeline/generate_character_art.py belfast --batch battle
uv run --locked python tools/art_pipeline/generate_character_art.py belfast --batch animation
uv run --locked python tools/art_pipeline/generate_character_art.py belfast --batch vfx
uv run --locked python tools/art_pipeline/batch_character_art.py bismarck --process --preview
uv run --locked python tools/art_pipeline/postprocess_trial_sheets.py iowa
uv run --locked python tools/art_pipeline/batch_character_art.py --phase phase2
uv run --locked python tools/art_pipeline/check_character_asset_contract.py --phase phase2
uv run --locked python tools/art_pipeline/postprocess_generated_character.py --phase phase2 --roster-contact
```

生成入口的 `--dry-run` 会输出 endpoint、模型、尺寸、质量、`background=transparent`、PNG 格式和目标路径，不调用付费接口。批处理 Dry-run 会检查旧式独立 sheet 或新式母版输入、生成 provenance、逐件裁切规格、运行时数据和资产契约。`--process` 统一调用 `postprocess_trial_sheets.py`：旧试产角色沿用脚本内规格，原生 Alpha 包通过适配层读取第 3 节的逐件规格，并复用同一个源图连通块裁切、trim 和平衡 padding 核心。`postprocess_generated_character.py {id}` 仅保留为转发到旧入口的兼容命令，不再执行自动网格切分，也不再用待机动画覆盖独立战斗本体。sheet 的 `4x2`、`2x2` 或 `5x4` 只是生成布局约定，不是裁切边界。像素完全一致且已确认属于舰种模板的 VFX 只在 `assets/vfx/combat/character_templates/` 保存一份，角色 `vfx_config` 通过 `shared_class_template` 引用；不同图像自动保留为角色专属覆盖。`--process` 按角色独立执行后处理，单个角色失败不中断后续角色，结果写入：

```text
assets/characters/qa/character_art_batch_report.json
assets/characters/qa/character_art_batch_report.md
```

新生产角色只有在 schema v2 provenance 按第 2 节校验实际生成路线、逐图原生 Alpha 或显式保底授权，且所有源图完成物体完整性审查、逐件裁切规格可用、后处理契约通过时才标记为 `batch_ready`。内置路线如实记录 Codex 托管信息；仅直连 API 路线要求实际模型、endpoint 和请求 ID。schema v1 旧包保留历史兼容，不反向宣称为新路线。图像生成必须按角色先建立和验收风格锚点，再生成依赖它的批次；不得在未验收锚点时一次生成整个角色包。全量验收使用 `postprocess_generated_character.py --roster-contact` 生成 24 角色关键资产总览，并保留每名角色的完整 processed contact。

`tools/art_pipeline/build_anchor_derived_mvp_sheets.py` 和 `tools/art_pipeline/build_procedural_animation_master.py` 只能用于 smoke test / placeholder 检查。它们不得写入 `assets/characters/{id}/ui`、`battle`、`vfx` 或 `processed` 等运行时源目录；显式使用 `--allow-placeholder` 时也只能输出到 `assets/characters/qa/*_placeholders/`，并写入 `batch_ready_allowed=false` 的 provenance。缺少真实 GPT Image 2.5 / reference-image 产物时应保持资产缺失，不生成虚假的正式资产面板。

其中 `--preview` 负责生成视觉检查页，人工确认后再将结果写入 QA 报告。默认后处理应优先保持快路径，不自动生成大体积嵌入式预览页。
