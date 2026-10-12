# Tiny Sea War Agent Guide

本文件是 Codex 进入项目后的总路引。做任何设计、程序、美术资产或数据改动前，先用它判断应该阅读哪些设计文档，以及本次改动应该落在哪一层。

## 项目总纲

Tiny Sea War 是基于 Godot 4.x 的 2D 二次元舰娘海战原型。当前目标不是完整养成游戏，而是做出可重复游玩的战斗切片，用于验证移动、侦查、隐蔽、炮击、鱼雷、主动技能、UI 可读性、美术资产接入和初始数值节奏。

MVP 的核心约束：

- 以开阔海域半即时战斗为主，不做抽卡、养成、剧情、基地和长线经济系统。
- 舰娘是情感与识别核心，航向、武器方向、射程、命中和状态通过舰装、特效、海面叠层与 UI 表达。
- 自动战斗与玩家指令并存：高价值攻击由玩家决定时机，其余武器维持自动交战。
- 战斗规则、公式、数据结构和表现层分离，Domain 层规则应能脱离 Godot 场景树测试。
- 所有数值都是首轮原型基线，允许通过实机测试持续调整。

## 文档路引

设计文档已按职责分目录，编号是稳定ID。完整文件目录与任务阅读路线见 [docs/README.md](docs/README.md)，结构及旧名映射见 [01](docs/01_documentation_structure_plan.md)。正式路径以README为准，不根据编号猜目录。

开始任务先读 [00](docs/00_project_status.md)，需要定位实现时读 [34](docs/34_implementation_map.md)。下表只选择权威源，不复制完整目录、字段或工程细节。

| 任务 | 设计真源 | 下游契约与实现方案 |
|---|---|---|
| 玩法取舍/核心规则/操作/公式 | gameplay中的17/10/11/12；公共预算13、角色14 | contracts/21；architecture/32 |
| 教学/挑战/进度 | gameplay/15公共规则、15-3教学、15-4挑战 | contracts/23；technical/t02 |
| 自定义与特别行动 | gameplay/15-1、15-2 | contracts/23/24；特别行动依人类反馈调平，不用AI代打 |
| AI与航行 | gameplay/16；contracts/24 | architecture/32/35；technical/t00/t01，不合并/缓存战略请求 |
| 地形/环境/设施 | gameplay/18效果；contracts/22 | architecture/35/37/38分别负责空间、环境上下文、设施 |
| 数据与资产接口 | contracts/20索引、21–26专题、45资产语义 | 加载校验与当前精确配置见data，位置查34 |
| 战斗表现/角色/场景/UI | presentation/40–44；操作归gameplay/11 | architecture/33生命周期；contracts/25/45；technical/t10航空 |
| 美术生产 | production/46角色、47场景 | presentation标准与contracts/45；对应tools README负责工具参数 |
| 音乐与音效 | presentation/50音乐、52声音标准 | production/51音乐、53音效；contracts/25、architecture/33负责运行时 |
| 模拟与平衡 | architecture/19平台、contracts/26字段、validation/36方法 | 不相互替代；20局及以上实验授权规则保持 |
| 状态、工单和历史 | 00是项目状态真源；workorder/00_workorder_status.md逐单跟踪 | history只追溯；关闭工单与旧失败不能自动恢复待办 |

现行架构名称为32核心战斗Domain、33战斗表现架构，不再使用phase1/phase2表示现行职责。91/92考据与纸面审查已在history；导航/航空实施日志、状态旧快照及审计报告均由README历史区检索。

## 当前项目完成状态

详细状态以 `docs/00_project_status.md` 为准。当前摘要：

### 战斗规则与工程边界入口

战斗规则、操作、公式和公共数值分别查10/11/12/13；环境与设施效果查18，Domain权威查32/35/37/38，导航工程约束查t00/t01。本文只提供路引，不复制完整规则、公式或预算。当前运行倍率及验证有效性见00，精确配置以data为准。

### 完成状态摘要（2026-10-12核对）

- 14份日期工单全部原范围完成或用户验收关闭，未关闭0份；当前性能、平衡与体验接受用户既有确认。旧失败、Candidate及缺少细分记录保留历史，不自动重开工单。
- 8教学＋15挑战共23正式关卡、目标/增援/进度和奖励已接入；全部19个有岸关卡使用新版地图。48角色均有获取来源（默认3／教学6／挑战39），固定正式关卡初始编队覆盖26名，勿混为全48固定出场。
- 自定义四规模、112敌军阵容、实际Cost三难度匹配、预览/重抽/冻结重开已接入；全阵容逐一实战不能由抽样烟测推定。
- 全48角色56px远景、独立人物/舰装、公共航空A默认/B显式、技能闪回、无框头像与六分类操作说明已接入；W07/W08/W13/W14已关闭。10-10镜头缩放协调已补登记于00。
- 2026-10-12按当前设置页窗口尺寸与音乐三模式更新旧下拉框数量断言，场景专项260/260通过；只改测试，旧259/260保留历史。
- L-02静止前舰与接回修复后三次263.9秒正常结算，12次恢复全完成，原306次重复拒绝及四告警消失；W06/W11/W12已关闭，旧边界只留档。
- 60项音效及5标题／6战斗／2结算音乐已接入；W09音效与W10中大型挑战已验收关闭。音乐循环区段、退出淡出及设备细分证据与W09分开判断，取消的指挥官音乐方向不恢复。
- 海面最后水体色块和天气第十版雨线仍为具体候选；后续优先反馈评审。特别行动六关目前仅设计，设施新内容由新特殊剧情关卡承接，不用AI代打调平。
- Windows最新交付仍为10-02免安装包，10-10预设更新不等于重新导出；实际Windows运行交人工。当前详情、验证日期与后续范围见00，[旧阶段记录](docs/history/00_project_status_through_20261010.md)只用于追溯。

## 代码、数据与资产路引

- `scripts/infrastructure/bootstrap/data_registry.gd`：以 Autoload 注册的运行时数据与资产总入口；源码按 Infrastructure 职责归档，Autoload 名称仍为 `DataRegistry`。
- `data/ships|weapons|skills/`：第一期与第二期角色规则配置；`data/levels/` 目前只有第一期角色关卡。
- `data/progress/ship_acquisition.json`：48 名角色互斥获取分类和唯一奖励来源；`scripts/infrastructure/data/ship_acquisition_catalog.gd` 负责校验与查询。旧存档已拥有角色保留。
- `data/visuals/`：投射物表现、武器表现和 VFX 播放参数。
- `scripts/application/battle_session.gd`：战斗流程和当前大部分规则协调。
- `scripts/application/navigation/route_planner.gd`、`navigation_request_broker.gd`、`trajectory_planner.gd`：稀疏战略走廊、统一请求预算和常规/紧急动力学候选；`scripts/domain/services/ship_motion_service.gd` 负责同源推进、转向、水流、制动与简化倒车积分。
- `scripts/domain/services/terrain_collision_field.gd`、`scripts/infrastructure/data/terrain_collision_field_loader.gd`：静态占用/距离下界查询和 checksum/revision 加载回退；正式派生物位于 `data/terrain/collision_fields/` 与 `collision_field_manifest.json`，确定性烘焙/差分入口为 `tools/terrain/bake_collision_fields.py`、`validate_collision_fields.py`。
- `scripts/presentation/battle/ship_unit_view.gd`：角色战场视图；`animation_state_machine.gd` 管理角色动画状态。
- `scripts/presentation/battle/battle_effect_director.gd`：消费战斗事件并协调角色、投射物、炮弹轨迹、VFX 和伤害跳字。
- `scripts/presentation/battle/projectile_view.gd`、`shell_flight_view.gd`、`battle_vfx.gd`：公共战斗表现节点。
- `assets/characters/{character_id}/processed/`：已完成角色运行时资产；只有 `postprocess_plan.json` 不代表资产完成。
- `assets/vfx/`：公共战斗与角色模板特效；`assets/environment/`、`assets/environments/`：陆地、天气和海面运行时资源。
- `assets/environment/land/source/`：已审核的海岸透明母版、构图参考和权威参考遮罩；`assets/environment/land/land_*_16x9_runtime.png` 与 manifest 是运行时入口。`assets/environment/land/generated/` 只允许作为被 Git 忽略的临时工作区，不保留 raw/chroma-key 中间图。
- `assets/environment/qa/`：只保留被文档或 manifest 引用的最终 QA 证据；临时审查面板写入系统临时目录或被忽略的 `reports/`。
- `addons/terrain_authoring/`：仅编辑器使用的地形作者插件，操作、依赖和发布边界见目录内 `README.md`。
- `tools/data/`：角色批次配置生成；`tools/art_pipeline/record_codex_builtin_art.py` 与 `generation_contract.py`：Codex 内置原生 Alpha 来源登记和源图门禁；`generate_character_art.py` 是非 Codex 环境的可选直连 API 入口；`tools/art_pipeline/` 其余脚本：角色、UI、场景和陆地资产处理与验收；`tools/scene_review/`：正式战斗场景全图与镜头 QA。
- `tools/music/`：ACE-Step 服务器生成、逐曲显存预检、可恢复任务、WAV 下载校验与人工评审页；入口和限制见目录内 `README.md`。端到端编排使用 `.agents/skills/tiny-sea-war-music-review/SKILL.md`。显存不足必须等待用户明确决定，不得擅自放行、切卡、降配或清理其他任务。
- `tools/music/reviews/registry.json`：音乐版本与人工评审历史台账；`registry.md` 为派生阅读表，使用 `tools/music/tracker.py` 登记、导入反馈和记录改良计划。新版本关联父版本并重新评审，不能将生成成功当作旧问题已解决。
- `artifacts/simulations/`：被 Git 忽略的可再生模拟结果，不是运行时资源或配置真源；`artifacts/.gdignore` 阻止 Godot 导入其中的 CSV/报告。
- 正式音频源包与运行时派生物位于 `assets/audio/`；音乐遵循 `50`，运行时清单与总线约定见 `25`，当前接入与验收边界见 `00`。

## Python 工具环境

- 项目 Python 工具统一使用仓库根目录的 uv `.venv`，Python 小版本约束为 `3.12`，当前由 `.python-version` 精确固定为 `3.12.13`；不得使用系统、Homebrew 或 Conda 的裸 `python`、`python3`、`pip`、`pip3` 执行本项目工具。
- `pyproject.toml` 是 Python 直接依赖声明真源，`uv.lock` 是完整解析版本真源；首次检出或锁文件更新后运行 `uv sync --locked` 创建/同步 `.venv`，不要单独重复安装 Pillow。
- Python 工具、审计和单测统一使用 `uv run --locked python ...`；需要直接解释器路径时使用 `.venv/bin/python`。新增或调整依赖后使用 `uv add <package>`，并同时提交 `pyproject.toml` 与 `uv.lock`。
- `.venv/` 与 uv 下载缓存不得提交。受限执行环境无法写入用户级 uv 缓存时，只将 `UV_CACHE_DIR` 指向系统临时目录，不要在正式资源目录留下缓存。

## Codex 工作指引

### 音乐评审迭代授权

- 用户于2026-10-02明确：“每次收到评审意见后就可以生成新版”。收到音乐聊天意见或评审JSON后，核对版本、归档原话并直接按反馈生成修订候选、验证和交付试听页，无需再询问是否制作下一轮；用户要求仅记录、暂停或取消时按最新指令处理。
- 已明确采用的曲目进入源包，退出待采用迭代；未改动的待评审曲可复用。新版本保留来源链，不继承旧版采用或循环验收。逐曲GPU映射、模型和显存门禁仍按音乐skill执行，容量不足或生成失败不属于本授权的自动重试范围。

- 2026-10-02第六轮评审已取消指挥官音乐方向，三候选全部拒绝：不再生成或改良该方向。温柔109秒／轻快81秒已正式源采用，本轮没有待采用曲目；历史音频与反馈保留，后续播放／循环任务按另行请求开展。

- 用户最新要求音乐用更加文学的方式命名，不能偏离原提示词与对应风格；风格／特点单独存style_description，不强制放入曲名前缀。当前名及命名依据写入离线catalog与源记录，保留旧名、稳定ID、源哈希及历史评审，不覆写已试听manifest。具体命名见assets/audio/music/naming_record_20261002_literary.json，此前命名记录原样保留。

### 玩家体验与验收备注

- 玩家应能理解目标、表达意图、确认执行结果，并从失败中找到下一次可改变的选择。新增机制之前先确认它是否创造真实取舍，避免仅增加按钮、百分比或难以察觉的判定。
- 自动测试通过只证明对应契约；数据加载、资源交付、Headless 行为、带画面性能和真人可玩性必须分别记录，不得相互替代。AI 对 AI 的胜率不是人类通关率，首次尝试、学习后重试和熟练玩家需要分开观察。
- 先确认命令、导航和舰种参与正常，再决定关卡难度；不得用敌方 Cost、伤害、取消条件或更低目标胜率掩盖卡住、零贡献和不可执行的操作。
- 玩家不承担调试职责：提示使用人类可读的行动和原因，技术保护终态明确为本局无效；内部原因码保留在诊断数据中。开发验证入口与正常游玩进度分开。
- 玩家命令失败反馈应局部、简短、可合并，不弹窗、不抢焦点、不移动镜头，也不打断连续输入；只反馈该玩家提交的命令，不泄露敌方或 AI 内部状态。
- 手动控制的注意力成本必须换来可感知的时机、目标或区域控制收益；扩大舰队规模前先验证多选、编组与信息分层，不能只增加逐舰操作数量。
- 优先打通短而完整的学习与重玩体验，再扩展内容；战后解释应引用真实战斗事实，不能用固定泛化建议假装完成复盘。角色素材齐备不等于朝向、装配和实机识别完成。
- 2026-09-27 本轮玩家体验整改明确暂缓潜艇执行/开火行为与性能优化，两者继续沿既有工单管理；相关表现调研不构成修改其规则、AI 或导航预算的授权。

### 开始任何任务

- 先检查 `git status --short`，保护用户已有改动，不回滚无关文件。
- 先读 `docs/00_project_status.md`，确认本次任务是在补缺口、扩展部分完成项，还是维护已完成基线。
- 涉及 Python 工具时先运行 `uv sync --locked`，后续命令使用 `uv run --locked python ...`，不得因当前 shell 激活了 Conda 或裸 `python3` 可用而绕过项目 `.venv`。
- 根据任务类型阅读上面对应文档；如果涉及代码落点，再读 `docs/34_implementation_map.md`。
- 用 `rg` 或 `rg --files` 查找引用和调用点，避免只改一处留下旧路径、旧字段或旧规则。
- 只改和任务直接相关的文件。设计文档、数据、代码、美术资产不要顺手大范围重构。

### 设计改动

- 统一审核先判断文档所有权，再检查完整性、重复、矛盾和信息越界。技术方案、生产管线可以保留其自有实现职责、迁移步骤与命令；玩法/美术规范不复制实施清单、精确字段表或测试历史。主设计保留必要不变量、拒绝语义和反例，不以缩短篇幅代替契约完整性。

- 审查一个或一组编号设计文档的完整性、边界、重复、矛盾、冗余、拆分、合并、存档或删除候选时，使用项目级 `$tiny-sea-war-audit-design-docs`；实施审查结论时必须同步 `docs/00_project_status.md`、本文件、`docs/README.md` 和全部受影响路引。
- gameplay的10–18及关卡分册分别拥有规则、操作、公式、基线、角色、关卡、AI、体验与环境效果；模拟平台19在architecture，验证方法36在validation。编号是稳定ID，目录决定职责。跨文档引用指向真源，不在非权威文档复制完整公式、数值表、状态、路径或测试历史。
- 改核心规则时，同时检查玩法、公式、数据结构、Domain 和操作文档是否需要同步。
- 改数值时区分三层：`13_balance_baseline` 是范围，`14_character_balance_design` 是角色草案，`data/` 是当前可运行配置。
- `20-26` 数据契约只保留字段名、类型、必填性、枚举、默认值、引用和加载校验；玩法语义、数值依据、Domain 状态机、实现完成度、文件入口和实验结论分别回到对应真源。
- 改美术职责时保持边界：角色方向/个体/生产归 `40/41/46`，公共战斗特效归 `42`，场景视觉归 `43`，UI 归 `44`，资产语义接口归 `45`，场景资产生产归 `47`。
- 审计报告只记录历史判断；如它与编号较低的主设计文档冲突，优先更新主设计文档，并在审计相关处说明状态。

### 程序改动

- Godot 运行时代码按现有目录分层：`scripts/domain` 放规则，`scripts/application` 放流程协调，`scripts/presentation` 放场景和 UI，`scripts/infrastructure` 放数据、资产和外部支持。
- Domain 层不要依赖 Godot 场景树、HUD 节点或具体贴图路径。
- 表现层不要重新实现命中、伤害、装填、侦查等规则；这些规则应来自 Domain 或配置。
- 资产路径优先通过 `DataRegistry.assets` 或 `scripts/infrastructure/assets/asset_catalog.gd` 的语义查询，不在表现代码里手拼文件名。
- 新增配置字段时，同步更新所属 `docs/21-26` 专题契约、加载校验和相关测试；只有新增类别或公共约定变化时才更新 `docs/contracts/20_data_schema_design.md`。

### 美术资产与管线

- 美术目录总入口为 `assets/README.md`；统一目录、命名、路径格式及固定路径兼容例外见 `docs/contracts/45_art_asset_interface_design.md`。角色/UI/小地图通过 `DataRegistry.assets` 语义查询，不在表现层拼接 PNG 路径。

- 角色运行时资产真源在 `assets/characters/{character_id}/processed/`，原始 sheet 和 QA 产物不要混作运行时入口。
- UI 运行时语义清单参考 `assets/ui/qa/ui_asset_manifest.json`，导出倍率目录位于 `assets/ui/export/`。
- 改角色后处理或资产验收时，优先复用 `tools/art_pipeline/` 中现有脚本。
- 角色正式拆件统一进入 `postprocess_trial_sheets.py`；已有手写 `CropSpec` 继续使用，新源包在 `meta/{id}_crop_specs.json` 标定逐件源图提示，并由 `postprocess_generated_character.py` 适配后调用同一个旧裁切核心。缺少规格不得回退网格硬切；生产计划不等于裁切规格。 扩框后的安全边距须排除未被提示选中的邻件组件，保留全部选中组件及原有柔边；VFX 提示必须覆盖所有断开图元，不能只标中心。原生 Alpha 直接保留，不随旧裁切流程恢复白底/绿幕清理。
- 新旧后处理共用 `delivery_review.py` 生成带包哈希和逐件 Alpha/裁切证据的交付核验清单；初始视觉结论只能是 pending。技术 `batch_ready/technical_ready` 不代表视觉通过，`delivery_ready` 还要求当前文件版本逐件有审查人、观察记录和 pass/polish；源图、配置或成品变化必须复验。详见 `46` 第 5.1 节。
- 内置源图审查可用 `record_codex_builtin_art.py {id} --prepare-review` 准备，换图后旧结论不能直接沿用；正式交付检查使用 `batch_character_art.py --require-delivery --report-tag <批次名> ...`，防止技术通过被当作交付通过，或单批报告覆盖全期结果。
- Codex 会话中新角色生图直接使用账户内置 ImageGen 请求透明 PNG，并用 `uv run --locked python tools/art_pipeline/record_codex_builtin_art.py {id}` 登记逐图哈希、Alpha 事实和人工结论，不要求 SDK 或用户 API Key；底层模型/请求 ID 未暴露时必须如实记录为 Codex 托管，不得伪造直连 API 信息。非 Codex 环境才显式使用 `generate_character_art.py`。绿幕只有在原生 Alpha 失败后，带 `--allow-legacy-chroma-fallback` 与非空失败原因时才可作为最后保底。
- 改场景环境资产时先按 `47` 区分视觉图层与规则几何；贴图 alpha 和 `visual_regions` 不得直接成为碰撞、浅水或通行真相。
- 生图 raw、抠色结果、单次审查面板、缓存和临时导出不得留在正式资源目录；通过审核后只保留可复现所需的源母版/参考遮罩、运行时资产和被路引引用的最终 QA 证据。
- 模拟报告可留在被忽略的 `artifacts/simulations/` 供本地复核，但不得保留 Godot 为 CSV/文本生成的 `.import`、`.translation` 等导入副产物。
- 不为每个角色重复制作公共炮弹、鱼雷、命中、水柱、范围圈等资产；优先使用公共类别资产加角色覆盖层。

### 验证

- 文档重命名或字段重命名后，用 `rg` 检查旧名称是否残留。
- 程序改动后，优先运行项目已有测试或最小可行的 Godot/脚本校验。
- 资产或 UI 改动后，检查对应 QA 报告、manifest 或运行时引用是否仍然能找到文件。
- 如果暂时无法运行测试，在最终回复中明确说明原因和剩余风险。
- 更新阶段完成度时，必须同时记录数据加载、运行时接入、关卡覆盖、资产覆盖和自动/人工验收，不以单一维度代替整体完成度。
- 旧高压图绝对性能预算与字段P99测量保留原日期，单条A*仍不可抢占；用户已确认当前总体性能/体验并关闭相关工单，不以旧测量重开验收，也不将用户确认改写为旧指标重测达标。新改动仍分别记录自动正确性、带画面性能和人工验收。
