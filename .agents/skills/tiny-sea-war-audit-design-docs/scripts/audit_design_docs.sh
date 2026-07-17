#!/usr/bin/env bash
set -euo pipefail

if ! command -v rg >/dev/null 2>&1; then
  printf 'ERROR: rg is required.\n' >&2
  exit 2
fi

files=()
if (($# > 0)); then
  for candidate in "$@"; do
    if [[ -f "$candidate" ]]; then
      files+=("$candidate")
    else
      printf 'WARN missing input: %s\n' "$candidate" >&2
    fi
  done
else
  while IFS= read -r candidate; do
    files+=("$candidate")
  done < <(find docs -maxdepth 1 -type f -name '[0-9][0-9]_*.md' | LC_ALL=C sort)
fi

if ((${#files[@]} == 0)); then
  printf 'ERROR: no design documents selected.\n' >&2
  exit 2
fi

printf '# Tiny Sea War design document inventory\n\n'
printf 'Selected files: %d\n\n' "${#files[@]}"

printf '## Size and opening boundary\n\n'
printf '%-58s %7s %9s %9s  %s\n' 'FILE' 'LINES' 'BYTES' 'HEADINGS' 'BOUNDARY'
for file in "${files[@]}"; do
  lines=$(wc -l <"$file" | tr -d ' ')
  bytes=$(wc -c <"$file" | tr -d ' ')
  headings=$(rg -c '^#{1,6} ' "$file" || true)
  boundary='missing'
  if sed -n '1,24p' "$file" | rg -q '功能与边界|文档定位|文档目的|功能和边界|职责与边界'; then
    boundary='present'
  fi
  printf '%-58s %7s %9s %9s  %s\n' "$file" "$lines" "$bytes" "$headings" "$boundary"
done

printf '\n## Potentially duplicated headings\n\n'
heading_output=$(
  { rg --no-filename '^#{2,6} ' "${files[@]}" || true; } \
    | sed -E 's/^#{2,6}[[:space:]]+//' \
    | LC_ALL=C sort \
    | uniq -c \
    | awk '$1 > 1 { count=$1; $1=""; sub(/^ /, ""); printf "%4d  %s\n", count, $0 }'
)
if [[ -n "$heading_output" ]]; then
  printf '%s\n' "$heading_output"
else
  printf 'None.\n'
fi

printf '\n## Stale or ownership-leak candidates\n\n'
candidate_pattern='Tinny Sea War|未来实现|建议新增|当前已实现|当前未实现|尚未实施|待实施|已完成|代码路径|测试通过|[0-9]+/[0-9]+'
if ! rg -n "$candidate_pattern" "${files[@]}"; then
  printf 'None.\n'
fi

printf '\n## Literal docs references missing from the workspace\n\n'
missing_count=0
while IFS= read -r reference; do
  [[ -z "$reference" ]] && continue
  if [[ ! -e "$reference" ]]; then
    printf '%s\n' "$reference"
    missing_count=$((missing_count + 1))
  fi
done < <({ rg --no-filename -o 'docs/[A-Za-z0-9_./-]+\.md' "${files[@]}" || true; } | LC_ALL=C sort -u)
if ((missing_count == 0)); then
  printf 'None.\n'
fi

printf '\n## References to archived documents\n\n'
if ! rg -n 'docs/history/|history/[A-Za-z0-9_./-]+\.md' "${files[@]}"; then
  printf 'None.\n'
fi

printf '\n## File references and inbound consumers\n\n'
for file in "${files[@]}"; do
  base=$(basename "$file")
  consumers=$({ rg -l --fixed-strings "$base" AGENTS.md docs data scripts tools workorder 2>/dev/null || true; } \
    | LC_ALL=C sort \
    | tr '\n' ' ')
  if [[ -z "$consumers" ]]; then
    consumers='none'
  fi
  printf '%s <- %s\n' "$file" "$consumers"
done

printf '\nInventory complete. Verify every candidate against full document and repository evidence.\n'
