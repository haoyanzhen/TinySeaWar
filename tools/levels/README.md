# 中大型挑战制作与验证

本工具从正式 16:9 海岸母图派生 M-01..05 / L-01..05，保留自定义母图，输出正式编队、目标、环境、导航引用、小地图别名和实验清单。

作者选择由 `challenge_balance_selection.json` 的十关 `selected_stages` 决定：0为原配置，1为部署/增援候选，2/3逐级叠加获授权的敌方替换。它不是运行时数据或玩家设置；只有生成出的关卡Definition进入游戏。替换舰继承原槽候选点，可选精通随实体引用更新。公共属性、AI档位、玩家舰队、任务门槛和奖励保持原契约。

现有目标 `description` 追加菜单编成 Cost（初始、预备、全部），仅用于展示。最终配置与冻结候选比较时，战斗 Definition 和目标判定字段必须完全一致；这一说明追加及正式清单版本/输出目录是显式记录的非战斗差异。

该作者清单可指定 `experiment_revision`（例如 `20261001_tuned/v1`），为后续正式清单生成独立实验ID和输出目录，避免覆盖旧验收产物。省略时保留旧 `20260930/v4`；候选实验使用自己的清单和目录。

```sh
uv sync --locked
uv run --locked python tools/levels/build_challenge_levels.py --bake-fields
uv run --locked python tools/levels/build_challenge_levels.py --check
godot --headless --path . --script scripts/tests/challenge_ml_runtime_test.gd
godot --headless --path . --script scripts/tests/challenge_ml_progress_test.gd
```

`--check` 比较所有生成 JSON；几何变化时必须重新 `--bake-fields`，不能只改地图 JSON。出生使用半径 46 深吃水连通分量的保守投影，至少 180 间距；实际单位的合法性和每关接敌路线由 Godot 专项补验。生成证据在 `data/terrain/authoring/challenge_deployment_evidence.json`；最终坐标/航向在正式关卡与地图数据。RN/RS 为作者标识，玩家提示使用 `spawn_display_name`。

正式实验（须先通过行为门禁）：

```sh
godot --headless --path . --script tools/simulation/run_experiment.gd -- data/simulations/experiments/level_m01_win_rate_20.json
```

其他九关替换 ID。20 种子集合和目标带固定，不修改样本以迎合结果。每次调参修改作者生成器、重新生成，实验输出目录使用新的版本，不覆盖历史。单局和三种子诊断复制正式 manifest 后改为 `FullBattleSimulation`、删除 `win_rate_evaluation`、count 为 1 或 3 并更换输出目录；不得将诊断胜率称为正式验收。

2026-10-01获用户明确授权的关卡难度调参（保留旧产物，新的重复实验必须传入新的输出目录）：

```sh
uv run --locked python -m unittest discover -s tools/levels -p 'test_challenge_tuning.py' -v
uv run --locked python tools/levels/tune_challenge_difficulty.py --output artifacts/simulations/challenge_ml_tuning_20261001
uv run --locked python tools/levels/summarize_challenge_tuning.py
```

此工具使用10月1日难度测量的冻结运行时；启动前核对公共战斗代码和全部数据没有漂移。四份隔离工程先通过实际舰体与双向接敌路径预检，再并行最多四场会话。每关最多三组、每组原20种子；点估计进入目标带且无新增技术无效种子后停止。按有效分母计算胜率，但增加任何技术无效种子即拒绝；M-03原91214必须保留。最接近目标且优于原配置的候选进入独立20种子配对复验，复验后不重新挑组。训练须严格改善、复验不能变差且无新增技术无效，才保留；否则选回0组。L-02只复验原配置。上限920场新战斗，不自动扩大、补种子或覆盖结果。

工具只写隔离产物，不自动应用。确认 `selection_final.json` 与报告一致后，把十关 `selected_stages` 写入作者选择清单、重新生成并跑关卡/进度回归。候选和正式验收严格分开：本实验使用 `FullBattleSimulation`，公共行为、性能和人工缺口仍独立。`pipeline_status.json` 是运行进度；每个完成种子的 `progress.jsonl` 与最终原生结果必须一致；配置SHA与失败启动日志都保留。

隔离生成可用 `--output-root <project> --candidate-stage 0|1|2|3` 或 `--selection <json>`；不要向正式工作区生成尚未验证的候选。几何不变时不重烘焙碰撞场。

整场性能/航空源点窗口探针（其他实验与渲染停止后单进程执行）：

```sh
godot --headless --path . --script scripts/tests/challenge_ml_battle_probe.gd -- --code=l01 --output=/tmp/l01-probe.json
```

输出每阶段 CPU 分位数、航母实际所在环境区的 Normal/Restricted/Severe 时间、真实开火事件、伤害及潜艇/导航诊断。源点天气许可不等于目标点许可、射程/装填/侦查通过，也不是命中保证。探针不会写进度。

`run_challenge_interactive_qa.gd` 启动仅使用内存进度的新档窗口；用于真实键鼠输入烟测，不污染玩家存档。`render_scene_qa.gd` 支持 `--ui-state=mission|paused|result`，并显式禁止保存挑战进度。渲染和自动键鼠烟测都不能替代真人长期体验验收。

汇总诊断证据：`uv run --locked python tools/levels/summarize_challenge_validation.py`。默认以 gate3 为基础，用 gate4 的四关完整复验替换对应样本，不合并同种子重复运行；输出逐局结果、分类伤害、导航事件 CSV 和明确标记为非正式验收的报告。
