# Character Art Batch Report

Mode: `dry-run`
Required gate: `delivery_ready`; passed: `True`.

Roster source: `docs/41_character_art_design.md`.

| Character | Prototype | Source route | Sources | Four-frame | Source blockers | Configured | Contract | Technical ready | Visual review | Delivery ready | Run status |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| yat_sen | 逸仙号 ROCS Yat Sen | generated_state_sheets | yes | yes | - | yes | complete | yes | polish | yes | dry-run |
| chang_chun | 长春号 PLAN Chang Chun | generated_state_sheets | yes | yes | - | yes | complete | yes | polish | yes | dry-run |
| hai_lung | 海龙号 ROCS Hai Lung SS-793 | generated_state_sheets | yes | yes | - | yes | complete | yes | polish | yes | dry-run |

A character is batch-ready only when either the legacy sheet route or generated source route is complete, no non-production source provenance is present, a valid postprocess route exists, and the processed asset contract passes.
batch_ready is the backward-compatible technical_ready flag, not a visual verdict. delivery_ready additionally requires current, per-output visual review; neither proves in-engine acceptance.
Failures are isolated per character and do not stop later characters in the batch.
