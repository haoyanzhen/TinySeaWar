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
