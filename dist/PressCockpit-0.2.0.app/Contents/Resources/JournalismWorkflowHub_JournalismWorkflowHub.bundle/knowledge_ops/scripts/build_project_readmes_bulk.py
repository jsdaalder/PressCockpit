#!/usr/bin/env python3
from __future__ import annotations

import argparse
import csv
import json
from pathlib import Path

from build_project_readme import (
    assess_readme_quality,
    best_gdoc,
    build_readme,
    collect_project_inventory,
    ensure_cache_placeholders,
    parse_frontmatter,
    sample_paths,
    write_manifest,
)


WORKSPACE_ROOT = Path.cwd().resolve()
PROJECTS_ROOT = WORKSPACE_ROOT / "Projects"
INDEX_ROOT = WORKSPACE_ROOT / "Resources" / "knowledge_ops" / "index"
YEAR_NAMES = ("2022", "2023", "2024", "2025", "2026")


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Bulk-build README.md files for year-based project folders.")
    parser.add_argument("--projects-root", type=Path, default=PROJECTS_ROOT)
    parser.add_argument("--years", nargs="*", default=list(YEAR_NAMES))
    parser.add_argument("--overwrite", action="store_true", help="Overwrite existing README.md files.")
    parser.add_argument(
        "--write-index",
        action="store_true",
        help="Write coverage CSV/JSON files into Resources/knowledge_ops/index.",
    )
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
    projects = discover_projects(args.projects_root, args.years)
    results: list[dict[str, object]] = []
    generated = 0
    skipped = 0

    for project_root in projects:
        inventory = collect_project_inventory(project_root)
        ensure_cache_placeholders(inventory)
        inventory = collect_project_inventory(project_root)
        write_manifest(inventory)
        readme = build_readme(inventory)
        readme_exists = inventory.readme_path.exists()

        if readme_exists and not args.overwrite:
            action = "skipped_existing"
            skipped += 1
        else:
            inventory.readme_path.write_text(readme, encoding="utf-8")
            action = "overwritten" if readme_exists else "created"
            generated += 1

        metadata, body = parse_frontmatter(readme)
        title = ""
        for line in body.splitlines():
            if line.startswith("# "):
                title = line[2:].strip()
                break

        primary_gdoc = best_gdoc(inventory)
        results.append(
            {
                "project_year": project_root.parent.name,
                "project_slug": project_root.name,
                "project_path": str(project_root),
                "readme_path": str(inventory.readme_path),
                "action": action,
                "readme_quality": assess_readme_quality(inventory),
                "project_title": title,
                "root_gdoc_count": len(inventory.gdocs),
                "cached_root_gdoc_count": len([gdoc for gdoc in inventory.gdocs if gdoc.cache_has_body]),
                "primary_gdoc_title": primary_gdoc.title if primary_gdoc else "",
                "docs_file_count": len(inventory.docs_files),
                "root_file_count": len(inventory.root_files),
            }
        )
        print(f"{action}\t{project_root}")

    if args.write_index:
        INDEX_ROOT.mkdir(parents=True, exist_ok=True)
        csv_path = INDEX_ROOT / "project_readme_coverage.csv"
        json_path = INDEX_ROOT / "project_readme_coverage.json"
        with csv_path.open("w", encoding="utf-8", newline="") as handle:
            writer = csv.DictWriter(handle, fieldnames=list(results[0].keys()) if results else [])
            writer.writeheader()
            writer.writerows(results)
        json_path.write_text(json.dumps(results, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")

    quality_counts: dict[str, int] = {}
    for row in results:
        quality = str(row["readme_quality"])
        quality_counts[quality] = quality_counts.get(quality, 0) + 1

    print(f"projects={len(projects)}")
    print(f"generated={generated}")
    print(f"skipped_existing={skipped}")
    print(json.dumps({"quality_counts": quality_counts}, ensure_ascii=False))


if __name__ == "__main__":
    main()
