# 文档重组实施与内容保全记录（2026-10-12）

> **历史记录 / 功能与边界**：本文记录按[01结构规划](../01_documentation_structure_plan.md)执行的文档搬迁、改名、拆分、引用适配和内容保全证据。现行文件检索见[README](../README.md)，项目当前完成度只见[00](../00_project_status.md)。本文不新增规则或实施待办。

## 1. 实施范围

按规划建立gameplay、contracts、architecture、presentation、production、technical、validation、history八类职责目录。45份原编号文档映射无目的地冲突，其中39份搬迁，32/33/52按职责改名，91/92移入history；00、34及technical四份保留原位置。

新增15-3教学、15-4挑战、53音效生产三个分册。15保留公共规则，52保留声音标准；逐关表、奖励、时间线及生产交付分别进入唯一目标。旧路径未保留可编辑副本；Git中的删除表示源路径迁移，内容已在新路径。

原45份文件逐项去向保留在01。AGENTS改为任务约束与权威路由，README维护完整目录与任务阅读路线，34继续负责代码位置。审计inventory递归覆盖分册和technical，排除history；增加可复跑的链接/锚点/字面路径检查脚本。

开始前工作区已有上一轮审计、结构规划、状态历史及场景测试改动。本轮保存当时文本基线进行比较，不用HEAD替代用户已有内容；未回滚这些改动，也未提交Git。

## 2. 保全方法与差异边界

迁移前保存1658份仓库及相关个人技能文本快照。40份非拆分专题（排除00/34、15/15-1/52）中，34份与基线经过相同路径适配后逐字一致；剩余30、33、35、36、45、t02仅修改目录分类、音效生产/听感、关卡公共规则/逐关配方的权威引用。核心规则、数值、字段、ID和拒绝条件未改。

关卡拆分按源行逐一分配归属：355条非空源行中342条在仅规范化文档地址后原样覆盖，13条为登记的边界/标题/引用/混合句改写；132条表头/数据行（其中2行只更新内部章节引用）和15条分隔行全部覆盖。原15-1正文保留，全部数字词元覆盖。混合句的教学/挑战部分各有唯一去向；表头为独立表的必要复用。

音效拆分保留19个原样正文块各一次；唯一混合段按句号/分号拆得5个分句，5/5保留。分类、取消ID、候选、PCM24/PCM16、声道、淡化、来源及人工听感边界均保留。

人工登记改写只包括标题/职责、分册导航、混合句拆分及失效内部引用。完整教学/挑战规则没有复制回公共15，声音标准没有复制回生产53。历史正文只适配路径，保留原日期、失败及当时判断。

### 2.1 关卡源行去向

| 源15行段 | 源所属标题 | 目标文件 | 目标标题 |
|---|---|---|---|
| 1–100 | 教学、挑战与自定义战斗关卡设计 | 15_battle_level_design.md | 公共关卡规则与内容导航 |
| 101–101 | 3.4 局部环境使用原则 | 15-3_tutorial_level_design.md | 教学关卡设计：T-01～T-08 |
| 103–103 | 3.5 关卡地图配方 | 15_battle_level_design.md | 3.5 逐关地图配方入口 |
| 105–114 | 3.5 关卡地图配方 | 15-3_tutorial_level_design.md | 3.5 教学关卡地图配方 |
| 115–129 | 3.5 关卡地图配方 | 15-4_challenge_level_design.md | 3.5 挑战关卡地图配方 |
| 130–152 | 3.5 关卡地图配方 | 15_battle_level_design.md | 3.6 出生与增援方案 |
| 153–172 | 3.7 中大型挑战的地图制作约束 | 15-4_challenge_level_design.md | 3.7 中大型挑战的地图制作约束 |
| 174–174 | 3.8 教学与小型挑战采用新版地图 | 15_battle_level_design.md | 3.8 新版地图的共用约束 |
| 176–176 | 3.8 教学与小型挑战采用新版地图 | 15_battle_level_design.md | 3.8 新版地图的共用约束 |
| 178–183 | 3.8 教学与小型挑战采用新版地图 | 15-3_tutorial_level_design.md | 3.8 教学部署适配 |
| 184–185 | 3.8 教学与小型挑战采用新版地图 | 15-4_challenge_level_design.md | 3.8 小型挑战部署适配 |
| 187–202 | 3.8 教学与小型挑战采用新版地图 | 15_battle_level_design.md | 3.8 新版地图的共用约束 |
| 203–204 | 4.2 胜率与时长 | 15-3_tutorial_level_design.md | 4.2 教学胜率与时长 |
| 205–205 | 4.2 胜率与时长 | 15-4_challenge_level_design.md | 4.2 挑战胜率目标 |
| 206–214 | 4.2 胜率与时长 | 15_battle_level_design.md | 4.2 胜率与时长 |
| 216–260 | 5. 第一章：教学 | 15-3_tutorial_level_design.md | 5. 第一章：教学 |
| 262–394 | 6. 第二章：挑战·小型海战 | 15-4_challenge_level_design.md | 6. 第二章：挑战·小型海战 |
| 396–408 | 9. 自定义战斗 | 15_battle_level_design.md | 9. 自定义战斗 |
| 409–409 | 9.1 编成与消耗用量 | 15-1_custom_battle_roster_design.md | 公共自定义规则的关联 |
| 410–418 | 9.1 编成与消耗用量 | 15_battle_level_design.md | 9.1 编成与消耗用量 |
| 419–419 | 9.2 舰船解锁 | 15-4_challenge_level_design.md | 8.6 十关共用的结算与简报约定 |
| 420–423 | 9.2 舰船解锁 | 15_battle_level_design.md | 9.2 舰船解锁 |
| 424–424 | 9.2 舰船解锁 | 15-3_tutorial_level_design.md | 教学奖励汇总 |
| 425–439 | 9.2 舰船解锁 | 15-4_challenge_level_design.md | 挑战奖励汇总 |
| 440–455 | 9.2 舰船解锁 | 15_battle_level_design.md | 9.2 舰船解锁 |
| 456–456 | 10.1 静态检查 | 15-3_tutorial_level_design.md | 教学内容验收 |
| 457–461 | 10.1 静态检查 | 15_battle_level_design.md | 10.2 动态调参边界 |
| 462–472 | 10.3 中大型挑战的内容验收边界 | 15-4_challenge_level_design.md | 10.3 中大型挑战的内容验收边界 |
| 473–474 | 10.3 中大型挑战的内容验收边界 | 15_battle_level_design.md | 10.2 动态调参边界 |
| 477–486 | 自定义环境变化预设 | 15-1_custom_battle_roster_design.md | 自定义环境变化预设 |
| 488–492 | 中大型挑战雷雨过境 | 15-4_challenge_level_design.md | 中大型挑战雷雨过境 |

关卡主动改写：公共标题与开头收窄；源101环境句、源203目标胜率句按教学/挑战拆开；源151通关表引用改为15-3/15-4；源409匹配概述迁15-1后改自引用；源486挑战时间线改链接；原“见3.8”“3.7制作门禁”改为本分册/分册链接。所有原数值与条件保留。

### 2.2 音效段落去向

| 原文段落 | 唯一目标 | 处理 |
|---|---|---|
|原§1，3个正文段|52 §1|19个原样块之一|
|原§2，制作决策/105项/索引段|53 §1|原句迁移；新增34定位句|
|原§2，9行声音分类表|52 §2|完整表原样保留|
|原§2，K01–K10段|52 §2|原样保留|
|原§2，N04/S05/U08/U09/F07/U14段|52 §2|原样保留|
|原§3，事实到声音首段|52 §3|原样保留|
|原§3，三候选/参数/独立生成/取消排产段|53 §2|原样保留|
|原§3，模型CLI/回执/调研/TangoFlux段|53 §2|原样保留|
|原§3，评审batch/哈希/返工/文字优先段|53 §2|原样保留|
|原§4，源包位置和隔离段|53 §3|原样保留|
|原§4，6项文件清单|53 §3|完整列表原样保留|
|原§4，历史候选/来源/离线使用段|53 §3|原样保留|
|原§5，后期记录/源波形/重建/声道段|53 §4|原样保留|
|原§5，循环标记用途句|52 §4|原句保留|
|原§5，至少三轮试听分句|52 §4|原分号改句号|
|原§5，必要时派生且保留采用版分句|53 §4|原分句独立成句|
|原§5，目标时长/尾音句|52 §4|原句保留|
|原§5，四类测量/失真句|53 §4|原句保留|
|原§5，哈希/格式/ID/需求/许可段|53 §4|原样保留|
|原§5，总线/独立派生/不引用reports/状态边界段|53 §5|原样保留|
|原§6，48kHz PCM16/声道/0.5秒交叉淡化/哈希/源保护段|53 §5|原样保留|
|原§6，听感/设备/疲劳/关闭工单边界段|52 §4|原样保留|

音效唯一正文标点变动是“三轮试听；必要时派生并保留采用版”拆成两句，分别归声音验收与生产；两项原要求完整保留。两文件新增边界和互引，不新增触发或制作授权。

## 3. 引用与技能

全量适配本仓库文档、工单、素材README/QA、工具文档及工具生成元数据的旧路径。Python工具和场景测试中仅同步文档路径字符串/说明，游戏数据、运行逻辑、资产内容及已有测试修正保持。

仓库内同步审计、教学关、小型挑战、音乐评审、海面评审五个技能及审计criteria/inventory。教学与挑战技能分别读15-3/15-4；状态只写00，设计和位置分别写所属专题/34。海面技能原已失效48入口改为34/00/47。审计技能按目录判职责，不再把19或46归错层。

个人技能同步tiny-sea-war-art-pipeline的SKILL及三个引用文件、tiny-sea-war-cover-art的SKILL，共5个仓库外文件，仅调整文档路径，不改变美术生产、回退或授权规则。仓库外文件不出现在本仓库Git差异中。

## 4. 验证

检查命令：

```bash
uv sync --locked
.agents/skills/tiny-sea-war-audit-design-docs/scripts/audit_design_docs.sh
uv run --locked python .agents/skills/tiny-sea-war-audit-design-docs/scripts/validate_design_docs.py .agents/skills /Users/qingyue/.codex/skills/tiny-sea-war-art-pipeline /Users/qingyue/.codex/skills/tiny-sea-war-cover-art
git diff --check
```

实际结果：递归inventory覆盖47份现行编号文档，47/47有边界声明，缺失字面docs引用为0。AGENTS、docs及相关技能共72份Markdown，438条本地链接、8个章节锚点和428项按文件去重的字面docs路径检查通过；原状态历史中93旧文件名与94未创建提议名两处保留为明确历史提及。检查脚本通过正反例：拒绝缺失文件和不存在的锚点，接受中文同名标题的去重锚点。

1658份文本基线范围内，仓库/相关个人技能的342条设计文档链接有效；39个迁移旧路径引用剩余0、45个目的地唯一且存在、39个旧源路径均不存在。仅同步文档路径的3个Python工具通过语法解析，新检查脚本语法通过，inventory的bash -n通过；运行时与数据没有额外变化。Git差异空白检查通过。

7个相关技能quick_validate通过。初次使用项目环境运行外部技能校验器因缺PyYAML退出；改用uv临时依赖层后全部通过，没有修改pyproject.toml或uv.lock。复跑形式为：`uv run --locked --with PyYAML python /Users/qingyue/.codex/skills/.system/skill-creator/scripts/quick_validate.py <skill-folder>`。

没有执行Godot、战斗矩阵、素材生成或人工音画验收；文档迁移校验不替代这些证据。原场景测试改动保留，未重跑或改写其既有通过记录。

## 5. 基线指纹

下表为迁移开始时原45份文档的SHA256；比对基于原工作区文本，保留用户已有修改。它是迁移证据，不是运行时配置指纹。

| 原稳定编号/文件名 | 迁移前SHA256 |
|---|---|
| 00_project_status.md | `6fb29ac884f16d25135aa8c3a8d0b077fe6a16e2afaae8553fcecc8e7b5fef74` |
| 10_game_core_mechanics.md | `c0a99e58a597ab8d34e09fa5e0d0442cefc56ca0867ff5ebd56ee0b432d27fc8` |
| 11_game_operation_design.md | `9014c455b6f2f59c181cd3f6beaab3952fc76d4789e10cc2db60e83be39448c7` |
| 12_combat_formula_design.md | `ee10ed65585541267987cfa8cb8e9f13580dff461ac985fff3bbad4541d6f600` |
| 13_balance_baseline.md | `15d0e188ce88a7658ebe445ed9985d4e90557b6d4f50f6d80dd9e614b81158bf` |
| 14_character_balance_design.md | `a337b7dbb89b8b9be470091883c36f4ca35d24e9b4883f32e8c39fcdc3ec4652` |
| 15-1_custom_battle_roster_design.md | `9a4dd5c7f0c9de1c53325c08e13bb11c652771ea9e8ed4b3bc6d848d494af377` |
| 15-2_special_operations_design.md | `81b6a7238258ca8d066ad028b28c175f0f9ad31b9b051625f4b0439d4202601e` |
| 15_battle_level_design.md | `ace3f55549c765b3ce34d20c6ffc1011135326e969b897203b27ad818e931ad3` |
| 16_enemy_ai_behavior_design.md | `e28ddd55c1121dc10aadf0930207c5f18fcf15b69d1937629485f07d35c994ec` |
| 17_play_design.md | `25de0e730698ac0b9572c471b4eed73dabd149ae9a6aff3a32e27a39844e1a48` |
| 18_facility_weather_effect_design.md | `9aa9ab382dd137f7e2ee638e9c3052c0ecdc54c65dfb9af8efa542d9f076ddbd` |
| 19_battle_simulator_design.md | `d8c1ff6e5b558584a32ccd8ba32cda46bdfdef8322129c3f2b0bed6e0b23608a` |
| 20_data_schema_design.md | `240260311aaad842e7b4b69acf3e1621ca921386bbad982b99c690367acc002d` |
| 21_combat_data_schema.md | `90455873df1a127dcedf09ccd3a58f41196f3fac4f9bc1c4212890bafe3ca39e` |
| 22_scene_environment_data_schema.md | `363db26b9f82926aba2ce6a09858965a6315e037389c3c7f241170b9734d1738` |
| 23_level_progress_data_schema.md | `3fc64bfdf51f76c7b5e05b68b04364396118009b34fc3b8b8e8820335ea77251` |
| 24_ai_data_schema.md | `2b7ba82247f2ee45e7a08cf6a75b5f7fccc970b90dee7272fe09f58df1bcb50b` |
| 25_presentation_data_schema.md | `68ddce4fddb320cffe6867b3e766dd9b4ee0ca1b37c59b0523cbedb97bda5084` |
| 26_simulation_data_schema.md | `d0ee3d5a78a6269be15273eb6bbfcabe799a3f1c6f31c4785a2a4f86aa5ea2b8` |
| 30_technical_architecture.md | `87b78541169acb3491ef50af992b74c56104704a99577d08712593ada3d8a9d6` |
| 32_domain_design_phase1.md | `6f4e388502afc9c00cc5c5cbc331c98bea936e6c5d6c65e3848f67fc8ed66fd7` |
| 33_domain_design_phase2.md | `07df4251eda45897fb70b338bbc72cf44ffe3dd9331d29bad466cd464a2b6b58` |
| 34_implementation_map.md | `20257f4baee207c48f902ebf18fd51a44d27b3b06e61d09efd1986600d41e328` |
| 35_scene_combat_domain_design.md | `a720241fa4117e0b83a8a757e01a005289de82fc1858a53e03e10d79b898ec8a` |
| 36_balance_testing_design.md | `48eb2af6707fcc55cd18b49a5538260b0986c82369c8050735d0e0b4af9c3502` |
| 37_environment_runtime_domain_design.md | `c6f3868f479ae68ab70d3dd4fbf33e51ad712d0f422b4d39c6350e1412acabc7` |
| 38_facility_combat_domain_design.md | `8a80c5258b6b4330c02a9c53572ed46ddeb31f56414b7f3bd6172b6210982a58` |
| 40_art_direction_design.md | `975fc24272b452db7930bc7a60789b39d9b2a0f7c1410304c3d5204bd2aea5bb` |
| 41_character_art_design.md | `35cc3e2fe9c89b898f56404aa4963f99e0d39ae0480923312852105bdd1a94cb` |
| 42_combat_art_design.md | `8134efc8d6ce9a6d3cfae409322b8034c1716d4fed5238dd3c73e93f964b7a87` |
| 43_scene_art_design.md | `a4cd4f4d22d63d3869f8bc96ad595d2484a5efe56a0125f225f326adeb7ef6e1` |
| 44_ui_art_design.md | `840d7fcd1675252eedea0334c974e3133b3084b749c1acdcfc612a3c46133f32` |
| 45_art_asset_interface_design.md | `9cf4e74f68c0141b33c141589e454ca5d5f3b1ced986abc8d0dd79dddf09bab5` |
| 46_character_art_asset_pipeline.md | `c96239ad077bf2e0d992415ef3506c85a9d4cfa929e667b9c5d1883e378055f5` |
| 47_scene_art_asset_pipeline.md | `ff483b35b9397855a91dbe7120e0221de13d2331f1ec89871242f74355513a79` |
| 50_music_playback_and_asset_design.md | `5769a318173c742b7ace851dfb544fa633c5ff14c9d59da4b03fbdf55a74072d` |
| 51_music_generation_and_review_pipeline.md | `866a1e29f13f5aecf11d288464aa54c92d8684901e79ddb9717f6ae9af912fc9` |
| 52_sound_effect_design_and_production.md | `6edf929aad370322a3efc78fe83033f6c4ecfb2516f5b9406f72cafd1c969435` |
| 91_character_phase2_historical_validation.md | `7506b29d07a81ef872bfd8c4411355efc5c0cf7a6753ee684e925a3d41091851` |
| 92_character_phase2_static_balance_review.md | `0675ef6f88e4c26f83b8bc51ab6334c8b258a5ce00a3af206be4f7af2d4ebc71` |
| t00_coastal_ai_performance_solution.md | `d445e5de577d98646b6f887480d6114c9d7b9f2b9097181e39ff80b834f87565` |
| t01_inertial_navigation_and_emergency_avoidance.md | `04b01bdbc4e9fdbea79f297fdae5118ad70ae126bf306c9b53f532bc4e810b28` |
| t02_level_objective_reinforcement_progress_solution.md | `f0cd12c9be927ad20ff59b155d971c0023d1234d455c2dbcc3385cd5ddd38d72` |
| t10_carrier_combat_presentation_solution.md | `c84e8e6c0afcc89327d7c335149a93221ec0d8ae3714b957e03545488b0b0ff9` |
