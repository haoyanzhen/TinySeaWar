"""Check local Markdown targets, heading anchors and literal docs paths.

Run with uv run --locked python; optional paths extend the default AGENTS/docs
scope to repository or personal skills. Historical proposals are reported separately.
"""
from __future__ import annotations

import argparse
import json
import re
from pathlib import Path
from urllib.parse import unquote


def visible_text(text: str) -> str:
    return re.sub(r"^```[^\n]*\n.*?^```[^\n]*$", "", text, flags=re.M | re.S)


def anchors(path: Path) -> set[str]:
    text = visible_text(path.read_text())
    result = set(re.findall(r'<(?:a|\w+)\b[^>]*\bid=["\']([^"\']+)', text))
    counts: dict[str, int] = {}
    for heading in re.findall(r"^#{1,6}\s+(.+?)\s*#*\s*$", text, re.M):
        heading = re.sub(r"\[([^\]]+)\]\([^)]+\)", r"\1", heading)
        heading = re.sub(r"<[^>]+>", "", heading).lower()
        slug = re.sub(r"[^\w\-\s]", "", heading)
        slug = re.sub(r"\s", "-", slug)
        count = counts.get(slug, 0)
        counts[slug] = count + 1
        result.add(slug if count == 0 else f"{slug}-{count}")
    return result


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("paths", nargs="*", type=Path)
    args = parser.parse_args()
    root = Path.cwd()
    files = {root / "AGENTS.md", *root.glob("docs/**/*.md")}
    for candidate in args.paths:
        files.update(candidate.rglob("*.md") if candidate.is_dir() else [candidate])
    errors = []
    historical = []
    link_count = anchor_count = literal_count = 0
    cache: dict[Path, set[str]] = {}
    for path in sorted(files):
        text = visible_text(path.read_text())
        for match in re.finditer(r"!?\[[^\]\n]*\]\((<[^>]+>|[^\s)]+)(?:\s+[\"'][^\n]*[\"'])?\)", text):
            target = match.group(1).strip("<>")
            if re.match(r"^[A-Za-z][\w+.-]*:", target):
                continue
            base, _, fragment = unquote(target).partition("#")
            resolved = (path.parent / base).resolve() if base else path.resolve()
            link_count += 1
            if not resolved.exists():
                errors.append({"file": str(path), "kind": "target", "target": target})
            elif fragment and resolved.suffix == ".md":
                anchor_count += 1
                if resolved not in cache:
                    cache[resolved] = anchors(resolved)
                if fragment not in cache[resolved]:
                    errors.append({"file": str(path), "kind": "anchor", "target": target})
        for target in sorted(set(re.findall(r"(?<![\w/])(docs/[A-Za-z0-9_./-]+\.md)", text))):
            literal_count += 1
            if not (root / target).exists():
                if path.name == "00_project_status_through_20261010.md" and target in {
                    "docs/93_ai_navigation_facility_review.md", "docs/94_ai_navigation_facility_followup.md"
                }:
                    historical.append({"file": str(path), "target": target})
                else:
                    errors.append({"file": str(path), "kind": "literal", "target": target})
    print(json.dumps({"files": len(files), "links": link_count, "anchors": anchor_count,
                      "literal_occurrences": literal_count, "historical_mentions": historical,
                      "errors": errors}, ensure_ascii=False, indent=2))
    return int(bool(errors))


if __name__ == "__main__":
    raise SystemExit(main())
