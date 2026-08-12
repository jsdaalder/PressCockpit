#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import re
from pathlib import Path


IGNORE_DIRS = {
    ".git",
    ".next",
    ".obsidian",
    ".vercel",
    "__pycache__",
    "build",
    "coverage",
    "dist",
    "node_modules",
    "venv",
}

WIKILINK_RE = re.compile(r"\[\[([^\]|#]+)")
TOKEN_RE = re.compile(r"[A-Za-z0-9_][A-Za-z0-9_\-:/]{1,}")


def parse_frontmatter(text: str) -> tuple[dict[str, object], str]:
    if not text.startswith("---\n"):
        return {}, text
    end = text.find("\n---\n", 4)
    if end == -1:
        return {}, text
    block = text[4:end]
    body = text[end + 5 :]
    data: dict[str, object] = {}
    for line in block.splitlines():
        if ":" not in line:
            continue
        key, value = line.split(":", 1)
        key = key.strip()
        value = value.strip()
        if value.startswith("[") and value.endswith("]"):
            items = [item.strip().strip('"').strip("'") for item in value[1:-1].split(",") if item.strip()]
            data[key] = items
            continue
        data[key] = value.strip('"').strip("'")
    return data, body


def iter_markdown_files(vault_root: Path) -> list[Path]:
    paths: list[Path] = []
    for path in vault_root.rglob("*.md"):
        if any(part in IGNORE_DIRS for part in path.parts):
            continue
        paths.append(path)
    return sorted(paths)


def make_excerpt(body: str, limit: int = 400) -> str:
    compact = " ".join(body.split())
    return compact[:limit]


def build_record(vault_root: Path, note_path: Path) -> dict[str, object]:
    text = note_path.read_text(encoding="utf-8", errors="ignore")
    frontmatter, body = parse_frontmatter(text)
    title = frontmatter.get("title") or note_path.stem.replace("_", " ")
    return {
        "path": note_path.relative_to(vault_root).as_posix(),
        "title": title,
        "type": frontmatter.get("type", ""),
        "topics": frontmatter.get("topics", []),
        "entities": frontmatter.get("entities", []),
        "aliases": frontmatter.get("aliases", []),
        "project": frontmatter.get("project", ""),
        "links": sorted({match.strip() for match in WIKILINK_RE.findall(text)}),
        "excerpt": make_excerpt(body),
        "tokens": sorted({token.lower() for token in TOKEN_RE.findall(text)}),
    }


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Build a JSONL index of Markdown notes in the vault.")
    parser.add_argument("--vault-root", default=".", type=Path)
    parser.add_argument(
        "--output",
        default="Resources/knowledge_ops/index/notes_manifest.jsonl",
        type=Path,
    )
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    vault_root = args.vault_root.resolve()
    output_path = (vault_root / args.output).resolve() if not args.output.is_absolute() else args.output
    output_path.parent.mkdir(parents=True, exist_ok=True)
    records = [build_record(vault_root, path) for path in iter_markdown_files(vault_root)]
    with output_path.open("w", encoding="utf-8") as handle:
        for record in records:
            handle.write(json.dumps(record, ensure_ascii=False) + "\n")
    print(output_path)


if __name__ == "__main__":
    main()
