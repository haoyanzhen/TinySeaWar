# 音乐生成与人工评审工具

从仓库根目录使用 `uv run --locked python tools/music/music.py …`。仅用 Python 标准库；服务器执行使用部署的 `.venv`，无需向仓库添加 GPU 依赖。设计真源见 [50](../../docs/50_music_playback_and_asset_design.md)。

## 输入与运行

`server.json` 保存已授权服务器的位置，不含密码。SSH 使用已有密钥／agent、BatchMode 与严格主机校验。工具不安装软件、不启动服务、不释放其他进程显存、不改 GPU、不自动降低模型配置。可通过 `--config` 指定其他部署；API 必须为远端 loopback。

批次清单示例见 `example_batch.json`：`version=1`，稳定批次 `id`，`tracks` 中每项包含唯一 `id`、展示 `title`、`category`、完整 API `request`。类别为 title/battle/victory/defeat/neutral，不再单列菜单。请求固定种子、单曲单批、WAV、XL SFT + 4B；提示词和曲式由 agent 按用户目标编写。示例为 150 秒标题主主题，仅演示结构；实际时长按用户要求或设计目标填写。

```sh
uv run --locked python tools/music/music.py check --manifest tools/music/example_batch.json
uv run --locked python tools/music/music.py e2e --manifest tools/music/example_batch.json --output reports/audio/my_batch
# 中断后使用相同清单继续；也可分步运行：
uv run --locked python tools/music/music.py generate --manifest tools/music/example_batch.json
uv run --locked python tools/music/music.py fetch --manifest tools/music/example_batch.json --output reports/audio/my_batch
uv run --locked python tools/music/music.py review --output reports/audio/my_batch
uv run --locked python tools/music/music.py serve --output reports/audio/my_batch --port 8767
```

`e2e` 依次生成、下载、验证、制作页面；`serve` 单独前台运行，仅监听 127.0.0.1。打开其输出的 `/listen.html`。浏览器意见保存在本机 localStorage，评审人应导出 JSON 并交回项目；导入时核对批次和音频哈希。页面仅标记“偏好候选”，不自动晋升为正式资产。

## 显存决策门禁

每次提交新曲前读取 `nvidia-smi`，并核对运行中服务进程树的 `CUDA_VISIBLE_DEVICES` 和 API 加载模型。健康检查或 GPU 信息不明时直接报错，不能靠授权文件绕过。

所有时长在服务 GPU 映射和已加载模型核验通过后，统一检查空闲显存至少 **16384 MiB**。时长按用户要求或设计 50 的类别目标填写，不默认缩成 90 秒，不因超过历史测量时长单独要求试跑批准；清单接受任意有限正数时长，服务实际支持范围以返回结果为准。16 GiB 是运行余量门槛，不是任意时长都能成功的容量保证，也不按时长编造显存估算。已有服务占用不重复计入空闲显存。服务拒绝或生成失败时保留证据并停止，不自动缩短时长或重试。

显存不足时返回 `needs_user_decision`，本地退出码 3，不发生成 POST。报告 GPU UUID、总/用/空闲显存、任务参数、门槛及原因，请用户决定等待、调整任务，或按当前条件试跑。**超时等待不代表同意。** 不自动终止现有任务、切卡或降配。

只有用户明确决定继续，agent 才可创建临时 `approval.json`，通过 `--approval` 传入：

```json
{
  "batch_sha256": "check 返回的批次哈希",
  "gpu_uuid": "check 返回的 GPU UUID",
  "free_floor_mib": 12000,
  "expires_at": 1790000000,
  "user_decision": "用户实际授权原文及本批次适用范围"
}
```

`expires_at` 为 UTC Unix 秒，使用时有效期不得超过一小时；`free_floor_mib` 取向用户报告并获准时的空闲容量，不得为绕过后续检查故意降低。仅适用于该批次、该 GPU。每首仍重新测量，空闲显存下降到批准下限以下再次停下。记录随曲保存。授权不能保证不会 OOM；若发生失败就停止，保留证据交用户选择，不无限重试。

## 恢复、文件与确定性边界

远端产物在 `<remote_root>/outputs/batches/<batch_id>/`，保留原始清单、请求、提交前快照、授权、任务 ID、结果和 WAV。相同批次 ID 不允许更改内容；改提示词、种子、模型或参数需新 ID。服务器跨批次文件锁防止本工具重复并发，但不锁住其他 GPU 使用者；检查与分配之间仍有竞争窗口。

- 提交前持久化 `submitting` 意图；收到任务 ID 后持久化 `submitted`，轮询超时后重跑只查询原任务。
- 若在提交响应到达前断线，会留下 `submitting`。检查同曲 submission.json／API 日志找回已受理的 task_id，再人工修复 state 到 submitted；无法确定则先报告用户，**不得删除状态盲目重发**。
- 明确失败标记 failed，重跑仍停止。定位原因后由用户决定是否以新批次重试。
- 成功产物用哈希核验；下载不打包权重、密钥或服务器配置，解包仅接受清单列出的平面文件。
- 固定清单与种子、不可变批次、可恢复任务和稳定报告是工具的确定性保证。GPU 模型跨软件版本、硬件或后端不承诺逐位相同。

本地输出用被忽略的 `reports/audio/<batch_id>/`。`review` 可处理部分下载，缺失曲目显示未就绪。它不生成新音乐，适合重新制作页面和交付。

## 评审跟踪与改良版本

长期台账是 [reviews/registry.json](reviews/registry.json)，可读数据表是 [reviews/registry.md](reviews/registry.md)。台账和 `reviews/sources/` 历史归档均由 Git 忽略，仅保留本地及服务器备份；WAV 和临时评审页仍放在被忽略的 reports 中。台账保存提示词、音频哈希、本地／远端位置、技术检测快照、全部人工意见、独立制作计划及父子版本关系，不依赖浏览器暂存作为长期记录。

```sh
# 先运行 music.py review 取得校验报告，再登记整批；旧批次可指定实际远端归档目录。
uv run --locked python tools/music/tracker.py register --batch-dir reports/audio/my_batch --remote-dir /home/hyz/server/musicGen/outputs/batches/my_batch
# 导入人工评审页导出的 JSON；保留评审人和意见原文，注明来源。
uv run --locked python tools/music/tracker.py import --feedback /path/to/my_batch.review.json --source '用户试听页评审'
# 计划与人工意见分开，计划更新保留历史，不改变人工结论。
uv run --locked python tools/music/tracker.py plan --record my_batch/track_id --priority high --actions '降低背景小提琴密度，保持主旋律'
# 单曲改良批次关联原版；新版本必须重新评审，不继承原版结论。
uv run --locked python tools/music/tracker.py register --batch-dir reports/audio/revision_batch --parent my_batch/track_id --remote-dir /home/hyz/server/musicGen/outputs/batches/revision_batch
uv run --locked python tools/music/tracker.py render
```

这些命令不调用 GPU，默认写入上述台账；测试或独立实验可在子命令前用 `--registry <path>` 指定隔离台账。所有修改后自动重建 Markdown 表，请勿直接编辑派生表。`--parent` 首期仅支持单曲改良批次；多首改良可分为单曲批次登记。改用新批次/新曲目 ID，不能在原 ID 下替换 WAV。

人工结论包括待评审、偏好候选、需改良和不采用；它们不是正式音乐验收状态。新版本登记后显示待复查，原版问题不自动关闭。复查时应明确哪些旧问题已解决、哪些仍存在；相关结论写入新版本意见，版本链保留旧记录。制作计划的优先级由制作方明确记录，不伪装成用户原话。

导入先验证整份反馈的批次哈希、音频哈希、曲目唯一性和问题时间范围，失败不写入任何意见。相同来源/评审人/内容重复导入不会新增事件；按评审日期排序保留历史，全页导出中未填写的待评审行不覆盖已有结论。为识别音乐版本，修改过音频后必须重新生成清单版本与技术报告。

台账登记不等于音频备份。清理 reports 前确认远端或正式源资产中仍有对应哈希的 WAV；台账保存的来源、参数和评审记录不能代替原音频。首批用户聊天反馈原文快照位于 `reviews/sources/20260929_chat_feedback.json`，实际时间点未给出的不自行补造。

## 信号检查范围

PCM16 WAV 检查实际时长、48kHz 双声道、削波样本、每秒 RMS、连续低电平区间和低电平尾部，保存原音频 SHA256。小于 -55 dBFS 的连续三秒区段供人工复查，五秒以上尾部特别标记；安静配器可能误报，因此不自动剪辑或判为失败。不同位深需显式增加解析能力，不静默误读。

这些检查不能证明没有抖动、人声、配器问题、音乐提前收束或循环接缝；真峰值、LUFS、循环母带仍属正式资产后期。保留原 WAV，不自动补静音、拼接或响度归一化掩盖问题。

```sh
uv run --locked python -m unittest discover -s tools/music -p 'test_*.py' -v
```

## 局部重绘

清单曲目可指定 `source_audio={batch_id,track_id,sha256}`，引用服务器既有批次 WAV；请求使用 `task_type=repaint` 与有限的 `0 <= repainting_start < repainting_end <= audio_duration`。禁止直接传任意源路径。提交前校验源文件哈希与路径，再执行相同显存门禁；失败不提交。重绘仍保存完整输出，不承诺未重绘区逐样本保持；需局部拼接时保留原始生成与后期版本，记录区间、淡化、源哈希及独立验收。

2026-09-30 部署验证：重绘请求可受理，但当前服务器音频解码器缺少 `libavutil.so`，源音频读取失败。局部重绘尚未端到端验证通过，需修复服务器解码依赖后由用户决定重试；不要将接口存在视为功能已可用。源文件校验后复制至服务器临时目录供API读取，保留失败记录与临时输入用于诊断。

后续诊断更正：现有 soundfile 可正常读取原始 WAV；首因是服务在 app 工作目录解析了错误的相对路径，随后备用 TorchCodec 才报告缺库。源文件复制至任务独立临时目录并使用绝对路径可被 soundfile 正常读取，样本一致，无需安装系统库或重启服务。重绘生成与听感验收另行记录。

批次 `title_revision04_repaint_fixed_20260930` 的三处请求技术执行完成，但其派生版 `title_revision04_local_edits_20260930` 已被人工指出重绘段不具音乐性，不能视为修复成功。原始输出、反馈及后期来源继续保留。

当前新提交的重绘必须显式传 `chunk_mask_mode=explicit`。部署版本 `ca1e85fe9430179831e6bc6be790c332190a3866` 的 CPU 复现显示：`auto` 将值 2 写入 bool 遮罩，条件遮罩覆盖整曲；`explicit` 才准确表示指定区间。独立的源音频注入遮罩仍正确，不能据此声称整曲都被替换。已提交旧任务可以继续查询，旧清单也可评审，不静默改写历史请求。

该部署的 `repaint_strength` 越高越偏离原曲；balanced + 0.7 实际只在前 30% 步骤注入原曲。保守修补可从 0.2–0.3 开始，同时提供整曲风格与局部意图。部署代码使用模式解析出的交叉淡化值，不能假设请求中的 `repaint_wav_crossfade_sec` 已生效；最终局部拼接须独立记录实际淡化。显式遮罩单变量试验仍出现片段电平偏高，因此遮罩修正不等于听感问题已解决，音乐性与接缝必须人工确认。

## 文件存放约定

- 候选、生成中间产物和历史试听页：`reports/audio/<batch_id>/`，保留批次位置以维持台账及对照链接。
- 正式采用源版：`assets/audio/music/source/<asset_id>/`；统一索引 `assets/audio/music/catalog.json` 仅供离线制作，不是运行时 manifest。源包由 `.gdignore` 隔离。
- 长期评审：`tools/music/reviews/`；收到的原始反馈及 attributed 副本另按批次归档到 `reviews/sources/`，索引记录原位置与哈希。不得改写原始决定或历史日志中的路径。
- 生成工具、服务器配置和模板继续位于 `tools/music/`，不要把每轮脚本或临时 WAV 放入工具目录。


## 已采用标题曲的运行时构建

`uv run tools/music/build_runtime.py` 使用脚本内固定的 SoundFile 0.13.1，将 `assets/audio/music/catalog.json` 中的采用 WAV 按恒定增益派生为48kHz双声道Ogg，不压缩动态、不裁剪或修改源包。逐曲测量编码后综合响度、响度范围、真峰值并写入 `data/audio/music_manifest.json`；只读校验使用 `python3 tools/music/build_runtime.py --check`。构建依赖ffmpeg/ffprobe作测量，Vorbis由libsndfile编码，分块写入避免大缓冲编码失败。

完整曲目循环、播完再硬切与手动立即硬切是当前播放实现，切歌不加播放器淡入淡出；清单中的人工循环与混音状态保持pending，恢复点空数组按播放设计进入下一首。此工具不提交GPU生成任务，也不改变采用源包或历史评审。
