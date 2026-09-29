# 音乐生成与人工评审流程

> **功能与边界**：本文简述音乐从服务器生成到人工评审的生产路径与 skill 入口。音乐风格、播放策略和正式资产标准归 [50](50_music_playback_and_asset_design.md)，当前完成度归 [00](00_project_status.md)。详细命令、容量门禁和恢复方法以 [工具说明](../tools/music/README.md) 为准；本文不定义游戏运行时播放器。

## 1. 生成路径

```text
用户需求与试听反馈
  → 编写批次清单：用途、提示词、时长、固定种子
  → 检查服务状态、目标 GPU 与空闲显存
  → 服务器逐曲生成，记录任务 ID 和原始结果
  → 下载 WAV，校验哈希、时长与分段音量
  → 制作本地试听评审页
  → 人工标注问题、选择候选、导出意见
  → 按反馈新建版本，或进入正式循环与混音制作
```

当前默认部署如下；连接配置的唯一维护入口是 [server.json](../tools/music/server.json)，迁移服务器时以该配置为准。

| 项目 | 默认位置／配置 |
| --- | --- |
| 服务器 | `hyz@192.168.252.143` |
| 部署根目录 | `/home/hyz/server/musicGen` |
| 模型 | ACE-Step XL SFT + 4B LM，PyTorch 后端 |
| 计算设备 | 第 0 张 A100 80GB；不自动切换其他 GPU |
| 生成服务 | 用户级 `musicgen.service`，远端本机 `127.0.0.1:8001` |
| 远端批次产物 | `~/server/musicGen/outputs/batches/<batch_id>/` |
| 本地候选与评审材料 | `reports/audio/<batch_id>/`，被 Git 忽略 |

连接使用已有 SSH 身份与严格主机校验，不在清单中保存密码。工具不自动安装模型、启动服务或清理其他任务。

## 2. 工具与 skill

确定性执行工具位于 [tools/music](../tools/music/README.md)，统一入口为 `music.py`：

| 命令 | 职责 |
| --- | --- |
| `check` | 读取 GPU 容量、核对服务 GPU 映射与模型，评估本批次是否可执行 |
| `generate` | 逐曲复检显存、提交任务并保存结果；中断后继续查询原任务 |
| `fetch` | 下载产物、核验哈希并制作评审页 |
| `review` | 对已有本地 WAV 重新检查并生成评审页，不调用 GPU |
| `e2e` | 串联生成、下载、检查与页面制作 |
| `serve` | 在本地 loopback 地址提供评审页，不调用 GPU |

端到端编排使用项目 skill：[$tiny-sea-war-music-review](../.agents/skills/tiny-sea-war-music-review/SKILL.md)。它负责理解用途、吸收历史反馈、编写提示词与清单、调用工具、处理容量决策及交付人工试听；重复执行逻辑留在工具中，不为每批另写生成脚本。

可直接请求：“使用 `$tiny-sea-war-music-review`，按 50 号设计生成指定音乐候选，并准备人工评审页。”这不等于授权在显存不足时继续执行。

从仓库根目录运行，先按 [示例清单](../tools/music/example_batch.json) 准备本批次 `manifest.json`：

```sh
uv run --locked python tools/music/music.py check --manifest reports/audio/my_batch/manifest.json
uv run --locked python tools/music/music.py e2e --manifest reports/audio/my_batch/manifest.json --output reports/audio/my_batch
uv run --locked python tools/music/music.py serve --output reports/audio/my_batch --port 8767
```

环境首次建立或锁文件改变时先执行 `uv sync --locked`；生成成功后打开 `serve` 输出的 `/listen.html`。

## 3. 显存与恢复约束

- 每首新提交前重新检查空闲显存。**显存不足必须停下并交由用户决定**，不能以一般生成授权、等待时间或上一首成功替代本次判断。
- 超出已验证容量配置时也先报告并取得用户的试跑决定；当前自动放行基线和保守余量见工具说明，不将其当作任意时长的容量保证。
- 显存信息或服务 GPU 映射无法核实时停止；不得自动切卡、降配、终止其他任务或降低门槛。
- 用户明确同意后，按工具说明记录绑定批次、GPU、容量下限与有效期的授权；后续容量跌破获准下限时再次停止。
- 固定批次 ID 对应不可变清单；改变提示词、种子或参数须新建批次。已完成曲目复用产物，已提交曲目继续查询，提交结果不明或明确失败时不盲目重发。
- 确定性指清单、任务记录、恢复行为和校验过程可追溯；不承诺 GPU 推理跨环境逐位一致。

## 4. 人工评审与交付

每批保留请求、参数、任务 ID、结果、来源记录、WAV、哈希和分段检查报告。评审页支持单曲播放、问题时间点、偏好／修改意见、浏览器暂存及 JSON 导出／导入；反馈绑定批次与音频哈希，避免混用版本。浏览器暂存不替代交付，评审结束应导出意见并保留在对应批次目录。

自动检查仅提示时长异常、低电平区间、长尾或削波等问题。抖动、旋律提前结束、配器主次、胜负情绪和循环接缝仍由人工试听判定。候选通过技术检查不等于正式音乐完成；接受后按 `50` 继续循环、混音与实机验收，不能直接将试听产物视为运行时资产。

## 5. 长期评审跟踪

[音乐评审跟踪表](../tools/music/reviews/registry.md) 按一个音频版本一条记录汇总用途、人工结论、改良优先级、反馈、计划与后继版本；[JSON 台账](../tools/music/reviews/registry.json) 保存原始请求、哈希、文件位置和历次评审，二者纳入 Git。`tracker.py` 提供登记、导入评审 JSON、更新制作计划和重建表格，具体命令见工具说明。

改良版通过父版本标识关联原曲，新版从待复查开始；原有问题与意见不被覆盖，也不因生成新版而自动关闭。用户原话、制作方计划、自动信号提示分开记录。评审 JSON 必须与登记的批次和音频哈希匹配，重复导入去重，较早意见不覆盖较新结论。偏好候选不等于正式资产验收。此台账用于内容制作，不属于游戏运行时配置；清理试听目录前仍须确认原音频可恢复。
