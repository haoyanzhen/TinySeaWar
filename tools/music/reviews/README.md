# 音乐评审记录

历史台账 `registry.json`、派生表 `registry.md` 及 `sources/` 全部由 Git 忽略，仅保留本地及服务器备份。本目录说明仍纳入 Git；正式源资产包中的必要来源与采用证明继续随资产保存。

- `registry.json`：版本、哈希、原始评审事件和制作计划的长期台账。
- `registry.md`：由 tracker 生成的可读视图，不手工修改。
- `sources/<batch_id>/`：原始评审与注明归属的导入副本，逐字节保留；`sources/index.json` 保存原位置及哈希。
- `sources/20260929_chat_feedback.json`：早期聊天反馈快照。

第十五轮反馈原文件在成功读取后消失，`read_snapshot` 是读取内容快照，不宣称保留了原文件字节；详情见对应 `feedback_archive_note.txt`。空白评审人只在 attributed 副本中补归属，不改原始选择或意见。

已采用源包和离线索引见 [音乐资产目录](../../../assets/audio/music/README.md)。历史候选和页面保留在被 Git 忽略的 `reports/audio/`；不可把此目录清理视为音频已备份，恢复须核对台账记录的服务器路径和哈希。归档来源中的历史路径保留原样，当前正式源资产路径由音乐索引提供。
