#!/usr/bin/env python3
from __future__ import annotations

import argparse
import csv
import re
import subprocess
import tempfile
import unicodedata
from pathlib import Path


WORKSPACE_ROOT = Path.cwd().resolve()
INDEX_ROOT = WORKSPACE_ROOT / "Resources" / "knowledge_ops" / "index"
TRACKER_PATH = INDEX_ROOT / "publication_tracker.csv"
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
}
PDF_SUFFIX_RE = re.compile(
    r"\s*-\s*follow the money\s*-\s*platform\s*(voor onderzoeksjournalistiek|for investigative journalism)\s*$",
    re.IGNORECASE,
)
DATE_LINE_RE = re.compile(r"^\d{1,2}\s+[A-ZÀ-Ý]{3,}\s+20\d{2}")
PAGE_COUNTER_RE = re.compile(r"^\d+\s+of\s+\d+\b", re.IGNORECASE)
TIMESTAMP_RE = re.compile(r"\b\d{2}/\d{2}/\d{4},\s*\d{2}:\d{2}\b")


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Create local project-level published PDF text caches from the canonical publication corpus."
    )
    parser.add_argument("--tracker-path", type=Path, default=TRACKER_PATH)
    parser.add_argument("--overwrite", action="store_true")
    return parser.parse_args()


def sanitize_filename(text: str) -> str:
    normalized = unicodedata.normalize("NFKD", text)
    without_accents = "".join(ch for ch in normalized if not unicodedata.combining(ch))
    lowered = without_accents.lower()
    lowered = re.sub(r"[^a-z0-9]+", "_", lowered).strip("_")
    return lowered or "untitled"


def normalize_title(text: str) -> str:
    stem = text.removesuffix(".pdf")
    stem = unicodedata.normalize("NFKD", stem)
    stem = "".join(ch for ch in stem if not unicodedata.combining(ch))
    stem = PDF_SUFFIX_RE.sub("", stem)
    stem = stem.replace("_", " ")
    stem = re.sub(r"\s+", " ", stem).strip()
    return stem


def extract_pdf_text(pdf_path: Path, first_page_only: bool = False) -> list[str]:
    with tempfile.NamedTemporaryFile(suffix=".txt") as tmp:
        command = ["pdftotext", "-layout", "-nopgbrk"]
        if first_page_only:
            command.extend(["-f", "1", "-l", "1"])
        command.extend([str(pdf_path), tmp.name])
        subprocess.run(command, check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        return tmp.read().decode("utf-8", errors="ignore").splitlines()


def clean_lines(lines: list[str]) -> list[str]:
    cleaned: list[str] = []
    for raw in lines:
        line = raw.strip()
        if not line:
            cleaned.append("")
            continue
        if PAGE_COUNTER_RE.match(line):
            continue
        if TIMESTAMP_RE.search(line):
            continue
        if "ftm.nl/artikelen/" in line.lower():
            continue
        if line.lower().startswith(("http://", "https://")):
            continue
        if DATE_LINE_RE.match(line):
            continue
        if line.lower().startswith(("follow the money", "platform voor onderzoeksjournalistiek", "platform for investigative journalism")):
            continue
        cleaned.append(line)
    return cleaned


def first_paragraph(lines: list[str]) -> str:
    paragraph: list[str] = []
    for line in lines:
        if not line:
            if paragraph:
                text = " ".join(paragraph).strip()
                if len(text) > 80:
                    return text
                paragraph = []
            continue
        paragraph.append(line)
    text = " ".join(paragraph).strip()
    return text if len(text) > 80 else ""


def derive_tags(title: str, limit: int = 6) -> list[str]:
    normalized = normalize_title(title).lower()
    tokens = [
        token
        for token in re.split(r"[^a-z0-9]+", normalized)
        if token and token not in GENERIC_TOKENS and len(token) > 2
    ]
    tags: list[str] = []
    for token in tokens:
        human = token.capitalize()
        if human not in tags:
            tags.append(human)
        if len(tags) >= limit:
            break
    return tags


def build_markdown(row: dict[str, str]) -> str:
    pdf_title = row["pdf_title"]
    pdf_path = Path(row["pdf_path"])
    headline = normalize_title(pdf_title)
    first_page = clean_lines(extract_pdf_text(pdf_path, first_page_only=True))
    full_text_lines = clean_lines(extract_pdf_text(pdf_path, first_page_only=False))
    lead = first_paragraph(first_page) or first_paragraph(full_text_lines)
    summary = lead
    tags = derive_tags(pdf_title)
    body_text = "\n".join(line for line in full_text_lines if line).strip()
    lines = [
        "---",
        f"pdf_title: {pdf_title}",
        f"pdf_path: {pdf_path}",
        f"published_year: {row.get('published_year', '')}",
        f"generated_on: {__import__('datetime').date.today().isoformat()}",
        "source: published_pdf",
        "---",
        "",
        "[Headline]",
        headline,
        "",
    ]
    if lead:
        lines.extend(["[Lead]", lead, ""])
    if tags:
        lines.extend(["[Tags]", ", ".join(tags), ""])
    if summary:
        lines.extend(["[Summary]", summary, ""])
    if body_text:
        lines.extend(["[Body]", body_text, ""])
    return "\n".join(lines).rstrip() + "\n"


def main() -> None:
    args = parse_args()
    with args.tracker_path.open(encoding="utf-8", newline="") as handle:
        rows = list(csv.DictReader(handle))

    processed = 0
    for row in rows:
        if row.get("match_status") != "matched":
            continue
        project_path = Path(row["matched_project_path"])
        if not project_path.exists():
            continue
        target_dir = project_path / "docs" / "_derived" / "published_pdf_text"
        target_dir.mkdir(parents=True, exist_ok=True)
        target_path = target_dir / f"{sanitize_filename(row['pdf_title'])}.md"
        if target_path.exists() and not args.overwrite:
            continue
        target_path.write_text(build_markdown(row), encoding="utf-8")
        processed += 1

    print(f"processed={processed}")


if __name__ == "__main__":
    main()
