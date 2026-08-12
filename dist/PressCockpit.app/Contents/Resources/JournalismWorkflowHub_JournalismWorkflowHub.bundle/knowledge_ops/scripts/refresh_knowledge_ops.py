#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import subprocess
import sys
from pathlib import Path

from build_project_readme import assess_readme_quality, collect_project_inventory
from build_project_readmes_bulk import YEAR_NAMES, discover_projects


WORKSPACE_ROOT = Path.cwd().resolve()
PROJECTS_ROOT = WORKSPACE_ROOT / "Projects"
INDEX_ROOT = WORKSPACE_ROOT / "Resources" / "knowledge_ops" / "index"
SUMMARY_PATH = INDEX_ROOT / "refresh_knowledge_ops_summary.json"
SCRIPTS_ROOT = Path(__file__).resolve().parent


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Run the local knowledge_ops refresh pipeline: fetch queue, READMEs, note index, and publication tracker."
    )
    parser.add_argument("--projects-root", type=Path, default=PROJECTS_ROOT)
    parser.add_argument("--years", nargs="*", default=list(YEAR_NAMES))
    parser.add_argument(
        "--project-root",
        action="append",
        type=Path,
        default=[],
        help="Rebuild only these project folders instead of bulk-refreshing all projects in the selected years.",
    )
    parser.add_argument("--overwrite", action="store_true", help="Overwrite existing README.md files.")
    parser.add_argument(
        "--backfill-title-stubs",
        action="store_true",
        help="Create title-derived cache stubs for any root `.gdoc` pointers that still only have placeholders.",
    )
    parser.add_argument("--skip-queue", action="store_true")
    parser.add_argument("--skip-readmes", action="store_true")
    parser.add_argument("--skip-note-index", action="store_true")
    parser.add_argument("--skip-publication-tracker", action="store_true")
    parser.add_argument("--skip-publication-artifacts", action="store_true")
    parser.add_argument("--skip-publication-metadata", action="store_true")
    parser.add_argument("--summary-path", type=Path, default=SUMMARY_PATH)
    return parser.parse_args()


def run_step(step: str, command: list[str]) -> None:
    print(f"[run] {step}")
    print(" ".join(command))
    subprocess.run(command, check=True)


def normalize_project_roots(args: argparse.Namespace) -> list[Path]:
    if args.project_root:
        return sorted(dict.fromkeys(path.resolve() for path in args.project_root))
    return discover_projects(args.projects_root, args.years)


def build_summary(project_roots: list[Path], years: list[str]) -> dict[str, object]:
    queue_json = INDEX_ROOT / "gdoc_fetch_queue.json"
    coverage_json = INDEX_ROOT / "project_readme_coverage.json"

    queue_rows = json.loads(queue_json.read_text(encoding="utf-8")) if queue_json.exists() else []
    coverage_rows = json.loads(coverage_json.read_text(encoding="utf-8")) if coverage_json.exists() else []
    selected_paths = {str(path.resolve()) for path in project_roots}

    selected_queue_rows = [row for row in queue_rows if row.get("project_path") in selected_paths]
    selected_coverage_rows = [row for row in coverage_rows if row.get("project_path") in selected_paths]

    quality_counts: dict[str, int] = {}
    cached_gdocs = 0
    total_gdocs = 0

    project_rows: list[dict[str, object]] = []
    for project_root in project_roots:
        inventory = collect_project_inventory(project_root)
        quality = assess_readme_quality(inventory)
        quality_counts[quality] = quality_counts.get(quality, 0) + 1
        cached_count = len([gdoc for gdoc in inventory.gdocs if gdoc.cache_has_body])
        total_gdocs += len(inventory.gdocs)
        cached_gdocs += cached_count
        project_rows.append(
            {
                "project_year": project_root.parent.name,
                "project_slug": project_root.name,
                "project_path": str(project_root),
                "readme_path": str(project_root / "README.md"),
                "readme_quality": quality,
                "root_gdoc_count": len(inventory.gdocs),
                "cached_root_gdoc_count": cached_count,
                "docs_file_count": len(inventory.docs_files),
            }
        )

    return {
        "generated_on": __import__("datetime").date.today().isoformat(),
        "years": years,
        "project_count": len(project_roots),
        "selected_root_gdoc_count": total_gdocs,
        "selected_cached_root_gdoc_count": cached_gdocs,
        "selected_pending_gdoc_fetch_count": len(selected_queue_rows),
        "selected_readme_quality_counts": quality_counts,
        "global_pending_gdoc_fetch_count": len(queue_rows),
        "selected_coverage_row_count": len(selected_coverage_rows),
        "projects": project_rows,
    }


def main() -> None:
    args = parse_args()
    args.summary_path.parent.mkdir(parents=True, exist_ok=True)
    project_roots = normalize_project_roots(args)

    if args.backfill_title_stubs:
        run_step(
            "Backfill title-derived Google Doc cache stubs",
            [
                sys.executable,
                str(SCRIPTS_ROOT / "backfill_gdoc_title_stubs.py"),
                "--years",
                *args.years,
                "--overwrite-placeholders",
            ],
        )

    if not args.skip_queue:
        run_step(
            "Build Google Doc fetch queue",
            [
                sys.executable,
                str(SCRIPTS_ROOT / "build_gdoc_fetch_queue.py"),
                "--years",
                *args.years,
                "--write-index",
            ],
        )

    if not args.skip_readmes:
        if args.project_root:
            for project_root in project_roots:
                command = [
                    sys.executable,
                    str(SCRIPTS_ROOT / "build_project_readme.py"),
                    "--project-root",
                    str(project_root),
                    "--write-readme",
                ]
                if args.overwrite:
                    command.append("--overwrite")
                run_step(f"Refresh README for {project_root.name}", command)
        else:
            command = [
                sys.executable,
                str(SCRIPTS_ROOT / "build_project_readmes_bulk.py"),
                "--years",
                *args.years,
                "--write-index",
            ]
            if args.overwrite:
                command.append("--overwrite")
            run_step("Refresh project READMEs in bulk", command)

    if not args.skip_publication_tracker:
        run_step(
            "Build publication tracker",
            [
                sys.executable,
                str(SCRIPTS_ROOT / "build_publication_tracker.py"),
            ],
        )

    if not args.skip_publication_artifacts:
        run_step(
            "Sync published PDF text into project caches",
            [
                sys.executable,
                str(SCRIPTS_ROOT / "sync_publication_artifacts.py"),
                "--overwrite",
            ],
        )

    if not args.skip_readmes and not args.skip_publication_artifacts:
        if args.project_root:
            for project_root in project_roots:
                command = [
                    sys.executable,
                    str(SCRIPTS_ROOT / "build_project_readme.py"),
                    "--project-root",
                    str(project_root),
                    "--write-readme",
                ]
                if args.overwrite:
                    command.append("--overwrite")
                run_step(f"Refresh README from publication artifacts for {project_root.name}", command)
        else:
            command = [
                sys.executable,
                str(SCRIPTS_ROOT / "build_project_readmes_bulk.py"),
                "--years",
                *args.years,
                "--write-index",
            ]
            if args.overwrite:
                command.append("--overwrite")
            run_step("Refresh project READMEs after publication artifact sync", command)

    if not args.skip_publication_metadata:
        run_step(
            "Sync publication metadata into project READMEs and dashboards",
            [
                sys.executable,
                str(SCRIPTS_ROOT / "sync_publication_metadata.py"),
            ],
        )

    if not args.skip_note_index:
        run_step(
            "Build vault note index",
            [
                sys.executable,
                str(SCRIPTS_ROOT / "build_note_index.py"),
                "--vault-root",
                str(WORKSPACE_ROOT),
            ],
        )

    summary = build_summary(project_roots, args.years)
    args.summary_path.write_text(json.dumps(summary, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(f"[done] wrote summary to {args.summary_path}")


if __name__ == "__main__":
    main()
