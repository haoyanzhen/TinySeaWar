# 第二期角色历史考据验证

> 复核日期：2026-07-17
>
> **功能与边界**：本文是第二期角色历史原型、时期、舰种映射和主要武装轮廓的独立考据记录，只用于解释游戏抽象与争议，不是当前配置、平衡或实现状态真源。当前精确配置见 `data/`，角色设计见 `docs/14_character_balance_design.md`，完成状态只见 `docs/00_project_status.md`。

## 1. 验证范围与方法

本报告只验证 `docs/14_character_balance_design.md` 第二期 24 名角色的历史原型、时期、舰种映射和主要武装轮廓，不评价 Cost、伤害、冷却或技能强度。静态纸面审查另见 `docs/92_character_phase2_static_balance_review.md`。

验证采用两步法：先确认舰名、舰级、完工状态与服役时期，再确认主炮、鱼雷管、舰载机或特殊设备的数量级。游戏中的射程、装填、伤害、侦查和技能均不作为史实主张。舰种映射按 MVP 六舰种执行，前无畏舰、驱逐领舰和未完工航母会单独标注。

结论等级：

- `通过`：原型与装备轮廓可由公开舰史相互印证。
- `通过（抽象）`：史实成立，但游戏合并了改装期、挂架或舰种。
- `条件通过`：属于未完成方案或跨时代映射，必须保留标签和说明。

## 2. 逐舰验证

| 角色 | 史实核对要点 | 游戏化处理 | 结论 |
|---|---|---|---|
| 弗莱彻 | 弗莱彻级；5 门 127mm 单装炮、2 座五联装 533mm 鱼雷管，并具反潜兵装。 | 两用炮、防空与深水炸弹按玩法拆成不同能力。 | 通过 |
| 克利夫兰 | 克利夫兰级轻巡；4 座三联装 152mm 主炮，强两用炮与近程防空，无鱼雷。 | 保留无鱼雷炮巡身份，以主炮作为 `E`。 | 通过 |
| 巴尔的摩 | 巴尔的摩级重巡；3 座三联装 203mm 主炮，无鱼雷，后期雷达火控突出。 | 技能强化雷达校射，不把雷达写成直接伤害来源。 | 通过 |
| 刺尾鱼 | 猫鲨级潜艇；6 具艏管、4 具艉管，以积极巡逻战绩著名。 | 高风险缩短雷击循环是角色化，不宣称史实装填速度。 | 通过 |
| 杰维斯 | J 级驱逐领舰；3 座双联装 120mm 主炮、2 座五联装鱼雷管。 | `FlotillaLeader` 转译为护航光环。 | 通过 |
| 贝尔法斯特 | 城级轻巡；4 座三联装 152mm 主炮、三联装鱼雷管，战时雷达与防空持续强化。 | 采用二战中后期综合状态，不绑定某一天的完整装备表。 | 通过（抽象） |
| 光辉 | 光辉级装甲航母；装甲飞行甲板是核心识别，舰载机规模小于部分同时代大型舰队航母。 | 用高舰载机 HP 与较慢循环表现，不直接换算甲板装甲厚度。 | 通过 |
| 拥护者 | U 级潜艇；以艏向鱼雷兵装和地中海近海作战为主要轮廓。 | 只提供舰首发射扇区，省略甲板炮。 | 通过（抽象） |
| 塔什干 | 苏联驱逐领舰；高速，大型舰体，后期配置 3 座双联装 130mm 炮与 3 座三联装鱼雷管。 | 采用后期主炮状态；超基线航速是玩法强化。 | 通过（抽象） |
| 恰巴耶夫 | 68-K 型轻巡；4 座三联装 152mm 主炮、2 座三联装鱼雷管。 | 以战后完成状态作为角色原型。 | 通过 |
| 甘古特 | 甘古特级无畏舰；4 座三联装 305mm 主炮，低速老式战列轮廓明确。 | 采用现代化后综合防护倾向，未逐项复刻副炮改装。 | 通过（抽象） |
| K-21 | K 级远洋潜艇；6 具艏管、4 具艉管，并有远洋侦察与巡逻经历。 | 省略甲板炮和布雷能力，避免引入 MVP 外机制。 | 通过（抽象） |
| Z23 | 1936A 型驱逐舰；后期重炮配置为 1 座双联装加 3 座单装 150mm 炮，2 座四联装鱼雷管。 | 当前数据统一抽象为 4 座双联装主炮；这是规则可执行性优先的强化抽象，不复刻混合单/双联布局。 | 通过（抽象） |
| 纽伦堡 | 莱比锡级轻巡；3 座三联装 150mm 主炮，完工时 4 座三联装鱼雷管。 | 采用完工时鱼雷轮廓；不把后续拆除的艉部鱼雷管混入同一史实状态。 | 通过 |
| 沙恩霍斯特 | 沙恩霍斯特级主力舰；3 座三联装 283mm 主炮，高航速。 | MVP 归类为战列；省略后期加装鱼雷，突出高速炮战。 | 通过（抽象） |
| 齐柏林伯爵 | 德国航母计划首舰，下水但未完工服役；计划配置航空联队与重型舰炮。 | 所有战斗表现均是假想完成状态，必须保留 `UnfinishedCarrier`。 | 条件通过 |
| 秋月 | 秋月级防空驱逐舰；4 座双联装 100mm 两用炮、1 座四联装 610mm 鱼雷管。 | 以防空护航为主，雷击低于第一期岛风。 | 通过 |
| 高雄 | 高雄级重巡；5 座双联装 203mm 主炮；改装后可见四联装鱼雷管配置。 | 采用后期鱼雷轮廓，技能为夜战风格转译。 | 通过（抽象） |
| 翔鹤 | 翔鹤级舰队航母；高速、大型航空队，适合持续协同攻击定位。 | 舰载机数量按单次出击规模抽象，不代表全舰载机总数。 | 通过（抽象） |
| 伊-19 | 巡潜乙型潜艇；6 具艏鱼雷管，并能搭载水上侦察机。 | 只保留艏管与单机侦察，未加入甲板炮。 | 通过 |
| 逸仙 | 中国自建小型巡洋舰；建成时主要重炮为 1 门约 152mm 与 1 门 140mm。 | MVP 归入轻巡；未把小口径炮全部列为独立底座。 | 通过（抽象） |
| 长春 | 原苏联 7 型驱逐舰“纪录”号，转交中国后为“四大金刚”之一；早期为 130mm 炮与 533mm 鱼雷配置。 | 固定采用接收初期状态，不混入后期导弹改装。 | 通过 |
| 定远 | 定远级铁甲舰；4 门 305mm 主炮、2 门 150mm 炮，属于前无畏舰时代。 | MVP 映射为战列并赋予 `PreDreadnoughtMapping`，防空近乎为零。 | 条件通过 |
| 海龙 | 原美国 Tench 级潜艇 USS Cutlass，转交中华民国海军后服役；具 10 具 533mm 鱼雷管。 | 按 6 艏、4 艉的美式舰队潜艇轮廓拆组，省略现代化声呐细节。 | 通过（抽象） |

## 3. 争议与修正记录

- 初稿曾把纽伦堡鱼雷写成 2 座三联装，经核对完工状态后改为 4 座三联装；若未来选择 1941 年后的状态，应同步减少鱼雷底座并写明年份。
- 初稿曾把逸仙 140mm 炮写成 2 座，经核对建成武装后改为 1 座。其余小口径炮不进入当前主武器表。
- “沙恩霍斯特”在不同资料中可称战列巡洋舰或战列舰；MVP 只支持六舰种，归入 `Battleship`，不借此宣称学术分类唯一。
- “定远”不是现代意义上的无畏舰或二战战列舰。采用 `Battleship` 只是规则层最近似映射，时代差异通过低速、近射程、低防空和标签表达。
- “齐柏林伯爵”从未完成战备服役。计划舰载机数量、舰炮和防护可作为轮廓参考，任何技能与实战性能都属于游戏假设。

## 4. 资料索引

本轮使用以下公开舰史入口交叉核对舰名、舰级、武装与完工状态；页面中的游戏数值不作为史实来源。资料索引支持本报告的历史语境，不意味着单一页面独立证明表中全部细节；有争议的精确装备状态仍应在后续修改时保留逐条来源。

- 美系：[Naval History and Heritage Command — USS Fletcher](https://www.history.navy.mil/research/histories/ship-histories/danfs/f/fletcher.html)、[USS Cleveland](https://en.wikipedia.org/wiki/USS_Cleveland_(CL-55))、[USS Baltimore](https://en.wikipedia.org/wiki/USS_Baltimore_(CA-68))、[Naval History and Heritage Command — USS Wahoo](https://www.history.navy.mil/content/history/nhhc/browse-by-topic/ships/submarines/wahoo-ss-238.html)。
- 英系：[Imperial War Museums — HMS Belfast](https://www.iwm.org.uk/visits/hms-belfast)、[HMS Jervis](https://en.wikipedia.org/wiki/HMS_Jervis)、[HMS Illustrious](https://en.wikipedia.org/wiki/HMS_Illustrious_(87))、[HMS Upholder](https://en.wikipedia.org/wiki/HMS_Upholder_(P37))。IWM 页面只用于舰船身份和保存状态入口，不单独支持本文的武装数量判断。
- 苏系：[Tashkent-class destroyer](https://en.wikipedia.org/wiki/Tashkent-class_destroyer)、[Chapayev-class cruiser](https://en.wikipedia.org/wiki/Chapayev-class_cruiser)、[Gangut](https://en.wikipedia.org/wiki/Russian_battleship_Gangut_(1911))、[K-21](https://en.wikipedia.org/wiki/Soviet_submarine_K-21)。
- 德系：[Z23](https://en.wikipedia.org/wiki/German_destroyer_Z23)、[Nürnberg](https://en.wikipedia.org/wiki/German_cruiser_N%C3%BCrnberg)、[Scharnhorst](https://en.wikipedia.org/wiki/German_battleship_Scharnhorst)、[Graf Zeppelin](https://en.wikipedia.org/wiki/German_aircraft_carrier_Graf_Zeppelin)。
- 日系：[Akizuki](https://en.wikipedia.org/wiki/Japanese_destroyer_Akizuki_(1941))、[Takao](https://en.wikipedia.org/wiki/Japanese_cruiser_Takao_(1930))、[Shōkaku](https://en.wikipedia.org/wiki/Japanese_aircraft_carrier_Sh%C5%8Dkaku)、[I-19](https://en.wikipedia.org/wiki/Japanese_submarine_I-19)。
- 中系：[Yat Sen](https://en.wikipedia.org/wiki/Chinese_cruiser_Yat_Sen)、[Rekordny / Chang Chun](https://en.wikipedia.org/wiki/Soviet_destroyer_Rekordny)、[Dingyuan](https://en.wikipedia.org/wiki/Chinese_ironclad_Dingyuan)、[Naval History and Heritage Command — USS Cutlass / Hai Lung](https://www.history.navy.mil/research/histories/ship-histories/danfs/c/cutlass-ss-478.html)。

## 5. 历史验证结论

第二期 24 名角色中，22 名为“通过”或“通过（抽象）”；2 名为必须持续显著标注的条件通过对象，即未完工航母齐柏林伯爵和跨时代舰种映射定远。没有发现虚构实舰或把未服役方案误写为已服役舰的情况。本记录曾为后续美术和数据设计提供输入；当前数据、资产覆盖和运行状态必须分别回到 `data/`、对应美术文档与 `docs/00_project_status.md` 判断。
