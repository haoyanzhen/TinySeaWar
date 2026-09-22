# 逸仙、长春、海龙美术交付与管线验证

日期：2026-09-21。范围为素材生产、静态审查与加载；不代表独立装备组装、跨状态尺寸或实机演出验收。

## 交付

三名角色各有 9 张 Codex 内置 ImageGen 原生 Alpha 源图、52 张角色运行时 PNG，以及动画、绑定点、VFX 和后处理配置。三套契约 complete，逐件视觉 polish，delivery_ready。逸仙另引用既有公共中口径炮口闪光，审查清单共 157 项。

- [角色总览](20260921_chinese_three_overview.png)
- [正式交付报告](character_art_batch_report_phase2_chinese_three_final.md)
- [195 文件重复构建哈希](20260921_chinese_three_rebuild_check.json)

各角色 meta 目录保存 generation_requests.json（实际提示词、原始输出路径及选中源图哈希）、source_provenance_v2.json、source_review.json 和 crop_specs.json；processed/config 保存版本绑定的 delivery_review.json。采用账户内置 ImageGen，未要求 API Key，未伪造底层请求 ID。全身/半身/cut-in 使用计划允许的锚图派生。

## 视觉检查

逐件查看 UI、8 个战斗组件、五组四帧和关键帧、8 个 VFX，并查看静态绑定与白/深蓝/暖灰背景。修正逸仙 UI/移动串格，长春雷达截断及组件提示重叠，海龙火力帧邻格污染；不合格候选没有进入正式源包。柔边与断开的水滴/光效保留。

|角色|逐件图|静态绑定|三背景|
|---|---|---|---|
|逸仙|[查看](yat_sen_processed_contact.png)|[查看](20260921_chinese_yat_sen_bindings.png)|[查看](20260921_chinese_yat_sen_edge_backgrounds.png)|
|长春|[查看](chang_chun_processed_contact.png)|[查看](20260921_chinese_chang_chun_bindings.png)|[查看](20260921_chinese_chang_chun_edge_backgrounds.png)|
|海龙|[查看](hai_lung_processed_contact.png)|[查看](20260921_chinese_hai_lung_bindings.png)|[查看](20260921_chinese_hai_lung_edge_backgrounds.png)|

逸仙主副炮采用中口径炮口效果；长春保持四门单炮、两座三联雷管，无导弹；海龙首六尾四出口逐个标定。计划生成器保留这批静态挂点和发射语义，防止重建覆盖手工标定。

## 最小可靠性改动

1. 逐件裁切规格支持 source_sha256：启用时必须完整覆盖引用源图，哈希不符在写成品前拒绝；兼容既有未带哈希的规格。本批全部启用，避免同尺寸换图继续沿用旧坐标。
2. delivery_review.py 独立检查只要任一角色 pending/stale/blocker/invalid 就返回非零，并检查完整批次；prepare 创建待审清单仍正常返回。未增加自动视觉通过机制。

新增五项有针对性的回归，全部 Python 回归 58/58。统一使用 uv 锁定环境；命令：`uv run --locked python -m unittest discover -s tools/art_pipeline/tests`。

## 验证及边界

- 同配置连续处理后，195 个 processed 文件（156 运行时 PNG、27 source_alpha、12 配置，排除审查清单及 Godot import 元数据）SHA-256 一致。
- `delivery_review.py yat_sen chang_chun hai_lung` 三套 accepted，`batch_character_art.py yat_sen chang_chun hai_lung --require-delivery --report-tag phase2_chinese_three_final` 退出 0。
- Godot `character_batch_asset_load.gd -- yat_sen chang_chun hai_lung`：169 项检查，errors=[]。
- 全局 `phase2_config_test.gd`：301/302；唯一失败仍是之前已记录的第一期 15 个角色缺 processed/vfx 目录，未归入本批已通过结论。编辑器导入完成，但沙箱不允许保存用户级 editor_settings，不能宣称全局编辑器日志无错误。
- 未修改关卡编队或战斗规则。第二期进入正式关卡、独立武器装配、朝向/尺寸、跨状态比例及实机演出仍待单独验收；细节打磨评级为 polish。
