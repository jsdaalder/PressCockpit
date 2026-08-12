#!/usr/bin/env python3
from __future__ import annotations

import argparse
import csv
import os
import re
from collections import defaultdict
from pathlib import Path


WORKSPACE_ROOT = Path.cwd().resolve()
INDEX_ROOT = WORKSPACE_ROOT / "Resources" / "knowledge_ops" / "index"
PROJECTS_ROOT = WORKSPACE_ROOT / "Projects"
DASHBOARDS_ROOT = WORKSPACE_ROOT / "Areas" / "knowledge_base" / "dashboards"
PUBLICATION_INDEX_PATH = DASHBOARDS_ROOT / "publication_index.md"
PUBLICATION_EXCEPTIONS_PATH = DASHBOARDS_ROOT / "publication_exceptions.md"
ARCHIVED_UNPUBLISHED_INDEX_PATH = DASHBOARDS_ROOT / "publication_archived_unpublished.md"
ARCHIVED_PERSONAL_INDEX_PATH = DASHBOARDS_ROOT / "publication_archived_personal.md"

PUBLICATION_SECTION_START = "<!-- publication_status:start -->"
PUBLICATION_SECTION_END = "<!-- publication_status:end -->"
YEAR_NAMES = ("2022", "2023", "2024", "2025", "2026")


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Sync publication coverage back into project READMEs and Obsidian dashboard notes."
    )
    parser.add_argument("--index-root", type=Path, default=INDEX_ROOT)
    parser.add_argument("--projects-root", type=Path, default=PROJECTS_ROOT)
    parser.add_argument("--dashboards-root", type=Path, default=DASHBOARDS_ROOT)
    return parser.parse_args()


def read_csv(path: Path) -> list[dict[str, str]]:
    with path.open(encoding="utf-8", newline="") as handle:
        return list(csv.DictReader(handle))


def relative_href(from_path: Path, to_path: Path) -> str:
    return re.sub(r"\\\\", "/", os.path.relpath(to_path, start=from_path.parent))


def build_project_pdf_map(tracker_rows: list[dict[str, str]]) -> dict[str, list[dict[str, str]]]:
    mapping: dict[str, list[dict[str, str]]] = defaultdict(list)
    for row in tracker_rows:
        if row.get("match_status") != "matched":
            continue
        project_path = row.get("matched_project_path", "").strip()
        if not project_path:
            continue
        mapping[project_path].append(row)
    for rows in mapping.values():
        rows.sort(key=lambda item: (item.get("published_year", ""), item.get("pdf_title", "")))
    return mapping


def build_publication_section(readme_path: Path, matched_rows: list[dict[str, str]]) -> str:
    lines = [
        PUBLICATION_SECTION_START,
        "## Publication Status",
        "",
    ]
    if matched_rows:
        lines.extend(
            [
                "- Status: `published`",
                f"- Linked published PDFs: `{len(matched_rows)}`",
            ]
        )
        bases = [row.get("match_basis", "").strip() for row in matched_rows if row.get("match_basis", "").strip()]
        if bases:
            unique_bases = ", ".join(f"`{basis}`" for basis in dict.fromkeys(bases))
            lines.append(f"- Match basis used: {unique_bases}")
        lines.append("- Published stories:")
        for row in matched_rows:
            pdf_path = Path(row["pdf_path"])
            pdf_href = relative_href(readme_path, pdf_path)
            lines.append(
                f"  - [{row['pdf_title']}]({pdf_href}) — `{row['published_year']}`"
            )
    else:
        lines.extend(
            [
                "- Status: `no_linked_pdf`",
                "- Linked published PDFs: `0`",
                "- Note: No published PDF from the official corpus is linked to this project. This usually means the project did not lead to publication, or the archive is still incomplete.",
            ]
        )
    lines.extend(["", PUBLICATION_SECTION_END, ""])
    return "\n".join(lines)


def sync_readme(readme_path: Path, matched_rows: list[dict[str, str]]) -> None:
    if not readme_path.exists():
        return
    text = readme_path.read_text(encoding="utf-8")
    section = build_publication_section(readme_path, matched_rows)
    pattern = re.compile(
        rf"\n?{re.escape(PUBLICATION_SECTION_START)}.*?{re.escape(PUBLICATION_SECTION_END)}\n?",
        re.DOTALL,
    )
    if pattern.search(text):
        updated = pattern.sub(f"\n{section}\n", text)
    elif "\n## Google Docs\n" in text:
        updated = text.replace("\n## Google Docs\n", f"\n{section}\n## Google Docs\n", 1)
    else:
        updated = text.rstrip() + "\n\n" + section + "\n"
    old_next_step = "- Link this project to any published PDFs once publication status is confirmed."
    if matched_rows:
        new_next_step = "- Publication mapping is synced from `Resources/al_mijn_artikelen/` and `Resources/knowledge_ops/index/publication_tracker.csv`."
    else:
        new_next_step = "- No linked published PDF is currently mapped from the official corpus. If this project produced a story, add the PDF to `Resources/al_mijn_artikelen/` and rerun the tracker."
    updated = updated.replace(old_next_step, new_next_step)
    if updated != text:
        readme_path.write_text(updated, encoding="utf-8")


def build_dashboard_index(coverage_rows: list[dict[str, str]], tracker_rows: list[dict[str, str]]) -> str:
    matched_by_year: dict[str, list[dict[str, str]]] = defaultdict(list)
    for row in tracker_rows:
        if row.get("match_status") == "matched":
            matched_by_year[row["published_year"]].append(row)
    for rows in matched_by_year.values():
        rows.sort(key=lambda item: item["pdf_title"])

    unpublished_by_year: dict[str, list[dict[str, str]]] = defaultdict(list)
    for row in coverage_rows:
        if row.get("published_status_from_pdfs") != "published":
            unpublished_by_year[row["project_year"]].append(row)
    for rows in unpublished_by_year.values():
        rows.sort(key=lambda item: (item.get("readme_title") or item["project_slug"]).lower())

    lines = [
        "# Publication Index",
        "",
        "Generated from the PDF-first publication tracker. This is the canonical published-story index inside the vault.",
        "",
        "- Source of truth for publication status: `Resources/al_mijn_artikelen/`",
        "- Canonical PDF→project mapping: `Resources/knowledge_ops/index/publication_tracker.csv`",
        "- Archived unpublished projects live separately under `Archives/<year>/unpublished/` and are excluded from this dashboard.",
        "- Archived personal/tooling projects live separately under `Archives/<year>/personal/` and are excluded from this dashboard.",
        "",
    ]

    for year in YEAR_NAMES:
        matched_rows = matched_by_year.get(year, [])
        unpublished_rows = unpublished_by_year.get(year, [])
        lines.extend(
            [
                f"## {year}",
                f"- Published PDFs linked this year: `{len(matched_rows)}`",
                f"- Project folders without linked PDF: `{len(unpublished_rows)}`",
                "",
                "### Published Stories",
                "",
            ]
        )
        if matched_rows:
            for row in matched_rows:
                pdf_path = Path(row["pdf_path"])
                project_readme = Path(row["matched_project_readme"])
                pdf_href = relative_href(PUBLICATION_INDEX_PATH, pdf_path)
                readme_href = relative_href(PUBLICATION_INDEX_PATH, project_readme)
                project_label = row.get("matched_project_title") or row.get("matched_project_slug") or "project"
                lines.append(
                    f"- [{row['pdf_title']}]({pdf_href}) → [{project_label}]({readme_href})"
                )
        else:
            lines.append("- None")
        lines.extend(["", "### Projects Without Linked PDF", ""])
        if unpublished_rows:
            for row in unpublished_rows:
                readme_path = Path(row["readme_path"])
                readme_href = relative_href(PUBLICATION_INDEX_PATH, readme_path)
                label = row.get("readme_title") or row["project_slug"]
                quality = row.get("readme_quality", "")
                lines.append(f"- [{label}]({readme_href}) — README quality `{quality}`")
        else:
            lines.append("- None")
        lines.append("")
    return "\n".join(lines)


def build_archived_unpublished_index(rows: list[dict[str, str]]) -> str:
    by_year: dict[str, list[dict[str, str]]] = defaultdict(list)
    for row in rows:
        by_year[row["project_year"]].append(row)
    for year_rows in by_year.values():
        year_rows.sort(key=lambda item: (item.get("readme_title") or item["project_slug"]).lower())

    lines = [
        "# Archived Unpublished Projects",
        "",
        "Generated from `Resources/knowledge_ops/index/archived_unpublished_projects.csv`.",
        "These folders are intentionally excluded from the canonical publication coverage dashboard.",
        "",
    ]
    for year in YEAR_NAMES:
        year_rows = by_year.get(year, [])
        lines.extend([f"## {year}", f"- Archived unpublished folders: `{len(year_rows)}`", ""])
        if year_rows:
            for row in year_rows:
                readme_path = Path(row["readme_path"])
                readme_href = relative_href(ARCHIVED_UNPUBLISHED_INDEX_PATH, readme_path)
                label = row.get("readme_title") or row["project_slug"]
                quality = row.get("readme_quality", "")
                lines.append(f"- [{label}]({readme_href}) — README quality `{quality}`")
        else:
            lines.append("- None")
        lines.append("")
    return "\n".join(lines)


def build_archived_personal_index(rows: list[dict[str, str]]) -> str:
    by_year: dict[str, list[dict[str, str]]] = defaultdict(list)
    for row in rows:
        by_year[row["project_year"]].append(row)
    for year_rows in by_year.values():
        year_rows.sort(key=lambda item: (item.get("readme_title") or item["project_slug"]).lower())

    lines = [
        "# Archived Personal Projects",
        "",
        "Generated from `Resources/knowledge_ops/index/archived_personal_projects.csv`.",
        "These folders are intentionally excluded from the canonical publication coverage dashboard.",
        "",
    ]
    for year in YEAR_NAMES:
        year_rows = by_year.get(year, [])
        lines.extend([f"## {year}", f"- Archived personal/tooling folders: `{len(year_rows)}`", ""])
        if year_rows:
            for row in year_rows:
                readme_path = Path(row["readme_path"])
                readme_href = relative_href(ARCHIVED_PERSONAL_INDEX_PATH, readme_path)
                label = row.get("readme_title") or row["project_slug"]
                quality = row.get("readme_quality", "")
                lines.append(f"- [{label}]({readme_href}) — README quality `{quality}`")
        else:
            lines.append("- None")
        lines.append("")
    return "\n".join(lines)


def build_exceptions_note(tracker_rows: list[dict[str, str]]) -> str:
    unresolved = [row for row in tracker_rows if row.get("match_status") != "matched"]
    lines = [
        "# Publication Exceptions",
        "",
        "Use this note as the short exception list. The detailed editable review queue remains in `Resources/knowledge_ops/index/publication_review_worklist.md`.",
        "",
    ]
    if not unresolved:
        lines.extend(
            [
                "- Current status: `0` unresolved publication mappings.",
                "- Action: no review needed right now.",
                "",
            ]
        )
        return "\n".join(lines)

    by_year: dict[str, list[dict[str, str]]] = defaultdict(list)
    for row in unresolved:
        by_year[row["published_year"]].append(row)

    for year in sorted(by_year):
        lines.extend([f"## {year}", ""])
        for row in sorted(by_year[year], key=lambda item: item["pdf_title"]):
            lines.append(f"- `{row['match_status']}` — {row['pdf_title']}")
        lines.append("")
    return "\n".join(lines)


def main() -> None:
    args = parse_args()
    tracker_rows = read_csv(args.index_root / "publication_tracker.csv")
    coverage_rows = read_csv(args.index_root / "project_publication_coverage.csv")
    archived_unpublished_rows = []
    archived_unpublished_path = args.index_root / "archived_unpublished_projects.csv"
    if archived_unpublished_path.exists():
        archived_unpublished_rows = read_csv(archived_unpublished_path)
    archived_personal_rows = []
    archived_personal_path = args.index_root / "archived_personal_projects.csv"
    if archived_personal_path.exists():
        archived_personal_rows = read_csv(archived_personal_path)
    args.dashboards_root.mkdir(parents=True, exist_ok=True)

    project_pdf_map = build_project_pdf_map(tracker_rows)
    for row in coverage_rows:
        sync_readme(Path(row["readme_path"]), project_pdf_map.get(row["project_path"], []))

    PUBLICATION_INDEX_PATH.write_text(
        build_dashboard_index(coverage_rows, tracker_rows) + "\n",
        encoding="utf-8",
    )
    PUBLICATION_EXCEPTIONS_PATH.write_text(
        build_exceptions_note(tracker_rows),
        encoding="utf-8",
    )
    ARCHIVED_UNPUBLISHED_INDEX_PATH.write_text(
        build_archived_unpublished_index(archived_unpublished_rows) + "\n",
        encoding="utf-8",
    )
    ARCHIVED_PERSONAL_INDEX_PATH.write_text(
        build_archived_personal_index(archived_personal_rows) + "\n",
        encoding="utf-8",
    )


if __name__ == "__main__":
    main()
