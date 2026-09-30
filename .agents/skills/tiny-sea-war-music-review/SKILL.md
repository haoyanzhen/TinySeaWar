---
name: tiny-sea-war-music-review
description: Generate TinySeaWar music on the configured ACE-Step GPU server, resume batches, download and validate audio, and build a human listening-review page. Use for title, battle, victory or defeat music production and review; not for game runtime audio integration.
---

# TinySeaWar Music Generation and Review

Use the repository's deterministic tools in `tools/music`; keep prompt design and artistic decisions in the agent workflow. Read `docs/50_music_playback_and_asset_design.md` for playback/asset requirements and `tools/music/README.md` for commands, manifest format, recovery and capacity policy. Run from the repository root with `uv run --locked python`; use `uv sync --locked` if the environment is missing or lock changed. Do not create per-task copies of generation or review scripts.

## Prepare and check capacity

1. Confirm category, number, duration, style and previously accepted feedback from the request. Write a new version-1 manifest under ignored `reports/audio/<batch_id>/` using `tools/music/example_batch.json` as the structure. Use unique safe IDs, explicit prompts and fixed seeds; never overwrite a used batch with revised parameters. Choose duration from the user request or category targets in design 50; a candidate is not automatically a 90-second sample. Support any positive finite duration accepted by the generation service; do not shorten it to fit an example or historical capacity measurement. No separate menu category: non-battle pages share title music.
2. Before **every new generation**, run `music.py check --manifest …` against `tools/music/server.json` (or user-specified config). Report target GPU, free VRAM and the decision. The generation tool repeats the check immediately before each new song; a prior successful check does not waive it. It checks the running service's GPU mapping and loaded models, not just device total capacity.
3. **If VRAM is insufficient, do not generate until the user decides.** Show free/total VRAM, required reserve, task duration/count/configuration and options to wait, change the task, or explicitly try under current conditions. State that this pause is required by the user's GPU condition and this SKILL.md. Unknown/failed GPU verification cannot be overridden.
4. Never lower thresholds, switch GPUs, stop other processes, restart/load models, reduce model quality or fabricate approval merely to proceed. Permission to generate generally does not waive the insufficient-VRAM decision. With an explicit decision for this batch, record the actual user statement in a temporary approval JSON following the README, bound to the batch hash, GPU UUID, reported free-capacity floor and at most one-hour expiry; pass `--approval`. Do not request the same approval again while it remains applicable, but recheck capacity for every song. If capacity falls below that floor, pause again for the user.

Duration alone never requires trial approval. After verifying the service GPU and loaded models, use the tool’s 16384 MiB free-VRAM reserve check for every duration. This is an operational minimum, not a guarantee that every duration fits; do not invent a duration-to-memory formula. If the service rejects a duration or generation fails, preserve evidence and report the actual limit or failure without silently shortening or resubmitting. Existing check/run authorization allows read-only probes; it does not authorize GPU workloads absent a production/test request.

## Generate and hand off

- Use `music.py e2e --manifest … --output reports/audio/<batch_id>` or generate/fetch/review separately. It serializes this workflow, journals task IDs, downloads WAVs, checks hashes, analyzes per-second levels and builds `listen.html`. Poll existing tasks after interruption; do not submit replacements blindly.
- For `submitting` or `failed` states, inspect saved evidence and follow README recovery. Stop after a failure rather than silently retrying GPU work. Do not delete journals to bypass an ambiguous submission.
- Inspect `validation_summary.json`. Long quiet tails, internal quiet regions, duration mismatch or clipping require review; a nonzero whole-file RMS does not prove complete music. Do not automatically trim, normalize or fill missing audio to make checks pass.
- Use `music.py serve --output … --port <available-port>` and open the printed local review page. Keep the preview loopback-only. Provide the local `listen.html` link as a durable alternative. If the user requests audible media directly, render WAVs using absolute-path Markdown audio embeds.
- The page supports exclusive playback, timestamped issues, preference/revision decisions and JSON export/import tied to batch/audio hashes. Ask the user to export feedback or provide comments; preserve returned JSON beside the batch and apply it only to the matching audio versions. Do not send it to anyone else or label pending tracks human-approved.
- Record model/parameters, output location, technical flags and actual human feedback. Report what ran, what is still awaiting listening, and any blocked songs. Do not claim absence of audible jitter, good composition, seamless looping or completed runtime integration from signal tests alone.

## Track reviews and improvements

- Read `tools/music/reviews/registry.md` before planning another batch. Its JSON registry is the durable history; ignored reports and browser storage are not the sole review record.
- After local validation, use `tools/music/tracker.py register --batch-dir … --remote-dir …` to register immutable versions with hashes and actual recovery locations. Import user-exported review JSON using `tracker.py import --feedback … --source …`; do not import automated browser-test feedback as human approval.
- For feedback received in chat, preserve the user's actual wording in the same review format with a clear source/date and reviewer attribution. Never invent issue timestamps or approval. Keep inferred action plans and priorities in `tracker.py plan`, separate from user quotations.
- Register a single-track improvement batch with `--parent <old_batch>/<old_track>`. The new audio starts awaiting review, and generating it does not resolve the old issues. Ask for focused comparison against the parent; retain every review round. The tracker rejects mismatched hashes and deduplicates identical imports.
- The generated Markdown table is a view, not an independent source to edit. Registration/import/render are local operations and do not need a GPU capacity decision. See the tool README for commands and scope.

## Reuse and project boundaries

`review` and `serve` do not need GPU authorization and can reuse existing WAVs with a manifest. Existing legacy sample folders can be adapted with a new manifest without copying or rerunning inference; preserve original requests and audio files. Do not overwrite their existing historical manifests.

Production candidates stay under ignored reports until separately accepted for runtime integration. Formal progress belongs in `docs/00_project_status.md`; music design in `50`; schemas and game playback implementation remain outside this skill's default scope. Fixed seeds support reproducibility but do not promise bit-identical inference across environments.

## TinySeaWar title-pool review preference

For each title-music revision round, deliver one listening overview containing all five styles (fleet preparation, everyday companionship, tender moments, lyrical storytelling, bright adventure). Reuse retained candidates for unchanged styles; do not generate five new tracks unless requested. Each card must identify its source version and whether it is retained, revised, rolled back or still awaiting repair. Keep failed revisions and feedback in history without presenting them as successful fixes. Aggregate manifests and review exports remain bound to exact audio hashes.
