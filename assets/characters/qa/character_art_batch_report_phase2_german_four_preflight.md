# Character Art Batch Report

Mode: `dry-run`
Required gate: `delivery_ready`; passed: `False`.

Roster source: `docs/41_character_art_design.md`.

| Character | Prototype | Source route | Sources | Four-frame | Source blockers | Configured | Contract | Technical ready | Visual review | Delivery ready | Run status |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| z23 | Z23 | generated_state_sheets | yes | yes | schema-v2 source provenance missing | no | incomplete | no | pending | no | dry-run |
| nurnberg | 纽伦堡号 Nürnberg | incomplete | no | yes | schema-v2 source provenance missing | no | incomplete | no | pending | no | dry-run |
| scharnhorst | 沙恩霍斯特号 Scharnhorst | incomplete | no | no | schema-v2 source provenance missing | no | incomplete | no | pending | no | dry-run |
| graf_zeppelin | 齐柏林伯爵号 Graf Zeppelin | incomplete | no | no | schema-v2 source provenance missing | no | incomplete | no | pending | no | dry-run |

A character is batch-ready only when either the legacy sheet route or generated source route is complete, no non-production source provenance is present, a valid postprocess route exists, and the processed asset contract passes.
batch_ready is the backward-compatible technical_ready flag, not a visual verdict. delivery_ready additionally requires current, per-output visual review; neither proves in-engine acceptance.
Failures are isolated per character and do not stop later characters in the batch.
