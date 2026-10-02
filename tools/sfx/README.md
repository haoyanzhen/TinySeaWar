# 音效候选制作

设计见 [52](../../docs/52_sound_effect_design_and_production.md)。本目录是制作工具，不是运行时音频系统。

```sh
uv sync --locked
uv run --locked python tools/sfx/build_catalog.py
```

`catalog_source.tsv` 为中文分类与剪辑目标，`english_briefs.json` 是逐条英文声音描述；构建器输出 105 需求映射、122 素材和 366 个固定种子候选。修改提示词后必须使用新批次 ID，已提交批次不可原地替换。

## 当前可用运行时

服务器使用 `/home/hyz/server/sfxGen/modelscope-runtime/run.sh`，通过独立 ComfyUI 核心加载已部署的 ModelScope Stable Audio 3 Small SFX 权重，完全离线，不启动 HTTP 服务。`modelscope-runtime/README.md` 与 `deployment.json` 保存版本、模型哈希和调用契约。不修改 musicGen/vllm 服务。

```sh
# 服务器执行：一个请求包含15条音效；不同内容使用新批次路径。
/home/hyz/server/sfxGen/modelscope-runtime/run.sh --request /home/hyz/server/sfxGen/modelscope-runtime/pilot5_request_20260930.json --output /home/hyz/server/sfxGen/modelscope-runtime/outputs/sfx_pilot5_20260930_v1
# 服务器音频环境中执行后期准备
/home/hyz/server/sfxGen/modelscope-runtime/.venv/bin/python prepare_review.py pilot5_20260930.json outputs/sfx_pilot5_20260930_v1 reviews/sfx_pilot5_20260930_v1
# 下载后在项目根目录构建试听页和响度报告
uv run --locked python tools/sfx/review.py reports/audio/sfx_pilot5_20260930_v1 --measure
uv run --locked python -m http.server 8768 --bind 127.0.0.1 --directory reports/audio/sfx_pilot5_20260930_v1
```

打开 `http://127.0.0.1:8768/listen.html`，逐条选择偏好并导出意见。浏览器 localStorage 不是长期归档。每条三候选具有独立 seed 和提示词。

运行时固定已核对的 GPU UUID，加载及每条生成前要求至少16GiB空闲；锁定避免本工具重复推理。既有成功文件恢复时核对哈希；失败/中断条目先排查，不改请求盲目重发。原始输出不变，后期和试听产物单独存放。

`pilot5_receipt_20260930.json` 是本次15条小样的生成参数、模型溯源、哈希与测量台账；`pilot5_summary_20260930.md` 是技术摘要。人工听感仍待评审，全量366条未启动。

父目录的 `generate_remote.py` 是此前为原生 `stable_audio_3` 包准备的未实测适配器，**不适用于当前 ComfyUI 打包权重**；不要用它加载当前模型。早期 TangoFlux `app`/`.venv` 同样不属于当前生产入口。历史403记录保留为历史，当前模型已由独立部署流程解决访问。

原始浮点 WAV 和 PCM24 试听版分别保存。自动处理仅作首轮试听准备，不将长音强切成 UI 目标长度，不宣称音乐/语音污染或循环听感已合格。

## 已授权全量生产

当前批次为 `sfx_full_20260930_v3`：121条音效、各三候选，共363条，N04已取消。`batch_20260930.json` 的122/366是历史计划，不能直接再次排产。

```sh
uv run --locked python tools/sfx/build_full_batch.py --integer-durations
```

构建器保留各类不同的音色方向与固定seed；v2的2.1秒中炮出现非有限波形后，同种子3秒探针通过，v3采用整数源时长重新生成。既有批次不允许改写参数。v2失败记录仍在远端，未作为交付。

远端请求为 `modelscope-runtime/full_request_20260930_v3.json`，CLI和后期调用方式同小样，只更换请求、输出目录和catalog。原始/试听文件均在 `reports/audio/sfx_full_20260930_v3/`，长期生成参数和检测台账见 `full_receipt_20260930_v3.json`。已选W03-C/U01-A/W14-r2-A在试听页单列作参考，不计入363个新候选。

本批海面不使用窄带低通，避免上一轮隔离感；仅水下爆炸族沿用已偏好方向的低通。音色适配、鸟声/人声污染、实际循环与游戏混音仍须人工评审。

## 当前人工评审状态

`reviews/current_disposition.json` 是当前有效制作范围、已采用音频和需求映射。2026-09-30为36条采用、58条本轮取消（另N04已取消）、27条返工；详见 `reviews/sfx_full_20260930_v3.summary.md`。后续排产只能从有效返工项建立新批次，不能用旧构建器全量重跑恢复取消项。`build_full_batch.py` 仅复现历史v2/v3，不代表当前排产入口。采用候选有文件路径和SHA256，不需要重新听选；原始候选/反馈不覆盖。

## 2026-09-30 音效27项返工候选已交付

用户授权返工后，批次 `sfx_rework27_20260930_v1` 完成27项各3候选，共81条。具体动作、材质和节奏重新设计，36条已采用与59条已取消不重新生成。81/81文件与哈希检查通过，81个不同试听哈希、试听峰值警告0；47条超目标时长、5条源浮点峰值偏高已标记，人工听审未完成。试听 `http://127.0.0.1:8771/listen.html`；记录见 `tools/sfx/rework27_receipt_20260930_v1.json` 与 `tools/sfx/rework27_summary_20260930_v1.md`。尚未接入游戏，返工问题不因生成成功而关闭。

## 2026-09-30 音效海战主题强化返工

用户指出前轮主题不明确后，27项各3候选重新生成，批次 `sfx_rework27_naval_20260930_v2`，每条明确舰娘海战背景、对应海军器材与动作。81/81下载及哈希核对通过，试听峰值警告0；48条时长、4条源峰值待复查。试听入口 `http://127.0.0.1:8772/listen.html`，记录见 `tools/sfx/rework27_naval_summary_20260930_v2.md`。旧返工保留历史；36条采用与59条取消不变。主题听感、语义辨认及游戏接入仍未验收。

## 2026-10-01 音效设计先行第三轮交付

最新评审7项采用、2项取消，累计43项采用、61项取消（含N04）、18项迭代。参考成熟游戏声音设计原则后，先完成 `tools/sfx/design18_20261001_v3.md` 的体量/声源/音型/时序/对照验收设计，再生成 `sfx_design18_20261001_v3` 的54条候选。54/54文件和哈希验证通过、试听峰值警告0；13条时长和2条源峰值待复查。试听 `http://127.0.0.1:8773/listen.html`；详见 `tools/sfx/design18_summary_20261001_v3.md`。人工语义、体量、音色和混音/接入仍待验收。

## 2026-10-01 第四轮15项候选交付

批次 `sfx_revision15_20261001_v4` 完成15项各3候选：42条GPU新生成，3条从U04a_d3_b制作二连音（60/120/200ms间隔），明确标记编辑来源。提示词改为短声源/动作描述，落实重冲击爆炸、投弹仓/初期破空、锚锁盘三声、提示音乐三连音和3秒海图展开。45/45文件与哈希通过，试听峰值警告0；9条时长、6条源峰值需复查。试听 `http://127.0.0.1:8774/listen.html`，设计与记录见 `tools/sfx/revision15_design_20261001_v4.md` 和 `tools/sfx/revision15_receipt_20261001_v4.json`。累计46项采用、61项取消不变，15项新候选听审待完成，尚未接入游戏。

## 2026-10-01 第五轮7项候选交付

批次 `sfx_revision7_20261001_v5` 已交付7项各3候选共21条，文件及哈希21/21通过，试听峰值警告0；0条时长、0条源峰值待复查。技能改有体量的短起势，任务/辅助尝试钢琴、木琴等具体乐器，布雷完成暂作非人声报告信号，移动重新设计、舰炮选择缩短。设计和回执见 `tools/sfx/revision7_design_20261001_v5.md` 与 `tools/sfx/revision7_receipt_20261001_v5.json`。试听入口 `http://127.0.0.1:8775/listen.html`；累计54项采用、61项取消不变，7项新候选听审待完成。生成不保证具体音程/次数，尚未接入游戏。

## 2026-10-01 第六轮提示词调研与3项候选交付

官方/社区提示词调研后，先完成 `tools/sfx/revision3_design_20261001_v6.md`，再生成K01技能提示、N11a钢琴三音与F09b舰桥报告铃各3候选。批次 `sfx_revision3_20261001_v6` 文件与哈希9/9通过，9个不同试听哈希，试听峰值警告0；0条时长、1条源浮点峰值需复查。A为极简描述，B为声源动作，C同种子增加官方标签，不能据单次结果断言哪种写法普遍更好。试听 `http://127.0.0.1:8776/listen.html`；回执见 `tools/sfx/revision3_receipt_20261001_v6.json`。累计58项采用、61项取消不变，3项听审待完成，正式混音/接入未完成。

## 2026-10-01 第七轮2项音效交付

第六轮评审已核验归档：F09b采用A，K01/N11a返工；累计59项采用、61项取消（含N04）、2项待听审。先设计后生成第七轮 `sfx_revision2_20261001_v7`，技能即时生效确认与钢琴三音任务完成各3候选，6/6文件与哈希验证通过、6个不同试听哈希，试听峰值警告0；0条时长、0条源峰值待复查。试听 `http://127.0.0.1:8777/listen.html`。设计/回执见 `tools/sfx/revision2_design_20261001_v7.md`、`tools/sfx/revision2_receipt_20261001_v7.json`；音数、音程与技能成功感仍需人工听审，正式混音/接入未完成。

## 2026-10-01 第七轮评审完成，无待返工音效

第七轮评审2项及6个试听文件SHA256核验通过。N11a目标完成采用A（`N11a_r7_a`）；K01通用技能成功提示音按用户备注取消，虽choice为空但取消意图明确，退出需求、播放安排与后续跟进。累计60项采用、62项取消（含N04），待返工0项。人工选材完成；循环、混音、正式资产整理与游戏接入尚未完成。本轮未生成新音效。当前映射见 `tools/sfx/reviews/current_disposition.json`。

## 正式采用源包整理

`uv run --locked python tools/sfx/package_selected.py`核验60项采用与105项映射，逐字节整理到`assets/audio/sfx/source/selected_20261001_v1/`。复跑比对已有文件，内容不一致即失败；不得用历史批次恢复取消项。源包manifest不是运行时manifest，`.gdignore`阻止源文件重复导入。历史未采用候选原位保留。


## 运行时派生与验证

`python3 tools/sfx/build_runtime.py`（Python标准库+ffmpeg）从正式采用源包核对哈希后生成60项48kHz PCM16运行时音效及完整逐ID映射。循环采用0.5秒首尾交叉淡化；不修改采用源，不读取历史reports候选。`godot --headless --path . --script scripts/tests/sound_runtime_test.gd` 验证绑定、取消/隐私、去重、场景生命周期与规则不变；`godot --path . --script scripts/tests/sound_device_test.gd` 验证真实设备、32短声部与录音，生成 `reports/audio/runtime_20261001/device.json` 和 `dense_mix.wav`。后者会实际播放声音，不用于替代人工混音/疲劳验收。
