---
name: tiny-sea-war-audit-design-docs
description: Audit, restructure, archive, and maintain Tiny Sea War numbered Markdown design documents and their navigation. Use when reviewing one document or a numbered series for completeness, overlapping ownership, unclear boundaries, contradictions, stale implementation claims, duplicated rules or values, excessive prose, split/merge candidates, or whether files should be kept, archived, or deleted; also use when implementing accepted audit recommendations and synchronizing docs/00_project_status.md, AGENTS.md, docs/README.md, implementation routes, cross-references, and proportional validation.
---

# Audit Tiny Sea War Design Documents

Produce one coherent source-of-truth system, not merely shorter prose. Read every selected document completely, identify which file owns each concept, implement authorized changes, and leave active routes and status claims consistent with the repository.

## Respect the Requested Action Level

Classify the request before editing:

- **Review/report**: inspect and report findings; do not move, delete, rewrite, or fix runtime code.
- **Review and fix**: implement safe in-scope text, split, archive, route, and directly related consistency changes.
- **Apply accepted recommendations**: execute the previously accepted action list without reopening settled choices unless repository evidence has changed.

Never treat a review-only request as authorization to mutate files. Never delete a file without explicit deletion approval naming the file or clearly accepting a recommendation that names it for deletion. Archiving is not deletion.

## Establish the Baseline

1. Run `git status --short`. Preserve all unrelated and pre-existing work.
2. Read:
   - `AGENTS.md`
   - `docs/00_project_status.md`
   - `docs/README.md`
   - `docs/34_implementation_map.md` when code or path claims are involved
   - every document in the requested range, in full
3. Use `rg` to find all references to selected filenames, headings, IDs, rules, values, status phrases, and proposed replacement names.
4. Inspect the actual data, code, tests, and generated reports whenever a document makes a current implementation or numerical claim.
5. Run the inventory helper before forming conclusions:

```bash
.agents/skills/tiny-sea-war-audit-design-docs/scripts/audit_design_docs.sh \
  docs/<first>.md docs/<second>.md
```

With no file arguments, the helper inventories all active top-level numbered design documents. Treat its output as leads, not automatic verdicts.

## Apply the Authority Order

Resolve conflicts by the kind of claim:

1. **Current completion and latest verification**: `docs/00_project_status.md`, supported by repository evidence.
2. **Intended gameplay and numerical rules**: the designated `10–19` source document.
3. **Current exact runtime configuration**: `data/`, with its owning `21–26` schema contract.
4. **Domain and architecture contracts**: `30–38`.
5. **Current code and asset location**: `34_implementation_map.md`, verified against the filesystem.
6. **Technical solution detail**: `docs/technical/`, subordinate to active architecture and Domain documents.
7. **Historical audit or validation reports**: `90–99` and `docs/history/`; evidence only, never the newest runtime truth.

Do not silently choose between a desired design rule and contradictory runtime behavior. Report the mismatch. If the user authorized correction, update the appropriate source plus code/data/tests in the same change.

## Audit in This Order

For each document, record evidence before deciding its disposition. Use the complete checklist and decision matrix in [references/audit-criteria.md](references/audit-criteria.md).

### 1. Function and boundary

- State in the opening paragraph what the document owns.
- State what it explicitly does not own and link to those sources.
- Ensure the title and filename still describe the current role.
- Check that one concept has one authoritative home.

### 2. Content completeness

- Verify the document covers the full contract implied by its stated role.
- Check inputs, outputs, ownership, lifecycle, error/rejection behavior, determinism, validation, and integration boundaries where applicable.
- Distinguish intended design, current implementation, historical evidence, and future work.

### 3. Cross-document overlap

- Identify copied formulas, tables, enums, status summaries, code paths, tests, examples, and prose.
- Keep the full definition only in the owner; replace copies with a concise semantic reference.
- Preserve small context sentences only when required to understand the local contract.

### 4. Contradictions and stale claims

- Search the full repository, not only the selected range.
- Verify exact names, IDs, percentages, enums, paths, current level coverage, test counts, and implementation statements.
- Distinguish a historical statement dated in context from an incorrect current statement.
- Correct every authorized stale or contradictory active claim and every route that repeats it.

### 5. Excess and implementation leakage

- Remove repeated motivation, tutorial prose, speculative futures, obsolete phase plans, path inventories outside `34`, completion tables outside `00`, schema tables outside `20–26`, and test history outside status/audit evidence.
- Keep actionable rationale, invariants, rejection semantics, edge cases, and acceptance criteria.
- Prefer references over abridged duplicate truth.

### 6. File disposition

Classify each file as `Keep`, `Tighten`, `Split`, `Merge`, `Archive`, or `Delete`. Do not use line count alone as the decision.

### 7. Cross-series second pass

After individual review, re-read the edited set in dependency order:

1. `00` current state
2. `10–19` gameplay and numerical intent
3. `20–26` data shape
4. `30–38` architecture, Domain, implementation map, and test method
5. `technical/` solutions
6. `40–49` presentation and assets
7. `90–99` and `history/`

Confirm that upstream rules flow downward without being redefined.

## Choose and Apply the File Disposition

### Keep

Keep when the file has one current responsibility, active consumers, and no material duplication. Still repair incorrect boundary text or references.

### Tighten

Tighten in place when the responsibility is correct but the document contains copied truth, stale status, obsolete examples, excessive rationale, or implementation paths owned elsewhere.

### Split

Split when two or more stable domains have different owners, readers, change cadence, schemas, or validation needs. Before splitting:

1. Define the responsibility and non-responsibility of every destination.
2. Assign each section to exactly one destination.
3. Keep the existing filename for the dominant current responsibility when that minimizes broken routes.
4. Add new numbered files only in available slots consistent with `docs/README.md`.
5. Replace cross-domain copies with links.
6. Update every inbound route and reference.

Do not split merely because a file is long. Do not create fragments that cannot stand as independent contracts.

### Merge

Merge when multiple active files claim the same responsibility and one can absorb all unique current content without becoming multi-domain. Migrate unique content first, then archive the superseded source unless explicit deletion is approved.

### Archive

Archive when a file has historical value but is no longer an active source: completed phase plan, superseded implementation guide, obsolete audit, or replaced contract.

1. Move it to `docs/history/` using `apply_patch`.
2. Add an opening archive notice naming the current sources.
3. Remove it from active reading order.
4. Add it to the history route in `AGENTS.md` and `docs/README.md` only when it remains useful.
5. Rewrite active inbound references; historical references may point to the archived path.
6. Never create `*_old`, `*_backup`, or duplicate active copies.

### Delete

Delete only when all are true:

- no unique current contract or useful historical explanation remains;
- content is generated, empty, exact duplication, or a disposable obsolete stub;
- all inbound references and tooling expectations are known;
- Git history is sufficient for recovery;
- the user explicitly approved deletion.

Before deleting, migrate any unique content, update references, and state why archive is unnecessary. If authorization is absent, report `Delete candidate` and leave the file untouched.

## Implement Document Changes

Use `apply_patch` for edits, moves, and new files. Preserve unrelated dirty work.

For every active document materially rewritten:

- put a concise **功能与边界** statement at the beginning;
- name its owning decisions and explicit exclusions;
- use current terminology and exact IDs;
- remove copied truth and link to the owner;
- keep current status only where the document is authorized to own it;
- avoid speculative “future implementation” language unless the file owns a planned contract;
- retain enough rationale and edge cases to make the contract executable.

When an audit exposes a runtime contradiction, change code/data only if the request authorizes correction. Add or update the smallest relevant test. Do not expand into unrelated refactors.

## Synchronize Routes and Status

Always inspect these after a rename, split, merge, archive, deletion, ownership change, or corrected current claim:

### `docs/00_project_status.md`

- Keep it the only current completion source.
- Update the current summary only when evidence changes.
- Add one dated validation entry for a material audit implementation.
- Record exact scope, dispositions, rule corrections, tests, failures, and remaining risks.
- Separate data loading, runtime integration, level coverage, asset coverage, automated checks, and manual acceptance.
- Do not rewrite old dated history merely because current state advanced.

### `AGENTS.md`

- Add, remove, or update routes for every active, new, renamed, or archived document.
- Describe each document’s unique responsibility and its main exclusions.
- Mirror the concise current-status summary from `00`; do not invent a second completion truth.
- Update workflow guidance when ownership changed, such as which schema or Domain document receives new fields.
- Do not copy full formulas, tables, test logs, or implementation maps into the route.

### `docs/README.md`

- Maintain active numeric reading order.
- Place archived material under History, not Technology or Gameplay.
- Add technical solution routes when they are part of the maintained reading order.

### Other routes

- Update `34_implementation_map.md` only for current locations, never for status or rules.
- Update schema indexes, technical solution references, workorders, tests, or comments that contain old paths or ownership.
- Search for the old filename and old responsibility wording until only intentional history remains.

## Validate Proportionally

Run at least:

```bash
git diff --check
rg -n '<old filename|old term|contradictory value>' AGENTS.md docs data scripts
.agents/skills/tiny-sea-war-audit-design-docs/scripts/audit_design_docs.sh <edited docs>
```

Also:

- validate every active Markdown link and referenced local path affected by the change;
- parse JSON when data changed;
- run the smallest relevant Godot tests when code, data, IDs, or runtime claims changed;
- run broader suites only in proportion to risk;
- do not run 20+ battle simulations without explicit authorization;
- distinguish a new regression from an unrelated or pre-existing failure;
- update `00` with actual, not expected, validation results.

Finish with `git status --short` and verify that every deletion, addition, and move is intentional.

## Deliver the Result

Report:

- files kept, tightened, split, merged, archived, deleted, and newly created;
- the new source-of-truth boundaries;
- contradictions and stale claims corrected;
- routes and status files updated;
- validation commands and exact results;
- unresolved failures or decisions still requiring explicit deletion authority.

Do not claim the audit is complete while active references are broken, current claims conflict, or an accepted split lacks synchronized routes.
