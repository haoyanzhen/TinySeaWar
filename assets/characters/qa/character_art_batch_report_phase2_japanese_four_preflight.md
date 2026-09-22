# Character Art Batch Report

Mode: `dry-run`
Required gate: `delivery_ready`; passed: `False`.

Roster source: `docs/41_character_art_design.md`.

| Character | Prototype | Source route | Sources | Four-frame | Source blockers | Configured | Contract | Technical ready | Visual review | Delivery ready | Run status |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| akizuki | 秋月号 Akizuki | incomplete | no | no | schema-v2 source provenance missing | no | incomplete | no | pending | no | dry-run |
| takao | 高雄号 Takao | incomplete | no | no | schema-v2 source provenance missing | no | incomplete | no | pending | no | dry-run |
| shokaku | 翔鹤号 Shokaku | incomplete | no | no | schema-v2 source provenance missing | no | incomplete | no | pending | no | dry-run |
| i_19 | 伊-19 I-19 | incomplete | no | no | schema-v2 source provenance missing | no | incomplete | no | pending | no | dry-run |

A character is batch-ready only when either the legacy sheet route or generated source route is complete, no non-production source provenance is present, a valid postprocess route exists, and the processed asset contract passes.
batch_ready is the backward-compatible technical_ready flag, not a visual verdict. delivery_ready additionally requires current, per-output visual review; neither proves in-engine acceptance.
Failures are isolated per character and do not stop later characters in the batch.
