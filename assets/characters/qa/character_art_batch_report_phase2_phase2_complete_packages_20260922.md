# Character Art Batch Report

Mode: `dry-run`
Required gate: `delivery_ready`; passed: `True`.

Roster source: `docs/41_character_art_design.md`.

| Character | Prototype | Source route | Sources | Four-frame | Source blockers | Configured | Contract | Technical ready | Visual review | Delivery ready | Run status |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| fletcher | 弗莱彻号 USS Fletcher DD-445 | generated_state_sheets | yes | yes | - | yes | complete | yes | polish | yes | dry-run |
| cleveland | 克利夫兰号 USS Cleveland CL-55 | generated_state_sheets | yes | yes | - | yes | complete | yes | polish | yes | dry-run |
| baltimore | 巴尔的摩号 USS Baltimore CA-68 | generated_state_sheets | yes | yes | - | yes | complete | yes | polish | yes | dry-run |
| wahoo | 刺尾鱼号 USS Wahoo SS-238 | generated_state_sheets | yes | yes | - | yes | complete | yes | polish | yes | dry-run |
| jervis | 杰维斯号 HMS Jervis | generated_state_sheets | yes | yes | - | yes | complete | yes | polish | yes | dry-run |
| belfast | 贝尔法斯特号 HMS Belfast | generated_state_sheets | yes | yes | - | yes | complete | yes | polish | yes | dry-run |
| illustrious | 光辉号 HMS Illustrious | generated_state_sheets | yes | yes | - | yes | complete | yes | polish | yes | dry-run |
| upholder | 拥护者号 HMS Upholder P37 | generated_state_sheets | yes | yes | - | yes | complete | yes | polish | yes | dry-run |
| tashkent | 塔什干号 Tashkent | generated_state_sheets | yes | yes | - | yes | complete | yes | polish | yes | dry-run |
| chapayev | 恰巴耶夫号 Chapayev | generated_state_sheets | yes | yes | - | yes | complete | yes | polish | yes | dry-run |
| gangut | 甘古特号 Gangut | generated_state_sheets | yes | yes | - | yes | complete | yes | polish | yes | dry-run |
| k_21 | K-21 | generated_state_sheets | yes | yes | - | yes | complete | yes | polish | yes | dry-run |
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
