#!/usr/bin/env python3
from __future__ import annotations

import csv
import json
import re
import subprocess
import unicodedata
from collections import Counter, defaultdict
from dataclasses import dataclass
from datetime import datetime
from difflib import SequenceMatcher
from pathlib import Path
from types import SimpleNamespace
from typing import Iterable

from build_project_readme import collect_project_inventory


WORKSPACE_ROOT = Path.cwd().resolve()
OFFICIAL_CORPUS_ROOT = WORKSPACE_ROOT / "Resources" / "al_mijn_artikelen"
LEGACY_CORPUS_ROOT = WORKSPACE_ROOT / "Resources" / "legacy_articles"
PROJECTS_ROOT = WORKSPACE_ROOT / "Projects"
ARCHIVES_ROOT = WORKSPACE_ROOT / "Archives"
PROJECT_ROOTS = (PROJECTS_ROOT, ARCHIVES_ROOT)
INDEX_ROOT = WORKSPACE_ROOT / "Resources" / "knowledge_ops" / "index"
REPORTS_ROOT = OFFICIAL_CORPUS_ROOT / "reports"
YEAR_NAMES = ("2022", "2023", "2024", "2025", "2026")
UNPUBLISHED_DIRNAME = "unpublished"
PERSONAL_DIRNAME = "personal"
NON_PROJECT_DIRNAMES = {"docs", "raw", "text", "notes", "output", "_derived"}
SYSTEM_NAMES = {".DS_Store", "README", "readme"}
GENERIC_TOKENS = {
    "follow",
    "the",
    "money",
    "platform",
    "voor",
    "onderzoeksjournalistiek",
    "for",
    "investigative",
    "journalism",
    "ftm",
    "artikel",
    "story",
    "project",
}
PDF_SUFFIX_RE = re.compile(
    r"\s*-\s*follow the money\s*-\s*platform\s*(voor onderzoeksjournalistiek|for investigative journalism)\s*$",
    re.IGNORECASE,
)
TRAILING_COPY_RE = re.compile(r"\s*\(\d+\)\s*$")
DATE_LINE_RE = re.compile(r"(?P<day>\d{1,2})\s+(?P<month>[A-ZÀ-Ý]{3,})\s+(?P<year>20\d{2})(?:\s+[·•]\s+\d+\s+MIN(?:\.|(?:UTEN?\.)?)?.*)?$")
NOISE_PREFIXES = (
    "http://",
    "https://",
    "follow the money",
    "platform voor onderzoeksjournalistiek",
    "platform for investigative journalism",
)


@dataclass(frozen=True)
class PdfRecord:
    path: Path
    title: str
    normalized_title: str
    token_key: tuple[str, ...]
    headline: str
    normalized_headline: str
    published_year: str
    published_year_source: str
    date_line: str


@dataclass(frozen=True)
class ProjectRecord:
    year: str
    slug: str
    path: Path
    readme_path: Path
    readme_title: str
    readme_summary: str
    readme_likely_headline: str
    readme_topics: tuple[str, ...]
    readme_quality: str
    root_gdocs: tuple[str, ...]
    root_files: tuple[str, ...]
    candidate_labels: tuple[str, ...]
    semantic_tokens: frozenset[str]


@dataclass(frozen=True)
class MatchCandidate:
    project: ProjectRecord
    score: float
    basis: str
    candidate_label: str


def normalize_text(text: str) -> str:
    stem = text.removesuffix(".pdf").removesuffix(".gdoc").removesuffix(".md")
    stem = stem.replace("_", " ")
    stem = unicodedata.normalize("NFKD", stem)
    stem = "".join(ch for ch in stem if not unicodedata.combining(ch))
    stem = PDF_SUFFIX_RE.sub("", stem)
    stem = TRAILING_COPY_RE.sub("", stem)
    stem = stem.lower()
    stem = re.sub(r"[’'`´]", "", stem)
    stem = re.sub(r"[^a-z0-9]+", " ", stem)
    stem = re.sub(r"\s+", " ", stem).strip()
    return stem


def token_key(text: str) -> tuple[str, ...]:
    tokens = [token for token in normalize_text(text).split() if token not in GENERIC_TOKENS and len(token) > 1]
    return tuple(dict.fromkeys(tokens))


def parse_frontmatter(text: str) -> tuple[dict[str, str], str]:
    if not text.startswith("---\n"):
        return {}, text
    lines = text.splitlines()
    metadata: dict[str, str] = {}
    end_index = None
    for idx in range(1, len(lines)):
        if lines[idx].strip() == "---":
            end_index = idx
            break
        if ":" not in lines[idx]:
            continue
        key, value = lines[idx].split(":", 1)
        metadata[key.strip()] = value.strip()
    if end_index is None:
        return {}, text
    body = "\n".join(lines[end_index + 1 :]).lstrip("\n")
    return metadata, body


def extract_readme_snapshot(readme_path: Path) -> tuple[str, str, str, tuple[str, ...]]:
    if not readme_path.exists():
        return "", "", "", ()
    try:
        _, body = parse_frontmatter(readme_path.read_text(encoding="utf-8"))
    except OSError:
        return "", "", "", ()

    title = ""
    summary = ""
    likely_headline = ""
    topics: tuple[str, ...] = ()
    for line in body.splitlines():
        stripped = line.strip()
        if stripped.startswith("# ") and not title:
            title = stripped.removeprefix("# ").strip()
            continue
        if stripped.startswith("- Summary:") and not summary:
            summary = stripped.removeprefix("- Summary:").strip()
            continue
        if stripped.startswith("- Likely published headline:") and not likely_headline:
            likely_headline = stripped.removeprefix("- Likely published headline:").strip()
            continue
        if stripped.startswith("- Observed topics:") and not topics:
            parts = re.findall(r"`([^`]+)`", stripped)
            topics = tuple(parts)
            continue
        if title and summary and likely_headline and topics:
            break
    return title, summary, likely_headline, topics


def score_candidate(candidate: str, pdf: PdfRecord) -> tuple[float, str]:
    candidate_norm = normalize_text(candidate)
    candidate_tokens = set(token_key(candidate))
    title_tokens = set(pdf.token_key)
    headline_tokens = set(token_key(pdf.headline))

    if not candidate_norm:
        return 0.0, "empty"

    possible_targets = []
    if pdf.normalized_title:
        possible_targets.append(("title", pdf.normalized_title, title_tokens))
    if pdf.normalized_headline and pdf.normalized_headline != pdf.normalized_title:
        possible_targets.append(("headline", pdf.normalized_headline, headline_tokens))

    best_score = 0.0
    best_basis = "none"
    for target_name, target_norm, target_tokens in possible_targets:
        if candidate_norm == target_norm:
            score = 1.0
            basis = f"exact_{target_name}"
        elif candidate_tokens and candidate_tokens == target_tokens:
            score = 0.99
            basis = f"token_exact_{target_name}"
        elif len(candidate_tokens) >= 3 and candidate_tokens and candidate_tokens.issubset(target_tokens):
            score = 0.95
            basis = f"candidate_subset_{target_name}"
        elif len(target_tokens) >= 3 and target_tokens and target_tokens.issubset(candidate_tokens):
            score = 0.92
            basis = f"pdf_subset_{target_name}"
        else:
            sequence = SequenceMatcher(None, candidate_norm, target_norm).ratio()
            jaccard = len(candidate_tokens & target_tokens) / len(candidate_tokens | target_tokens) if candidate_tokens or target_tokens else 0.0
            prefix_bonus = 0.05 if target_norm.startswith(candidate_norm) or candidate_norm.startswith(target_norm) else 0.0
            score = min(0.89, 0.6 * sequence + 0.4 * jaccard + prefix_bonus)
            basis = f"fuzzy_{target_name}"
        if score > best_score:
            best_score = score
            best_basis = basis
    return best_score, best_basis


def extract_pdf_page_text(path: Path) -> list[str]:
    try:
        result = subprocess.run(
            ["pdftotext", "-f", "1", "-l", "1", "-nopgbrk", str(path), "-"],
            capture_output=True,
            text=True,
            check=True,
        )
    except (OSError, subprocess.CalledProcessError):
        return []
    return result.stdout.splitlines()


def infer_year_from_filesystem(path: Path) -> str:
    try:
        stats = path.stat()
    except OSError:
        return ""
    candidates = []
    birthtime = getattr(stats, "st_birthtime", None)
    if birthtime:
        candidates.append(datetime.fromtimestamp(birthtime).year)
    candidates.append(datetime.fromtimestamp(stats.st_mtime).year)
    for year in candidates:
        year_str = str(year)
        if year_str in YEAR_NAMES:
            return year_str
    return ""


def extract_pdf_metadata(path: Path) -> tuple[str, str, str, str]:
    raw_lines = [line.strip() for line in extract_pdf_page_text(path)]
    lines = [line for line in raw_lines if line]
    meaningful: list[str] = []
    date_line = ""

    for line in lines[:50]:
        lowered = line.lower()
        if any(lowered.startswith(prefix) for prefix in NOISE_PREFIXES):
            continue
        if "follow the money - platform" in lowered:
            continue
        if re.match(r"^\d+/\d+/\d+", line):
            continue
        if re.match(r"^\d+/\d+,\s*\d+:\d+", line):
            continue
        if re.match(r"^\d+\s+of\s+\d+$", lowered):
            continue
        if re.match(r"^page\s+\d+", lowered):
            continue
        if len(line) < 4:
            continue
        meaningful.append(line)
        date_match = DATE_LINE_RE.search(line)
        if date_match and not date_line:
            date_line = line

    headline = ""
    for idx, line in enumerate(meaningful[:-1]):
        if DATE_LINE_RE.search(meaningful[idx + 1]):
            headline = line
            break
    if not headline:
        for line in meaningful[:10]:
            if DATE_LINE_RE.search(line):
                continue
            headline = line
            break

    published_year = ""
    published_year_source = ""
    if date_line:
        date_match = DATE_LINE_RE.search(date_line)
        if date_match:
            published_year = date_match.group("year")
            published_year_source = "date_line"
    if not published_year:
        published_year = infer_year_from_filesystem(path)
        if published_year:
            published_year_source = "filesystem"

    return headline, normalize_text(headline), published_year, published_year_source


def collect_pdfs(corpus_root: Path) -> list[PdfRecord]:
    records: list[PdfRecord] = []
    for path in sorted(corpus_root.glob("*.pdf")):
        title = path.stem
        headline, normalized_headline, published_year, published_year_source = extract_pdf_metadata(path)
        date_line = ""
        lines = [line.strip() for line in extract_pdf_page_text(path)[:20]]
        for line in lines:
            if DATE_LINE_RE.search(line.strip()):
                date_line = line.strip()
                break
        records.append(
            PdfRecord(
                path=path,
                title=title,
                normalized_title=normalize_text(title),
                token_key=token_key(title),
                headline=headline,
                normalized_headline=normalized_headline,
                published_year=published_year,
                published_year_source=published_year_source,
                date_line=date_line,
            )
        )
    return records


def build_project_record(path: Path, year: str, inventory: object) -> ProjectRecord:
    readme_title, readme_summary, readme_likely_headline, readme_topics = extract_readme_snapshot(path / "README.md")
    readme_quality = "low"
    if readme_title:
        for line in (path / "README.md").read_text(encoding="utf-8").splitlines():
            stripped = line.strip()
            if stripped.startswith("- Readme quality:"):
                match = re.search(r"`([^`]+)`", stripped)
                if match:
                    readme_quality = match.group(1)
                break

    root_entries = sorted(item for item in path.iterdir() if item.is_file() and not item.name.startswith("."))
    root_gdocs = tuple(item.name for item in root_entries if item.suffix.lower() == ".gdoc")
    root_files = tuple(item.name for item in root_entries if item.stem not in SYSTEM_NAMES)

    candidate_labels: list[str] = [path.name.replace("_", " ")]
    candidate_labels.extend(item.stem for item in root_entries if item.stem not in SYSTEM_NAMES)
    if readme_title:
        candidate_labels.append(readme_title)
    if readme_likely_headline:
        candidate_labels.append(readme_likely_headline)
    for gdoc in inventory.gdocs:
        candidate_labels.extend(gdoc.cache_headlines[:3])
    candidate_labels = [label.strip() for label in candidate_labels if label and label.strip()]
    semantic_parts = list(candidate_labels)
    if readme_summary:
        semantic_parts.append(readme_summary)
    semantic_parts.extend(readme_topics)
    semantic_tokens = frozenset(
        token
        for part in semantic_parts
        for token in token_key(part)
    )

    return ProjectRecord(
        year=year,
        slug=path.name,
        path=path,
        readme_path=path / "README.md",
        readme_title=readme_title,
        readme_summary=readme_summary,
        readme_likely_headline=readme_likely_headline,
        readme_topics=readme_topics,
        readme_quality=readme_quality,
        root_gdocs=root_gdocs,
        root_files=root_files,
        candidate_labels=tuple(dict.fromkeys(candidate_labels)),
        semantic_tokens=semantic_tokens,
    )


def collect_projects(project_roots: Iterable[Path]) -> list[ProjectRecord]:
    projects: list[ProjectRecord] = []
    for projects_root in project_roots:
        for year in YEAR_NAMES:
            year_dir = projects_root / year
            if not year_dir.is_dir():
                continue
            for path in sorted(child for child in year_dir.iterdir() if child.is_dir()):
                if path.name in {"old_coding_projects", UNPUBLISHED_DIRNAME, PERSONAL_DIRNAME}:
                    continue
                try:
                    inventory = collect_project_inventory(path)
                except OSError:
                    inventory = SimpleNamespace(gdocs=[])
                projects.append(build_project_record(path, year, inventory))
    return projects


def collect_archived_unpublished_projects(archives_root: Path) -> list[ProjectRecord]:
    projects: list[ProjectRecord] = []
    for year in YEAR_NAMES:
        year_dir = archives_root / year / UNPUBLISHED_DIRNAME
        if not year_dir.is_dir():
            continue
        for path in sorted(child for child in year_dir.iterdir() if child.is_dir()):
            if path.name in NON_PROJECT_DIRNAMES:
                continue
            if not (path / "README.md").exists():
                continue
            try:
                inventory = collect_project_inventory(path)
            except OSError:
                inventory = SimpleNamespace(gdocs=[])
            projects.append(build_project_record(path, year, inventory))
    return projects


def collect_archived_personal_projects(archives_root: Path) -> list[ProjectRecord]:
    projects: list[ProjectRecord] = []
    for year in YEAR_NAMES:
        year_dir = archives_root / year / PERSONAL_DIRNAME
        if not year_dir.is_dir():
            continue
        for path in sorted(child for child in year_dir.iterdir() if child.is_dir()):
            if path.name in NON_PROJECT_DIRNAMES:
                continue
            try:
                inventory = collect_project_inventory(path)
            except OSError:
                inventory = SimpleNamespace(gdocs=[])
            projects.append(build_project_record(path, year, inventory))
    return projects


def collect_note_links(notes_root: Path) -> dict[str, str]:
    mapping: dict[str, str] = {}
    if not notes_root.is_dir():
        return mapping
    pattern = re.compile(r"published pdf:\s*`[^`]*/([^`]+\.pdf)`", re.IGNORECASE)
    for note in sorted(notes_root.glob("*.md")):
        try:
            text = note.read_text(encoding="utf-8")
        except OSError:
            continue
        match = pattern.search(text)
        if not match:
            continue
        mapping[match.group(1)] = str(note)
    return mapping


def top_project_matches(pdf: PdfRecord, projects: Iterable[ProjectRecord], limit: int = 3) -> list[MatchCandidate]:
    candidates: list[MatchCandidate] = []
    pdf_token_sets = [set(pdf.token_key)]
    if pdf.headline:
        pdf_token_sets.append(set(token_key(pdf.headline)))
    for project in projects:
        best_score = 0.0
        best_basis = "none"
        best_label = ""
        for label in project.candidate_labels:
            score, basis = score_candidate(label, pdf)
            if score > best_score:
                best_score = score
                best_basis = basis
                best_label = label

        semantic_score = 0.0
        semantic_basis = "none"
        same_year_or_unknown = not pdf.published_year or pdf.published_year == project.year
        if project.semantic_tokens and project.readme_quality == "high" and same_year_or_unknown:
            for pdf_tokens in pdf_token_sets:
                if not pdf_tokens:
                    continue
                overlap = len(pdf_tokens & project.semantic_tokens)
                recall = overlap / len(pdf_tokens)
                if overlap >= 5 and recall >= 0.75:
                    score = 0.94
                    basis = "semantic_strong"
                elif overlap >= 4 and recall >= 0.6:
                    score = 0.88
                    basis = "semantic_medium"
                elif overlap >= 3 and recall >= 0.45:
                    score = 0.8
                    basis = "semantic_light"
                else:
                    score = 0.0
                    basis = "semantic_none"
                if score > semantic_score:
                    semantic_score = score
                    semantic_basis = basis

        if semantic_score > best_score:
            best_score = semantic_score
            best_basis = semantic_basis
            best_label = project.readme_title or project.slug

        if pdf.published_year:
            if pdf.published_year == project.year:
                best_score = min(1.0, best_score + 0.08)
                best_basis = f"{best_basis}_same_year"
            else:
                best_score = max(0.0, best_score - 0.08)
                best_basis = f"{best_basis}_cross_year"

        if project.readme_quality == "high" and best_basis.startswith("semantic"):
            best_score = min(1.0, best_score + 0.03)
            best_basis = f"{best_basis}_high_readme"

        candidates.append(MatchCandidate(project=project, score=best_score, basis=best_basis, candidate_label=best_label))
    candidates.sort(key=lambda item: (-item.score, item.project.year, item.project.slug))
    return candidates[:limit]


def classify_pdf_match(matches: list[MatchCandidate]) -> tuple[str, MatchCandidate | None]:
    if not matches:
        return "unmatched", None
    best = matches[0]
    second = matches[1] if len(matches) > 1 else None
    if best.score >= 0.99 and ("exact" in best.basis or "semantic_strong" in best.basis):
        return "matched", best
    if best.score >= 0.92:
        if second and second.score >= 0.88 and abs(best.score - second.score) <= 0.03:
            return "multiple_candidates", best
        return "matched", best
    if best.score >= 0.75:
        if second and abs(best.score - second.score) <= 0.05:
            return "multiple_candidates", best
        return "needs_review", best
    return "unmatched", best


def write_csv(path: Path, rows: list[dict[str, object]]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    fieldnames = list(rows[0].keys()) if rows else []
    with path.open("w", encoding="utf-8", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=fieldnames)
        writer.writeheader()
        writer.writerows(rows)


def write_jsonl(path: Path, rows: list[dict[str, object]]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", encoding="utf-8") as handle:
        for row in rows:
            handle.write(json.dumps(row, ensure_ascii=False) + "\n")


def build_review_queue_rows(rows: list[dict[str, object]]) -> list[dict[str, object]]:
    queue_rows: list[dict[str, object]] = []
    for row in rows:
        if row["match_status"] == "matched":
            continue
        queue_rows.append(
            {
                "published_year": row["published_year"],
                "pdf_title": row["pdf_title"],
                "pdf_path": row["pdf_path"],
                "match_status": row["match_status"],
                "current_candidate_slug": row["matched_project_slug"],
                "current_candidate_path": row["matched_project_path"],
                "current_candidate_title": row["matched_project_title"],
                "match_basis": row["match_basis"],
                "match_score": row["match_score"],
                "headline_hint": row["headline"],
                "confirmed_project_slug": "",
                "confirmed_project_path": "",
                "review_notes": "",
            }
        )
    return queue_rows


def build_review_backlog_markdown(rows: list[dict[str, object]]) -> str:
    by_year: dict[str, list[dict[str, object]]] = defaultdict(list)
    for row in rows:
        if row["match_status"] != "matched":
            by_year[str(row["published_year"])].append(row)

    lines = [
        "# Publication Review Backlog",
        "",
        "Generated from `publication_tracker.jsonl`.",
        "",
        "Use `pdf_title` as the canonical published-story label.",
        "Treat `headline` only as a noisy page-1 extraction hint.",
        "",
    ]

    for year in sorted(by_year):
        year_rows = by_year[year]
        counts = Counter(str(row["match_status"]) for row in year_rows)
        lines.append(f"## {year}")
        lines.append(f"- needs_review: {counts.get('needs_review', 0)}")
        lines.append(f"- multiple_candidates: {counts.get('multiple_candidates', 0)}")
        lines.append(f"- unmatched: {counts.get('unmatched', 0)}")
        lines.append("")
        for status in ("needs_review", "multiple_candidates", "unmatched"):
            subset = [row for row in year_rows if row["match_status"] == status]
            if not subset:
                continue
            lines.append(f"### {status}")
            for row in subset:
                lines.append(f"- `{row['pdf_title']}`")
                if row["matched_project_slug"]:
                    lines.append(f"  - current_candidate: `{row['matched_project_slug']}`")
                if row["match_basis"]:
                    lines.append(f"  - match_basis: `{row['match_basis']}`")
                if row["headline"]:
                    lines.append(f"  - headline_hint: `{row['headline']}`")
            lines.append("")
    return "\n".join(lines) + "\n"


def parse_existing_review_worklist(path: Path) -> dict[str, dict[str, str]]:
    if not path.exists():
        return {}
    decisions: dict[str, dict[str, str]] = {}
    current_title = ""
    current_year = ""
    for raw_line in path.read_text(encoding="utf-8").splitlines():
        line = raw_line.rstrip()
        if line.startswith("## "):
            current_year = line.removeprefix("## ").strip()
            continue
        if line.startswith("#### "):
            current_title = line.removeprefix("#### ").strip()
            decisions.setdefault(f"{current_year}::{current_title}", {})
            continue
        if not current_title or not line.startswith("- "):
            continue
        for key in ("year_override", "decision", "confirmed_project_slug", "notes"):
            prefix = f"- {key}:"
            if line.startswith(prefix):
                decisions[f"{current_year}::{current_title}"][key] = line.removeprefix(prefix).strip()
                break
    return decisions


def parse_existing_tracker_reviews(path: Path) -> dict[str, dict[str, str]]:
    if not path.exists():
        return {}
    decisions: dict[str, dict[str, str]] = {}
    try:
        if path.suffix == ".jsonl":
            for line in path.read_text(encoding="utf-8").splitlines():
                if not line.strip():
                    continue
                row = json.loads(line)
                review_decision = str(row.get("review_decision", "")).strip()
                review_confirmed_slug = str(row.get("review_confirmed_project_slug", "")).strip()
                review_notes = str(row.get("review_notes", "")).strip()
                review_year_override = str(row.get("review_year_override", "")).strip()
                if not any((review_decision, review_confirmed_slug, review_notes, review_year_override)):
                    continue
                key = f"{row.get('published_year','')}::{row.get('pdf_title','')}"
                decisions[key] = {
                    "decision": review_decision,
                    "confirmed_project_slug": review_confirmed_slug,
                    "notes": review_notes,
                    "year_override": review_year_override,
                }
    except OSError:
        return {}
    return decisions


def merge_review_maps(*maps: dict[str, dict[str, str]]) -> dict[str, dict[str, str]]:
    merged: dict[str, dict[str, str]] = {}
    for mapping in maps:
        for key, value in mapping.items():
            if key not in merged:
                merged[key] = {}
            for field, field_value in value.items():
                if field_value:
                    merged[key][field] = field_value
    return merged


def lookup_review_entry(existing: dict[str, dict[str, str]], year: str, title: str) -> dict[str, str]:
    direct = existing.get(f"{year}::{title}")
    if direct is not None:
        return direct
    matches = [value for key, value in existing.items() if key.endswith(f"::{title}")]
    if len(matches) == 1:
        return matches[0]
    return {}


def build_review_worklist_markdown(rows: list[dict[str, object]], existing: dict[str, dict[str, str]]) -> str:
    by_year_open: dict[str, list[dict[str, object]]] = defaultdict(list)
    by_year_reviewed: dict[str, list[dict[str, object]]] = defaultdict(list)
    for row in rows:
        year = str(row["published_year"])
        title = str(row["pdf_title"])
        preserved = lookup_review_entry(existing, year, title)
        if row["match_status"] != "matched":
            by_year_open[year].append(row)
        elif preserved.get("decision"):
            by_year_reviewed[year].append(row)

    lines = [
        "# Publication Review Worklist",
        "",
        "Edit this file directly in Obsidian.",
        "",
        "Only edit these three lines per story:",
        "- `year_override:` optional, only fill if the tracker put the PDF in the wrong year",
        "- `decision:` use `confirmed`, `changed`, or `missing`",
        "- `confirmed_project_slug:` fill the correct project slug when needed",
        "- `notes:` optional free text",
        "",
        "Use `pdf_title` as the canonical published-story label.",
        "Treat `headline_hint` only as a noisy page-1 extraction hint.",
        "Use `confirmed` when the current candidate is already the right project.",
        "Use `changed` when the current candidate is wrong but you know the correct project slug.",
        "Use `missing` when there is no usable project folder yet.",
        "",
    ]

    status_order = ("needs_review", "multiple_candidates", "unmatched")
    all_years = sorted(set(by_year_open) | set(by_year_reviewed))
    for year in all_years:
        year_rows = by_year_open.get(year, [])
        reviewed_rows = by_year_reviewed.get(year, [])
        counts = Counter(str(row["match_status"]) for row in year_rows)
        lines.append(f"## {year}")
        lines.append(f"- needs_review: {counts.get('needs_review', 0)}")
        lines.append(f"- multiple_candidates: {counts.get('multiple_candidates', 0)}")
        lines.append(f"- unmatched: {counts.get('unmatched', 0)}")
        lines.append(f"- reviewed: {len(reviewed_rows)}")
        lines.append("")
        for status in status_order:
            subset = [row for row in year_rows if row["match_status"] == status]
            if not subset:
                continue
            lines.append(f"### {status}")
            for row in subset:
                title = str(row["pdf_title"])
                preserved = lookup_review_entry(existing, year, title)
                year_override = preserved.get("year_override", "")
                decision = preserved.get("decision", "")
                confirmed_project_slug = preserved.get("confirmed_project_slug", "")
                notes = preserved.get("notes", "")
                lines.extend(
                    [
                        f"#### {title}",
                        f"- current_candidate_slug: `{row['matched_project_slug']}`" if row["matched_project_slug"] else "- current_candidate_slug:",
                        f"- current_candidate_path: `{row['matched_project_path']}`" if row["matched_project_path"] else "- current_candidate_path:",
                        f"- match_basis: `{row['match_basis']}`" if row["match_basis"] else "- match_basis:",
                        f"- headline_hint: `{row['headline']}`" if row["headline"] else "- headline_hint:",
                        f"- pdf_path: `{row['pdf_path']}`",
                        f"- year_override: {year_override}",
                        f"- decision: {decision}",
                        f"- confirmed_project_slug: {confirmed_project_slug}",
                        f"- notes: {notes}",
                        "",
                    ]
                )
            lines.append("")
        if reviewed_rows:
            lines.append("### reviewed")
            for row in reviewed_rows:
                title = str(row["pdf_title"])
                preserved = lookup_review_entry(existing, year, title)
                year_override = preserved.get("year_override", "")
                decision = preserved.get("decision", "")
                confirmed_project_slug = preserved.get("confirmed_project_slug", "")
                notes = preserved.get("notes", "")
                lines.extend(
                    [
                        f"#### {title}",
                        f"- current_candidate_slug: `{row['matched_project_slug']}`" if row["matched_project_slug"] else "- current_candidate_slug:",
                        f"- current_candidate_path: `{row['matched_project_path']}`" if row["matched_project_path"] else "- current_candidate_path:",
                        f"- match_basis: `{row['match_basis']}`" if row["match_basis"] else "- match_basis:",
                        f"- headline_hint: `{row['headline']}`" if row["headline"] else "- headline_hint:",
                        f"- pdf_path: `{row['pdf_path']}`",
                        f"- year_override: {year_override}",
                        f"- decision: {decision}",
                        f"- confirmed_project_slug: {confirmed_project_slug}",
                        f"- notes: {notes}",
                        "",
                    ]
                )
            lines.append("")
    return "\n".join(lines) + "\n"


def clean_review_slug(value: str) -> str:
    cleaned = value.strip().strip("`").strip()
    return cleaned


def canonicalize_review_decision(value: str) -> str:
    cleaned = value.strip().lower()
    aliases = {
        "confirmed": "confirmed",
        "changed": "changed",
        "missing": "missing",
        "changed_project_slug": "changed",
        "project_created": "changed",
        "missing_project_directory": "missing",
        "no_project_yet": "missing",
        "wrong_year": "changed",
        "not_this_project": "changed",
        "skip": "skip",
    }
    return aliases.get(cleaned, cleaned)


def build_project_indexes(
    projects: list[ProjectRecord],
) -> tuple[
    dict[str, ProjectRecord],
    dict[tuple[str, str], ProjectRecord],
    dict[str, ProjectRecord],
    dict[tuple[str, str], ProjectRecord],
]:
    by_slug: dict[str, ProjectRecord] = {}
    by_year_slug: dict[tuple[str, str], ProjectRecord] = {}
    by_normalized_slug: dict[str, ProjectRecord] = {}
    by_year_normalized_slug: dict[tuple[str, str], ProjectRecord] = {}
    for project in projects:
        by_year_slug[(project.year, project.slug)] = project
        by_slug.setdefault(project.slug, project)
        normalized_slug = normalize_text(project.slug)
        if normalized_slug:
            by_year_normalized_slug[(project.year, normalized_slug)] = project
            by_normalized_slug.setdefault(normalized_slug, project)
    return by_slug, by_year_slug, by_normalized_slug, by_year_normalized_slug


def apply_review_decision(
    row: dict[str, object],
    decision_map: dict[str, dict[str, str]],
    projects_by_slug: dict[str, ProjectRecord],
    projects_by_year_slug: dict[tuple[str, str], ProjectRecord],
    projects_by_normalized_slug: dict[str, ProjectRecord],
    projects_by_year_normalized_slug: dict[tuple[str, str], ProjectRecord],
) -> tuple[dict[str, object], ProjectRecord | None]:
    year = str(row["published_year"])
    title = str(row["pdf_title"])
    review = lookup_review_entry(decision_map, year, title)
    decision = canonicalize_review_decision(review.get("decision", ""))
    confirmed_slug = clean_review_slug(review.get("confirmed_project_slug", ""))
    notes = review.get("notes", "").strip()
    year_override = review.get("year_override", "").strip()

    if year_override in YEAR_NAMES:
        row["published_year"] = year_override
        row["published_year_source"] = "manual_override"
        year = year_override

    row["review_decision"] = decision
    row["review_notes"] = notes
    row["review_confirmed_project_slug"] = confirmed_slug
    row["review_year_override"] = year_override

    if decision == "missing":
        row["match_status"] = "unmatched"
        row["match_basis"] = "manual_missing"
        return row, None

    if decision == "confirmed" and not confirmed_slug:
        if row.get("matched_project_slug"):
            confirmed_slug = str(row["matched_project_slug"])
        else:
            return row, None

    if decision not in {"confirmed", "changed"} or not confirmed_slug:
        return row, None

    normalized_confirmed_slug = normalize_text(confirmed_slug)
    project = (
        projects_by_year_slug.get((year, confirmed_slug))
        or projects_by_slug.get(confirmed_slug)
        or projects_by_year_normalized_slug.get((year, normalized_confirmed_slug))
        or projects_by_normalized_slug.get(normalized_confirmed_slug)
    )
    if not project:
        row["review_decision"] = f"{decision}_missing_project"
        return row, None

    row["match_status"] = "matched"
    row["matched_project_year"] = project.year
    row["matched_project_slug"] = project.slug
    row["matched_project_path"] = str(project.path)
    row["matched_project_readme"] = str(project.readme_path)
    row["matched_project_title"] = project.readme_title
    row["match_score"] = 1.0
    row["match_basis"] = f"manual_{decision}"
    row["match_candidate"] = project.readme_title or project.slug
    return row, project


def main() -> None:
    review_worklist_path = INDEX_ROOT / "publication_review_worklist.md"
    tracker_jsonl_path = INDEX_ROOT / "publication_tracker.jsonl"
    existing_review_worklist = parse_existing_review_worklist(review_worklist_path)
    existing_tracker_reviews = parse_existing_tracker_reviews(tracker_jsonl_path)
    effective_review_map = merge_review_maps(existing_tracker_reviews, existing_review_worklist)

    official_pdfs = collect_pdfs(OFFICIAL_CORPUS_ROOT)
    legacy_pdfs = collect_pdfs(LEGACY_CORPUS_ROOT)
    projects = collect_projects(PROJECT_ROOTS)
    archived_unpublished_projects = collect_archived_unpublished_projects(ARCHIVES_ROOT)
    archived_personal_projects = collect_archived_personal_projects(ARCHIVES_ROOT)
    (
        projects_by_slug,
        projects_by_year_slug,
        projects_by_normalized_slug,
        projects_by_year_normalized_slug,
    ) = build_project_indexes(projects)
    note_links = collect_note_links(OFFICIAL_CORPUS_ROOT / "notes")
    legacy_names = {pdf.path.name for pdf in legacy_pdfs}

    pdf_rows: list[dict[str, object]] = []
    project_to_pdfs: defaultdict[str, list[PdfRecord]] = defaultdict(list)

    for pdf in official_pdfs:
        matches = top_project_matches(pdf, projects, limit=3)
        match_status, best = classify_pdf_match(matches)
        article_note_path = note_links.get(pdf.path.name, "")

        top_1 = matches[0] if len(matches) > 0 else None
        top_2 = matches[1] if len(matches) > 1 else None
        top_3 = matches[2] if len(matches) > 2 else None

        row = {
                "pdf_title": pdf.title,
                "pdf_path": str(pdf.path),
                "published_year": pdf.published_year,
                "published_year_source": pdf.published_year_source,
                "date_line": pdf.date_line,
                "headline": pdf.headline,
                "article_note_path": article_note_path,
                "match_status": match_status,
                "matched_project_year": best.project.year if best else "",
                "matched_project_slug": best.project.slug if best else "",
                "matched_project_path": str(best.project.path) if best else "",
                "matched_project_readme": str(best.project.readme_path) if best else "",
                "matched_project_title": best.project.readme_title if best else "",
                "match_score": round(best.score, 4) if best else 0.0,
                "match_basis": best.basis if best else "",
                "match_candidate": best.candidate_label if best else "",
                "candidate_2_slug": top_2.project.slug if top_2 else "",
                "candidate_2_score": round(top_2.score, 4) if top_2 else 0.0,
                "candidate_3_slug": top_3.project.slug if top_3 else "",
                "candidate_3_score": round(top_3.score, 4) if top_3 else 0.0,
                "exists_in_legacy_corpus": "yes" if pdf.path.name in legacy_names else "no",
                "review_decision": "",
                "review_confirmed_project_slug": "",
                "review_notes": "",
            }
        row, reviewed_project = apply_review_decision(
            row,
            effective_review_map,
            projects_by_slug,
            projects_by_year_slug,
            projects_by_normalized_slug,
            projects_by_year_normalized_slug,
        )
        if row["match_status"] == "matched":
            matched_project = reviewed_project or (best.project if best else None)
            if matched_project:
                project_to_pdfs[str(matched_project.path)].append(pdf)

        pdf_rows.append(row)

    project_rows: list[dict[str, object]] = []
    for project in projects:
        matched_pdfs = sorted(project_to_pdfs.get(str(project.path), []), key=lambda item: (item.published_year, item.title))
        project_rows.append(
            {
                "project_year": project.year,
                "project_slug": project.slug,
                "project_path": str(project.path),
                "readme_path": str(project.readme_path),
                "readme_title": project.readme_title,
                "readme_quality": project.readme_quality,
                "matched_pdf_count": len(matched_pdfs),
                "matched_pdf_titles": " | ".join(pdf.title for pdf in matched_pdfs),
                "published_status_from_pdfs": "published" if matched_pdfs else "no_linked_pdf",
            }
        )

    archived_unpublished_rows = [
        {
            "project_year": project.year,
            "project_slug": project.slug,
            "project_path": str(project.path),
            "readme_path": str(project.readme_path),
            "readme_title": project.readme_title,
            "readme_quality": project.readme_quality,
            "archive_status": "archived_unpublished",
        }
        for project in archived_unpublished_projects
    ]
    archived_personal_rows = [
        {
            "project_year": project.year,
            "project_slug": project.slug,
            "project_path": str(project.path),
            "readme_path": str(project.readme_path),
            "readme_title": project.readme_title,
            "readme_quality": project.readme_quality,
            "archive_status": "archived_personal",
        }
        for project in archived_personal_projects
    ]

    year_summary_rows: list[dict[str, object]] = []
    by_year: defaultdict[str, Counter[str]] = defaultdict(Counter)
    for row in pdf_rows:
        year = str(row["published_year"] or "unknown")
        by_year[year]["pdf_count"] += 1
        by_year[year][str(row["match_status"])] += 1

    for year in sorted(by_year):
        counters = by_year[year]
        year_summary_rows.append(
            {
                "published_year": year,
                "pdf_count": counters["pdf_count"],
                "matched_count": counters["matched"],
                "needs_review_count": counters["needs_review"],
                "multiple_candidates_count": counters["multiple_candidates"],
                "unmatched_count": counters["unmatched"],
            }
        )

    project_year_rows: list[dict[str, object]] = []
    by_project_year: defaultdict[str, Counter[str]] = defaultdict(Counter)
    for row in project_rows:
        by_project_year[str(row["project_year"])][str(row["published_status_from_pdfs"])] += 1
        if int(row["matched_pdf_count"]):
            by_project_year[str(row["project_year"])]["matched_pdf_count"] += int(row["matched_pdf_count"])
        if str(row["readme_quality"]):
            by_project_year[str(row["project_year"])][f"readme_{row['readme_quality']}"] += 1

    for year in sorted(by_project_year):
        counters = by_project_year[year]
        project_year_rows.append(
            {
                "project_year": year,
                "project_count": sum(counters[key] for key in counters if key.startswith("readme_")),
                "projects_with_linked_pdf": counters["published"],
                "projects_without_linked_pdf": counters["no_linked_pdf"],
                "linked_pdf_total": counters["matched_pdf_count"],
                "readme_high": counters["readme_high"],
                "readme_partial": counters["readme_partial"],
                "readme_low": counters["readme_low"],
            }
        )

    unmatched_rows = [row for row in pdf_rows if row["match_status"] != "matched"]
    review_queue_rows = build_review_queue_rows(pdf_rows)
    INDEX_ROOT.mkdir(parents=True, exist_ok=True)
    REPORTS_ROOT.mkdir(parents=True, exist_ok=True)

    write_csv(INDEX_ROOT / "publication_tracker.csv", pdf_rows)
    write_jsonl(INDEX_ROOT / "publication_tracker.jsonl", pdf_rows)
    write_csv(INDEX_ROOT / "project_publication_coverage.csv", project_rows)
    write_csv(INDEX_ROOT / "archived_unpublished_projects.csv", archived_unpublished_rows)
    write_csv(INDEX_ROOT / "archived_personal_projects.csv", archived_personal_rows)
    write_csv(INDEX_ROOT / "publication_year_summary.csv", year_summary_rows)
    write_csv(INDEX_ROOT / "project_year_summary.csv", project_year_rows)
    write_csv(INDEX_ROOT / "official_corpus_pdfs_needing_review.csv", unmatched_rows)
    write_csv(INDEX_ROOT / "publication_review_queue.csv", review_queue_rows)
    (INDEX_ROOT / "publication_review_backlog.md").write_text(
        build_review_backlog_markdown(pdf_rows),
        encoding="utf-8",
    )
    review_worklist_path.write_text(
        build_review_worklist_markdown(pdf_rows, effective_review_map),
        encoding="utf-8",
    )

    summary = {
        "official_corpus_pdf_count": len(official_pdfs),
        "legacy_corpus_pdf_count": len(legacy_pdfs),
        "project_count": len(projects),
        "pdf_status_counts": dict(Counter(str(row["match_status"]) for row in pdf_rows)),
        "publication_year_counts": {row["published_year"]: row["pdf_count"] for row in year_summary_rows},
        "projects_with_linked_pdf_count": sum(1 for row in project_rows if row["published_status_from_pdfs"] == "published"),
        "archived_unpublished_project_count": len(archived_unpublished_rows),
        "archived_personal_project_count": len(archived_personal_rows),
    }
    (INDEX_ROOT / "publication_audit_summary.json").write_text(
        json.dumps(summary, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )

    report_lines = [
        "# publication_audit_latest",
        "",
        f"- Official corpus: `{OFFICIAL_CORPUS_ROOT}`",
        f"- Legacy source corpus: `{LEGACY_CORPUS_ROOT}`",
        f"- Project roots: `{', '.join(str(root) for root in PROJECT_ROOTS)}`",
        f"- Official corpus PDFs: `{len(official_pdfs)}`",
        f"- Legacy corpus PDFs: `{len(legacy_pdfs)}`",
        f"- Project folders scanned: `{len(projects)}`",
        f"- Archived unpublished folders tracked separately: `{len(archived_unpublished_rows)}`",
        f"- Archived personal/tooling folders tracked separately: `{len(archived_personal_rows)}`",
        "",
        "## Published PDFs By Year",
        "",
    ]

    for row in year_summary_rows:
        report_lines.append(
            f"- `{row['published_year']}`: `{row['pdf_count']}` PDFs, `{row['matched_count']}` matched, "
            f"`{row['needs_review_count']}` need review, `{row['multiple_candidates_count']}` multiple candidates, "
            f"`{row['unmatched_count']}` unmatched"
        )

    report_lines.extend(["", "## Project Coverage By Year", ""])
    for row in project_year_rows:
        report_lines.append(
            f"- `{row['project_year']}`: `{row['projects_with_linked_pdf']}` projects linked to PDFs, "
            f"`{row['projects_without_linked_pdf']}` without linked PDF, READMEs `{row['readme_high']}` high / "
            f"`{row['readme_partial']}` partial / `{row['readme_low']}` low"
        )

    report_lines.extend(["", "## PDFs Needing Review", ""])
    for row in unmatched_rows[:20]:
        report_lines.append(
            f"- `{row['pdf_title']}` → `{row['matched_project_slug']}` "
            f"(status `{row['match_status']}`, score `{row['match_score']}`)"
        )

    report_lines.extend(
        [
            "",
            "## Output Files",
            "",
            f"- PDF-first tracker CSV: `{INDEX_ROOT / 'publication_tracker.csv'}`",
            f"- Project coverage CSV: `{INDEX_ROOT / 'project_publication_coverage.csv'}`",
            f"- Publication year summary CSV: `{INDEX_ROOT / 'publication_year_summary.csv'}`",
            f"- Project year summary CSV: `{INDEX_ROOT / 'project_year_summary.csv'}`",
            f"- Review CSV: `{INDEX_ROOT / 'official_corpus_pdfs_needing_review.csv'}`",
            f"- Review queue CSV: `{INDEX_ROOT / 'publication_review_queue.csv'}`",
            f"- Review backlog MD: `{INDEX_ROOT / 'publication_review_backlog.md'}`",
            f"- Editable review worklist MD: `{INDEX_ROOT / 'publication_review_worklist.md'}`",
        ]
    )
    (REPORTS_ROOT / "publication_audit_latest.md").write_text("\n".join(report_lines) + "\n", encoding="utf-8")


if __name__ == "__main__":
    main()
