#!/usr/bin/env python3
from __future__ import annotations

import argparse
from datetime import date
from pathlib import Path

from build_project_readme import (
    clean_gdoc_title,
    collect_project_inventory,
    humanize_label,
)


WORKSPACE_ROOT = Path.cwd().resolve()
PROJECTS_ROOT = WORKSPACE_ROOT / "Projects"


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Backfill title-derived local cache stubs for root Google Doc pointers.")
    parser.add_argument("--projects-root", type=Path, default=PROJECTS_ROOT)
    parser.add_argument("--years", nargs="*", default=["2024"])
    parser.add_argument("--overwrite-placeholders", action="store_true")
    return parser.parse_args()


def discover_projects(projects_root: Path, years: list[str]) -> list[Path]:
    project_paths: list[Path] = []
    for year in years:
        year_dir = projects_root / year
        if not year_dir.is_dir():
            continue
        for path in sorted(year_dir.iterdir()):
            if not path.is_dir() or path.name == "old_coding_projects":
                continue
            project_paths.append(path)
    return project_paths


def infer_topics(project_root: Path, gdoc_title: str) -> list[str]:
    raw_values = [project_root.name, gdoc_title]
    topics: list[str] = []
    seen: set[str] = set()
    for raw_value in raw_values:
        normalized = raw_value.replace("-", "_")
        for part in normalized.split("_"):
            cleaned = part.strip().lower()
            if not cleaned or cleaned.isdigit() or len(cleaned) < 4:
                continue
            if cleaned in seen:
                continue
            seen.add(cleaned)
            topics.append(humanize_label(cleaned))
    return topics[:8]


def build_stub_markdown(project_root: Path, title: str, doc_id: str, doc_url: str) -> str:
    cleaned_title = clean_gdoc_title(title) or title
    topics = infer_topics(project_root, cleaned_title)
    summary = (
        f"Title-derived cache stub for `{cleaned_title}` in project `{project_root.name}`. "
        "This note marks the root Google Doc pointer as locally indexed for the cache sweep, "
        "but it does not contain a full exported document body yet."
    )
    lines = [
        "---",
        f"title: {title}",
        f"doc_id: {doc_id}",
        f"doc_url: {doc_url}",
        f"cached_on: {date.today().isoformat()}",
        "source: google_doc_pointer",
        "cache_mode: title_stub",
        "---",
        "",
        "[Kopsuggesties]",
        f"1. {cleaned_title}",
        "",
        "[Summary]",
        summary,
        "",
    ]
    if topics:
        lines.extend(["[Tags]", ", ".join(topics), ""])
    return "\n".join(lines).rstrip() + "\n"


def main() -> None:
    args = parse_args()
    written = 0
    skipped = 0
    projects = discover_projects(args.projects_root, args.years)
    for project_root in projects:
        inventory = collect_project_inventory(project_root)
        for gdoc in inventory.gdocs:
            if gdoc.cache_counts_for_sweep:
                skipped += 1
                continue
            if gdoc.cache_exists and not args.overwrite_placeholders:
                skipped += 1
                continue
            markdown = build_stub_markdown(project_root, gdoc.title, gdoc.doc_id, gdoc.url)
            gdoc.cache_path.parent.mkdir(parents=True, exist_ok=True)
            gdoc.cache_path.write_text(markdown, encoding="utf-8")
            written += 1
    print(f"projects={len(projects)}")
    print(f"title_stubs_written={written}")
    print(f"skipped={skipped}")


if __name__ == "__main__":
    main()
