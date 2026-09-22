# belfast production trial — 2026-09-20

Codex built-in ImageGen native Alpha; nine accepted source PNGs preserved byte-for-byte. No API key or chroma fallback used.

Full package: 11 UI, 8 battle parts, 20 pose frames + 5 keyframes, 8 VFX, 9 Alpha source copies, runtime JSON configs and schema-v2 provenance.

Source-space crop hints were reviewed per semantic object; no grid cuts. Current source decisions are in `belfast_source_review.json`, and processed decisions are hash-bound in `../processed/config/belfast_delivery_review.json`.

Technical contract complete; per-output visual review polish. Runtime weapon assembly and animation scale/timing are not accepted by this production trial. See [batch validation](../../qa/20260920_four_character_pipeline_validation.md) and [contact](../../qa/belfast_processed_contact.png).
