# 技术解决方案

本目录记录跨系统、可实施、可验证的技术解决方案。这里不替代architecture的架构与Domain契约，也不替代gameplay规则或validation实验方法；它用于描述已确认问题的工程治理方案、迁移步骤、性能预算和验收方法。数字是稳定ID，不作为目录分类规则。

## 命名规则

- 文件使用小写英文、下划线和 `tNN` 前缀：`tNN_topic_solution.md`。
- `t00-t09`：性能与基础设施。
- `t10-t19`：运行时架构与数据流。
- `t20-t29`：工具链、构建与自动化。
- 新方案必须说明现状证据、目标与非目标、系统边界、实施阶段、回滚/降级方式和验收标准。
- 方案完成实现前保持“设计方案”口径；只有代码、数据、关卡覆盖及自动/人工验收齐备后才能标记为已完成。

## 当前方案

- [t00_coastal_ai_performance_solution.md](t00_coastal_ai_performance_solution.md)：有岸与大编队战斗的 AI 调度、导航、空间查询、Tick 阶段及单位侦查性能治理方案。
- [t01_inertial_navigation_and_emergency_avoidance.md](t01_inertial_navigation_and_emergency_avoidance.md)：`3-5s` 战略走廊、`1.0s` 常规动力学航迹与 `0.1s` 高威胁紧急避险状态机。
- [t02_level_objective_reinforcement_progress_solution.md](t02_level_objective_reinforcement_progress_solution.md)：声明式目标适配、接替增援原子提交与幂等进度事务；逐关玩法与正式字段分别见15/23。
- [t10_carrier_combat_presentation_solution.md](t10_carrier_combat_presentation_solution.md)：航空过程投影、新旧事件唯一消费、防空/投雷适配与分阶段验收。

全部方案的当前完成度与用户验收只见[00](../00_project_status.md)。技术方案拥有工程职责、迁移和验收设计，历史实现成绩不在此维护；t00测量与t10接入记录分别见[性能历史](../history/t00_coastal_ai_performance_iterations.md)、[航空历史](../history/t10_carrier_presentation_iterations.md)。
