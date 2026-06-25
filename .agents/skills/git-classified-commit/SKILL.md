---
name: git-classified-commit
description: Classify and commit TinySeaWar working-tree changes as cohesive Git commits using the repository's established prefixes and message style. Use when the user asks to perform a Git commit, classified commit, split current changes into commits, or commit the current workspace changes.
---

# Git Classified Commit

## Workflow

1. Inspect `git status --short --branch`, unstaged and staged file lists, untracked files, diff summaries, and recent commit messages.
2. Identify generated caches, editor state, import files, logs, and other artifacts that should not be committed. Do not delete or revert user changes merely to simplify grouping.
3. Group files by cohesive purpose. Prefer the existing prefixes:
   - `docs:` for design, audit, guides, and work orders.
   - `feat:` for runtime behavior, data contracts, scenes, and user-facing functionality.
   - `assets:` for character, UI, environment, and VFX assets plus their generated manifests.
   - `tools:` for art pipelines, generators, validators, and maintenance scripts.
   - `gd:` for isolated Godot project/import configuration.
   - Use `fix:`, `test:`, or `chore:` only when they more accurately describe the change.
4. Keep tightly coupled generated data with its owning feature or asset group. Avoid splitting files by hunk unless that is necessary for commits to remain coherent.
5. Before each commit, stage only that group, run `git diff --cached --check`, inspect the staged summary, and create a concise lowercase-prefix English commit message matching repository history.
6. After all commits, confirm the working tree is clean, list the new commit hashes, and report whether the branch is ahead of its remote.

## Validation Policy

- Do not run Godot tests during routine Git classification or commit requests.
- Specifically do not run `scripts/tests/test_runner.gd`, `scripts/tests/scene_presentation_test.gd`, render QA, or other Godot headless test commands unless the user explicitly requests testing in the same turn.
- Do not run broad project test suites merely because code is being committed.
- Keep lightweight commit-integrity checks such as `git diff --cached --check`. Run a narrowly relevant non-Godot validator only when needed to determine whether generated files belong together or when the user explicitly requests validation.
- State that tests were not run only when the final summary would otherwise imply verification; a routine classified-commit summary may simply list the integrity checks performed.

## Safety And Scope

- Preserve unrelated user changes and never use destructive reset or checkout commands.
- Do not commit ignored caches such as `.godot/`, `*.import`, `__pycache__/`, `.DS_Store`, logs, or temporary outputs.
- Treat Git LFS pointer-managed assets as normal project files; do not replace them with raw pointer text manually.
- Do not push, create branches, or open pull requests unless the user explicitly asks.
- If a staged set already exists, inspect it and reorganize only as needed for coherent commits without discarding content.
