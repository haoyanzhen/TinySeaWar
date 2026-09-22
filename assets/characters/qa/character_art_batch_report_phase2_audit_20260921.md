# Character Art Batch Report

Mode: `dry-run`
Required gate: `delivery_ready`; passed: `False`.

Roster source: `docs/41_character_art_design.md`.

| Character | Prototype | Source route | Sources | Four-frame | Source blockers | Configured | Contract | Technical ready | Visual review | Delivery ready | Run status |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| fletcher | 弗莱彻号 USS Fletcher DD-445 | generated_state_sheets | yes | yes | - | no | complete | no | pending | no | dry-run |
| cleveland | 克利夫兰号 USS Cleveland CL-55 | generated_state_sheets | yes | yes | - | no | complete | no | pending | no | dry-run |
| baltimore | 巴尔的摩号 USS Baltimore CA-68 | generated_state_sheets | yes | yes | - | no | complete | no | pending | no | dry-run |
| wahoo | 刺尾鱼号 USS Wahoo SS-238 | generated_state_sheets | yes | yes | - | no | complete | no | pending | no | dry-run |
| jervis | 杰维斯号 HMS Jervis | generated_state_sheets | yes | yes | - | no | complete | no | pending | no | dry-run |
| belfast | 贝尔法斯特号 HMS Belfast | generated_state_sheets | yes | yes | - | yes | complete | yes | polish | yes | dry-run |
| illustrious | 光辉号 HMS Illustrious | generated_state_sheets | yes | yes | - | yes | complete | yes | polish | yes | dry-run |
| upholder | 拥护者号 HMS Upholder P37 | generated_state_sheets | yes | yes | - | yes | complete | yes | polish | yes | dry-run |
| tashkent | 塔什干号 Tashkent | generated_state_sheets | yes | yes | - | no | complete | no | pending | no | dry-run |
| chapayev | 恰巴耶夫号 Chapayev | generated_state_sheets | yes | yes | - | no | complete | no | pending | no | dry-run |
| gangut | 甘古特号 Gangut | generated_state_sheets | yes | yes | - | no | complete | no | pending | no | dry-run |
| k_21 | K-21 | generated_state_sheets | yes | yes | - | no | complete | no | pending | no | dry-run |
| z23 | Z23 | generated_state_sheets | yes | yes | - | yes | complete | yes | polish | yes | dry-run |
| nurnberg | 纽伦堡号 Nürnberg | generated_state_sheets | yes | yes | - | yes | complete | yes | polish | yes | dry-run |
| scharnhorst | 沙恩霍斯特号 Scharnhorst | generated_state_sheets | yes | yes | - | yes | complete | yes | polish | yes | dry-run |
| graf_zeppelin | 齐柏林伯爵号 Graf Zeppelin | generated_state_sheets | yes | yes | - | yes | complete | yes | polish | yes | dry-run |
| akizuki | 秋月号 Akizuki | generated_state_sheets | yes | yes | - | yes | complete | yes | polish | yes | dry-run |
| takao | 高雄号 Takao | generated_state_sheets | yes | yes | - | yes | complete | yes | polish | yes | dry-run |
| shokaku | 翔鹤号 Shokaku | generated_state_sheets | yes | yes | - | yes | complete | yes | polish | yes | dry-run |
| i_19 | 伊-19 I-19 | generated_state_sheets | yes | yes | - | yes | complete | yes | polish | yes | dry-run |
| yat_sen | 逸仙号 ROCS Yat Sen | generated_state_sheets | yes | yes | - | yes | complete | yes | polish | yes | dry-run |
| chang_chun | 长春号 PLAN Chang Chun | generated_state_sheets | yes | yes | - | yes | complete | yes | polish | yes | dry-run |
| dingyuan | 定远号 Dingyuan | generated_state_sheets | yes | yes | - | yes | complete | yes | polish | yes | dry-run |
| hai_lung | 海龙号 ROCS Hai Lung SS-793 | generated_state_sheets | yes | yes | - | yes | complete | yes | polish | yes | dry-run |

A character is batch-ready only when either the legacy sheet route or generated source route is complete, no non-production source provenance is present, a valid postprocess route exists, and the processed asset contract passes.
batch_ready is the backward-compatible technical_ready flag, not a visual verdict. delivery_ready additionally requires current, per-output visual review; neither proves in-engine acceptance.
Failures are isolated per character and do not stop later characters in the batch.

## 2026-09-21 完成度核验结论

本轮为当前文件的静态契约、来源、裁切配置、审查记录哈希及 Godot 加载复核；未重新逐张目检或进行带画面实机验收。没有修改源图、成品或既有审查结论。

- 24/24 成品契约 complete；全体第二期 Godot 加载专项 1349 项，errors=[]。
- 15/24（62.5%）通过当前 technical_ready 与 delivery_ready；现有逐件审查记录均为 polish，哈希仍匹配，可进入绑定测试，最终导入前仍需精修。
- 5 名旧基线：弗莱彻、克利夫兰、巴尔的摩、刺尾鱼、杰维斯。成品契约通过，但当前批处理无有效裁切配置，且缺少 delivery_review；不能计入新版交付通过，也不代表已有图片丢失。
- 4 名待返修：塔什干、恰巴耶夫、甘古特、K-21。源包及成品存在、静态契约通过，但缺少逐件裁切规格，交付清单每人 52 项仍 pending。沿用状态真源中的截断、串格及语义问题判断，须标定、重切、逐件视觉和绑定复验。
- 15 名通过者：贝尔法斯特、光辉、拥护者、定远、Z23、纽伦堡、沙恩霍斯特、齐柏林伯爵、秋月、高雄、翔鹤、伊-19、逸仙、长春、海龙。
- 独立武器组装、朝向/尺寸、跨状态比例与实机演出仍未完成全期验收；第二期仍未进入既有正式关卡。
- Godot 专项退出 0，但 Autoload 仍报告第一期 15 名角色缺少 processed/vfx 目录；这是既有全局资产目录校验问题，不能把专项通过写成全局启动无错误。
- docs/00_project_status.md 中“当前 3 名第二期缺少 processed UI”的条目与本次全体加载结果不符，属于待清理的旧状态描述。

复验命令：`UV_CACHE_DIR=/private/tmp/tinyseawar-uv-cache uv run --locked python tools/art_pipeline/batch_character_art.py --phase phase2 --require-delivery --report-tag audit_20260921`。退出码 1 表示整期交付门禁未通过，不是脚本崩溃。dry-run 报告 summary.complete=0 为处理运行计数，不表示成品契约为零。
