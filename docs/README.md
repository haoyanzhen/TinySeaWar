# Tiny Sea War Design Docs

This folder uses numeric prefixes so design files stay grouped in a useful reading order.

## Naming Rules

- `00-09`: project status, roadmap, and repository-wide guides.
- `10-19`: gameplay, operations, formulas, and balance.
- `20-29`: data contracts and schema.
- `30-39`: technical architecture and implementation notes.
- `40-49`: art direction, asset contracts, and art pipeline notes.
- `90-99`: audits, reviews, and historical reports.

Use lowercase English file names with underscores:

`NN_domain_topic_kind.md`

## Reading Order

### Project Status

- [00_project_status.md](00_project_status.md)

### Gameplay And Balance

- [10_game_core_mechanics.md](10_game_core_mechanics.md)
- [11_game_operation_design.md](11_game_operation_design.md)
- [12_combat_formula_design.md](12_combat_formula_design.md)
- [13_balance_baseline.md](13_balance_baseline.md)
- [14_character_balance_design.md](14_character_balance_design.md)
- [15_battle_level_design.md](15_battle_level_design.md)
- [16_enemy_ai_behavior_design.md](16_enemy_ai_behavior_design.md)
- [17_play_design.md](17_play_design.md)
- [18_facility_weather_effect_design.md](18_facility_weather_effect_design.md)
- [19_battle_simulator_design.md](19_battle_simulator_design.md)

### Data

- [20_data_schema_design.md](20_data_schema_design.md)：数据契约索引与公共约定。
- [21_combat_data_schema.md](21_combat_data_schema.md)：战斗单位与结算输入。
- [22_scene_environment_data_schema.md](22_scene_environment_data_schema.md)：场景、环境与设施。
- [23_level_progress_data_schema.md](23_level_progress_data_schema.md)：关卡、目标与进度。
- [24_ai_data_schema.md](24_ai_data_schema.md)：AI 配置。
- [25_presentation_data_schema.md](25_presentation_data_schema.md)：纯表现配置。
- [26_simulation_data_schema.md](26_simulation_data_schema.md)：模拟实验清单。

### Technology

- [30_technical_architecture.md](30_technical_architecture.md)
- [32_domain_design_phase1.md](32_domain_design_phase1.md)
- [33_domain_design_phase2.md](33_domain_design_phase2.md)
- [34_implementation_map.md](34_implementation_map.md)
- [35_scene_combat_domain_design.md](35_scene_combat_domain_design.md)
- [36_balance_testing_design.md](36_balance_testing_design.md)
- [37_environment_runtime_domain_design.md](37_environment_runtime_domain_design.md)
- [38_facility_combat_domain_design.md](38_facility_combat_domain_design.md)

### Technical Solutions

- [technical/README.md](technical/README.md)
- [technical/t00_coastal_ai_performance_solution.md](technical/t00_coastal_ai_performance_solution.md)
- [technical/t01_inertial_navigation_and_emergency_avoidance.md](technical/t01_inertial_navigation_and_emergency_avoidance.md)
- [technical/t02_level_objective_reinforcement_progress_solution.md](technical/t02_level_objective_reinforcement_progress_solution.md)

### Art

- [40_art_direction_design.md](40_art_direction_design.md)
- [41_character_art_design.md](41_character_art_design.md)
- [42_combat_art_design.md](42_combat_art_design.md)
- [43_scene_art_design.md](43_scene_art_design.md)
- [44_ui_art_design.md](44_ui_art_design.md)
- [45_art_asset_interface_design.md](45_art_asset_interface_design.md)
- [46_character_art_asset_pipeline.md](46_character_art_asset_pipeline.md)
- [47_scene_art_asset_pipeline.md](47_scene_art_asset_pipeline.md)

### Audit

- [91_character_phase2_historical_validation.md](91_character_phase2_historical_validation.md)
- [92_character_phase2_static_balance_review.md](92_character_phase2_static_balance_review.md)

### History

- [history/31_program_design_phase1.md](history/31_program_design_phase1.md)：第一阶段 3v3 原型实施范围的历史存档，不再作为当前真源。
- [history/90_design_audit_round4.md](history/90_design_audit_round4.md)：2026-06-14 第四轮设计复核的历史存档；当前未闭环项见 `../workorder/20260717-design-audit-round4-unclosed-items.md`。
