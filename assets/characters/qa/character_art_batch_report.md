# Character Art Batch Report

Mode: `dry-run`

Roster source: `docs/41_character_art_design.md`.

| Character | Prototype | Source route | Sources | Four-frame | Source blockers | Configured | Contract | Batch ready | Run status |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| tashkent | 塔什干号 Tashkent | generated_state_sheets | yes | yes | - | yes | complete | yes | dry-run |
| chapayev | 恰巴耶夫号 Chapayev | generated_state_sheets | yes | yes | - | yes | complete | yes | dry-run |
| gangut | 甘古特号 Gangut | generated_state_sheets | yes | yes | - | yes | complete | yes | dry-run |
| k_21 | K-21 | generated_state_sheets | yes | yes | - | yes | complete | yes | dry-run |

A character is batch-ready only when either the legacy sheet route or generated source route is complete, no non-production source provenance is present, a valid postprocess route exists, and the processed asset contract passes.
Failures are isolated per character and do not stop later characters in the batch.
