# 音乐资产目录

正式采用的无损源版统一存放于 `source/<asset_id>/`。离线索引为 [catalog.json](catalog.json)，不是游戏运行时 manifest。

| 曲目 | 时长 | 源包 |
| --- | --- | --- |
| 迎风启航 | 80 秒 | [title_fleet_departure_v1](source/title_fleet_departure_v1/README.md) |
| 港灯与约定 | 87 秒 | [title_harbor_promise_v1](source/title_harbor_promise_v1/README.md) |
| 海风来信 | 90 秒 | [title_sea_letters_v1](source/title_sea_letters_v1/README.md) |
| 晴海相伴 | 84 秒 | [title_sunny_companions_v1](source/title_sunny_companions_v1/README.md) |
| 林间寻光 | 90 秒 | [title_woodland_discovery_v1](source/title_woodland_discovery_v1/README.md) |

每个源包保留 `source.wav`、`source_record.json`、原始采用反馈、响度测量及已有生成／后期证据。历史日志中的旧路径是当时执行事实，不随目录迁移改写。技术检查内的 `human_status` 是当时自动报告快照；当前源版采用状态以 `source_record.json` 顶层状态及原始采用意见为准。

`source/.gdignore` 隔离制作源包，避免 Godot 自动导入和导出。源音频不因归档而重编码或归一化。五首运行时 Ogg 已派生至 `runtime/`，播放清单为 `data/audio/music_manifest.json`；冷启动《迎风启航》，随后默认不重复随机轮播；设置可选择顺序轮播／随机轮播／单曲循环，选择保存本机。编码采用恒定增益，约 −20 LUFS，源包不修改。重建：`uv run tools/music/build_runtime.py`；只读核验：`python3 tools/music/build_runtime.py --check`。完整曲目重复和硬切已接入；三轮循环、曲池混音、乐句恢复点与模型使用条款仍待人工验收。当前主机 CoreAudio 输出启动失败，真实设备录音尚未取得；证据见 `reports/audio/title_runtime_20261001/validation.md`。

历史候选与试听页保留在 `reports/audio/<batch_id>/`，服务器备份按原批次 ID 保存；长期台账及反馈归档位于 [tools/music/reviews](../../../tools/music/reviews/README.md)。设计要求见 [50](../../../docs/50_music_playback_and_asset_design.md)，生产流程见 [51](../../../docs/51_music_generation_and_review_pipeline.md)。
