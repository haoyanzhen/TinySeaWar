# 音乐资产目录

正式采用的无损源版统一存放于 `source/<asset_id>/`。离线索引为 [catalog.json](catalog.json)，不是游戏运行时 manifest。

| 曲目 | 时长 | 源包 |
| --- | --- | --- |
| 迎风启航 | 80 秒 | [title_fleet_departure_v1](source/title_fleet_departure_v1/README.md) |
| 港灯与约定 | 87 秒 | [title_harbor_promise_v1](source/title_harbor_promise_v1/README.md) |
| 海风来信 | 90 秒 | [title_sea_letters_v1](source/title_sea_letters_v1/README.md) |
| 晴海相伴 | 84 秒 | [title_sunny_companions_v1](source/title_sunny_companions_v1/README.md) |
| 林间寻光 | 90 秒 | [title_woodland_discovery_v1](source/title_woodland_discovery_v1/README.md) |
| 万帆凌涛（终局关卡） | 180 秒 | [battle_finale_distant_decisive_v1](source/battle_finale_distant_decisive_v1/README.md) |
| 静海相守（克制战斗） | 120 秒 | [battle_watchful_route_v1](source/battle_watchful_route_v1/README.md) |
| 余潮再航（失败结算） | 30 秒 | [result_regroup_defeat_v1](source/result_regroup_defeat_v1/README.md) |
| 同心逐浪（通用战斗曲池之一） | 120 秒 | [battle_main_same_heading_v1](source/battle_main_same_heading_v1/README.md) |
| 破浪争锋（通用战斗曲池之一） | 114 秒 | [battle_main_rhythmic_clash_v1](source/battle_main_rhythmic_clash_v1/README.md) |
| 凯旋余晖（胜利结算） | 25 秒 | [result_victory_homeward_v1](source/result_victory_homeward_v1/README.md) |
| 海风相伴（温柔战斗） | 109 秒 | [battle_gentle_companions_v1](source/battle_gentle_companions_v1/README.md) |
| 乘风协奏（轻快战斗） | 81 秒 | [battle_light_concerto_v1](source/battle_light_concerto_v1/README.md) |

每个源包保留 `source.wav`、`source_record.json`、原始采用反馈、响度测量及已有生成／后期证据。历史日志中的旧路径是当时执行事实，不随目录迁移改写。技术检查内的 `human_status` 是当时自动报告快照；当前源版采用状态以 `source_record.json` 顶层状态及原始采用意见为准。

《远海决战》按2026-10-02评审暂收入最后一关素材，原180秒WAV保持不变；具体关卡ID、循环、混音与游戏接入待确认。它不作常规大型海战默认曲；第六轮已取消专属指挥官音乐制作，大型战从适配的通用曲选择，映射待接入。离线索引category区分title与battle，标题构建器只处理title，旧条目缺省按title兼容，避免终局曲进入标题曲池。

第二轮《守望航线》120秒与失败《再整航装》30秒均获用户明确收录，源WAV原样保存；曲目采用不代表实际关卡映射、结果开头／余韵边界、循环或混音已通过。标题构建器同样跳过battle与defeat源条目，运行时仍为既有五首标题曲。

第三轮通用C《同航迎敌》按“收录为正式素材，但不唯一”原样收入源包，通用曲池继续允许其他曲目。自动报告116–119秒低电平提示保留；采用不代表循环或运行时完成。该轮之后为九个采用源包；第四轮进一步采用通用A114秒及胜利25秒，当时共十一源包；第六轮再采用温柔／轻快两曲，当前十三源包，五首标题已接入，另八首战斗／结算仅采用源版。

按最新要求，正式名采用贴合原提示词的文学意象，风格／特点单独保存在catalog和source_record的style_description。命名依据及上一名称见[naming_record_20261002_literary.json](naming_record_20261002_literary.json)；此前前缀命名记录[naming_record_20261002.json](naming_record_20261002.json)原样保留。稳定ID、源WAV哈希及历史试听manifest不变。

|当前曲名|风格与特点|
|---|---|
|万帆凌涛|宏阔舰队决战管弦；圆号主题、中低弦、低铜管与稀疏打击乐，规模与战略张力并存。|
|静海相守|温柔克制护航；单簧管、钢琴与轻弦，安静而坚定地保护同伴。|
|余潮再航|克制钢琴与单簧管；承认失落、温柔反思，保留重整与再出发的希望。|
|同心逐浪|明朗动漫海战；单簧管、钢琴与圆号问答，突出同伴互信和协同迎敌。|
|破浪争锋|明快管弦海战；圆号、中低弦与克制定音鼓，紧张律动中保留坚定与希望。|
|凯旋余晖|明亮胜利短句后转温暖余韵；圆号庆功，单簧管与钢琴安静归航。|
|海风相伴|温柔动漫战斗；单簧管主旋律、柔和钢琴和轻中提琴伴奏，温暖同伴感与安静勇气。|
|乘风协奏|轻快动漫冒险；单簧管、中提琴断奏、柔和吉他与短长笛回应，弹性节奏和同伴协作。|

第六轮两曲采用及指挥官方向取消见[采用记录](adoption_record_20261002_round06.json)。两首源WAV保留裁尾与末4秒淡出，入库未再次加工；轻快曲原评审loop_checked=true保留，循环点仍待标定。没有待采用的第六轮曲目，不制作第七轮指挥官候选。

`source/.gdignore` 隔离制作源包，避免 Godot 自动导入和导出。源音频不因归档而重编码或归一化。五首运行时 Ogg 已派生至 `runtime/`，播放清单为 `data/audio/music_manifest.json`；冷启动《迎风启航》，随后默认不重复随机轮播；设置可选择顺序轮播／随机轮播／单曲循环，选择保存本机。编码采用恒定增益，约 −20 LUFS，源包不修改。重建：`uv run tools/music/build_runtime.py`；只读核验：`python3 tools/music/build_runtime.py --check`。完整曲目重复和硬切已接入；三轮循环、曲池混音、乐句恢复点与模型使用条款仍待人工验收。当前主机 CoreAudio 输出启动失败，真实设备录音尚未取得；证据见 `reports/audio/title_runtime_20261001/validation.md`。

历史候选与试听页保留在 `reports/audio/<batch_id>/`，服务器备份按原批次 ID 保存；长期台账及反馈归档位于 [tools/music/reviews](../../../tools/music/reviews/README.md)。设计要求见 [50](../../../docs/50_music_playback_and_asset_design.md)，生产流程见 [51](../../../docs/51_music_generation_and_review_pipeline.md)。

### 战斗运行时（2026-10-02）

八首采用源的派生Ogg见runtime，清单见data/audio/battle_music_manifest.json。通过 `uv run --locked python tools/music/build_runtime.py --battle` 重建，`--check`核验。源版采用、运行时技术接入与人工循环/混音验收分别记录；当前战斗完整循环、结果单次后安静，不能视作已验收主体/余韵循环。详见docs/00_project_status.md。
