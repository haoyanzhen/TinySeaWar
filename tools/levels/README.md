# 中大型挑战制作与验证

本工具从正式 16:9 海岸母图派生 M-01..05 / L-01..05，保留自定义母图，输出正式编队、目标、环境、导航引用、小地图别名和实验清单。

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

整场性能/航空源点窗口探针（其他实验与渲染停止后单进程执行）：

```sh
godot --headless --path . --script scripts/tests/challenge_ml_battle_probe.gd -- --code=l01 --output=/tmp/l01-probe.json
```

输出每阶段 CPU 分位数、航母实际所在环境区的 Normal/Restricted/Severe 时间、真实开火事件、伤害及潜艇/导航诊断。源点天气许可不等于目标点许可、射程/装填/侦查通过，也不是命中保证。探针不会写进度。

`run_challenge_interactive_qa.gd` 启动仅使用内存进度的新档窗口；用于真实键鼠输入烟测，不污染玩家存档。`render_scene_qa.gd` 支持 `--ui-state=mission|paused|result`，并显式禁止保存挑战进度。渲染和自动键鼠烟测都不能替代真人长期体验验收。

汇总诊断证据：`uv run --locked python tools/levels/summarize_challenge_validation.py`。默认以 gate3 为基础，用 gate4 的四关完整复验替换对应样本，不合并同种子重复运行；输出逐局结果、分类伤害、导航事件 CSV 和明确标记为非正式验收的报告。
