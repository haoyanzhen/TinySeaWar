# Character Art Batch Report

Mode: `process`
Required gate: `technical_ready`; passed: `True`.

Roster source: `docs/41_character_art_design.md`.

| Character | Prototype | Source route | Sources | Four-frame | Source blockers | Configured | Contract | Technical ready | Visual review | Delivery ready | Run status |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| wahoo | 刺尾鱼号 USS Wahoo SS-238 | generated_state_sheets | yes | yes | - | yes | complete | yes | pending | no | complete |
| chapayev | 恰巴耶夫号 Chapayev | generated_state_sheets | yes | yes | - | yes | complete | yes | pending | no | complete |

A character is batch-ready only when either the legacy sheet route or generated source route is complete, no non-production source provenance is present, a valid postprocess route exists, and the processed asset contract passes.
batch_ready is the backward-compatible technical_ready flag, not a visual verdict. delivery_ready additionally requires current, per-output visual review; neither proves in-engine acceptance.
Failures are isolated per character and do not stop later characters in the batch.
