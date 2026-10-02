# 已采用音效制作源包

60项人工采用音效按分类/工单ID归档。每项包含 `selected.wav`（采用试听版）、`raw.wav`（完整生成源）和 `provenance.json`（生成、后期、测量及选择来源）。两份音频均与原文件SHA256一致，本次不重新剪辑、归一化或编码。

- [素材索引](inventory.md)：逐项名称、候选与采用版链接。
- [只读试听](listen.html)：全部已采用版本，打开即可逐条播放。
- [manifest](manifest.json)：60项素材与105项需求映射，62项取消单列。
- [验证记录](validation.json)：120份WAV校验、格式、分类及待复查项。
- `disposition_snapshot.json`、`reviews/`、`production/`：整理时的决策快照、人工反馈与批次回执。

本包约119.69MB音频，采用版统一48kHz PCM24。9项循环尚需接缝实听；14项超过旧目标时长、5项源浮点峰值超范围记录保留，采用版过采样峰值警告0。人工选材已完成，这些制作记录不自动否定采用，也不代表循环/混音验收完成。

`.gdignore`隔离制作源，manifest不是游戏运行时API。运行时应另建派生资源和正式绑定，不引用reports或该源包。完整规范见[52](../../../../../docs/52_sound_effect_design_and_production.md)。

历史未采用及取消候选仍在原reports/audio批次保留，未删除或恢复排产。来源目录仅为追溯信息，本包播放无需原服务器。重建入口：`uv run --locked python tools/sfx/package_selected.py`；源包内容不一致时失败，不覆盖已归档版本。
