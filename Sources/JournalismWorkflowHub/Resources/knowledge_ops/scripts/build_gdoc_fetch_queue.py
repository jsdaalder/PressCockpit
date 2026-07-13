#!/usr/bin/env python3
from __future__ import annotations

import argparse
import csv
import json
from pathlib import Path

from build_project_readme import collect_project_inventory, ensure_cache_placeholders


WORKSPACE_ROOT = Path.cwd().resolve()
PROJECTS_ROOT = WORKSPACE_ROOT / "Projects"
INDEX_ROOT = WORKSPACE_ROOT / "Resources" / "knowledge_ops" / "index"
YEAR_NAMES = ("2022", "2023", "2024", "2025", "2026")


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Build a queue of root Google Docs that still need local cache content.")
    parser.add_argument("--projects-root", type=Path, default=PROJECTS_ROOT)
    parser.add_argument("--years", nargs="*", default=list(YEAR_NAMES))
    parser.add_argument("--write-index", action="store_true")
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


def main() -> None:
    args = parse_args()
    queue_rows: list[dict[str, object]] = []
    projects = discover_projects(args.projects_root, args.years)
    for project_root in projects:
        inventory = collect_project_inventory(project_root)
        ensure_cache_placeholders(inventory)
        inventory = collect_project_inventory(project_root)
        for gdoc in inventory.gdocs:
            if gdoc.cache_counts_for_sweep:
                continue
            queue_rows.append(
                {
                    "project_year": project_root.parent.name,
                    "project_slug": project_root.name,
                    "project_path": str(project_root),
                    "gdoc_title": gdoc.title,
                    "gdoc_pointer_path": str(gdoc.path),
                    "doc_id": gdoc.doc_id,
                    "doc_url": gdoc.url,
                    "cache_path": str(gdoc.cache_path),
                }
            )

    if args.write_index:
        INDEX_ROOT.mkdir(parents=True, exist_ok=True)
        csv_path = INDEX_ROOT / "gdoc_fetch_queue.csv"
        json_path = INDEX_ROOT / "gdoc_fetch_queue.json"
        with csv_path.open("w", encoding="utf-8", newline="") as handle:
            writer = csv.DictWriter(handle, fieldnames=list(queue_rows[0].keys()) if queue_rows else [])
            writer.writeheader()
            writer.writerows(queue_rows)
        json_path.write_text(json.dumps(queue_rows, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")

    print(f"projects={len(projects)}")
    print(f"queue_items={len(queue_rows)}")


if __name__ == "__main__":
    main()
