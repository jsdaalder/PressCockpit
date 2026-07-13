#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import re
import unicodedata
from dataclasses import dataclass
from datetime import date
from pathlib import Path
from urllib.parse import urlparse


SYSTEM_FILES = {".DS_Store"}
DERIVED_PARTS = {"_derived", "google_docs"}
README_FRONTMATTER_KEYS = ("type", "project", "status", "owner", "started", "topics", "entities", "deliverable")
SECTION_LABEL_RE = re.compile(r"^\[(.+?)\]\s*$")
LIST_ITEM_RE = re.compile(r"^\d+\.\s+")
SPECIAL_LABELS = {
    "ddos": "DDoS",
    "co2": "CO2",
}
LOW_SIGNAL_MARKERS = ("lorem ipsum", "asdf")


@dataclass(frozen=True)
class GDocPointer:
    path: Path
    title: str
    doc_id: str
    resource_key: str
    email: str
    url: str
    cache_path: Path
    cache_exists: bool
    cache_mode: str
    cache_counts_for_sweep: bool
    cache_has_body: bool
    cache_summary: str
    cache_lead: str
    cache_topics: tuple[str, ...]
    cache_headlines: tuple[str, ...]


@dataclass(frozen=True)
class ProjectInventory:
    project_root: Path
    readme_path: Path
    derived_root: Path
    manifest_path: Path
    gdocs: tuple[GDocPointer, ...]
    publication_artifacts: tuple["PublicationArtifact", ...]
    root_files: tuple[Path, ...]
    docs_files: tuple[Path, ...]
    other_files: tuple[Path, ...]
    extension_counts: dict[str, int]


@dataclass(frozen=True)
class PublicationArtifact:
    path: Path
    pdf_title: str
    pdf_path: str
    published_year: str
    headline: str
    lead: str
    summary: str
    topics: tuple[str, ...]


def sanitize_filename(text: str) -> str:
    normalized = unicodedata.normalize("NFKD", text)
    without_accents = "".join(ch for ch in normalized if not unicodedata.combining(ch))
    lowered = without_accents.lower()
    lowered = re.sub(r"[^a-z0-9]+", "_", lowered).strip("_")
    return lowered or "untitled"


def humanize_slug(slug: str) -> str:
    return slug.replace("_", " ").strip().title()


def humanize_label(text: str) -> str:
    parts = [part for part in re.split(r"[_\-\s]+", text) if part]
    words: list[str] = []
    for part in parts:
        lowered = part.lower()
        if lowered in SPECIAL_LABELS:
            words.append(SPECIAL_LABELS[lowered])
            continue
        if part.isupper():
            words.append(part)
        elif part.upper() in {"ADR", "RVO", "FTM", "NVWA", "CO2", "EU"}:
            words.append(part.upper())
        else:
            words.append(part.capitalize())
    return " ".join(words)


def normalize_topic_label(value: str) -> str:
    cleaned = value.strip(" -*")
    if not cleaned:
        return ""
    parsed = urlparse(cleaned)
    if parsed.scheme in {"http", "https"} and parsed.netloc:
        segments = [segment for segment in parsed.path.split("/") if segment]
        if segments:
            cleaned = segments[-1]
    cleaned = cleaned.replace("%20", " ")
    cleaned = re.sub(r"\[[^\]]+\]", "", cleaned).strip()
    if not cleaned:
        return ""
    return humanize_label(cleaned)


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


def split_paragraphs(text: str) -> list[str]:
    paragraphs: list[str] = []
    current: list[str] = []
    for raw_line in text.splitlines():
        line = raw_line.strip()
        if not line:
            if current:
                paragraphs.append(" ".join(current).strip())
                current = []
            continue
        current.append(line)
    if current:
        paragraphs.append(" ".join(current).strip())
    return paragraphs


def is_low_signal_text(text: str) -> bool:
    normalized = re.sub(r"\s+", " ", text).strip().lower()
    if not normalized:
        return True
    if any(marker in normalized for marker in LOW_SIGNAL_MARKERS):
        return True
    if len(normalized) < 40:
        return True
    return False


def parse_labeled_sections(text: str) -> dict[str, list[str]]:
    sections: dict[str, list[str]] = {}
    current_label: str | None = None
    for raw_line in text.splitlines():
        line = raw_line.strip()
        label_match = SECTION_LABEL_RE.match(line)
        if label_match:
            current_label = label_match.group(1).strip().lower()
            sections.setdefault(current_label, [])
            continue
        if current_label is None:
            continue
        sections[current_label].append(raw_line)
    return sections


def clean_section_text(lines: list[str]) -> str:
    text = "\n".join(lines).strip()
    return re.sub(r"\n{3,}", "\n\n", text)


def extract_summary_from_cache(text: str) -> tuple[str, str, tuple[str, ...], tuple[str, ...]]:
    _, body = parse_frontmatter(text)
    sections = parse_labeled_sections(body)

    lead = clean_section_text(sections.get("lead", []))
    dossier = clean_section_text(sections.get("dossier", []))
    tags = clean_section_text(sections.get("tags", []))

    summary = lead
    if not summary:
        paragraphs = [
            paragraph
            for paragraph in split_paragraphs(body)
            if len(paragraph) > 80 and not paragraph.lower().startswith(("tab ", "http://", "https://"))
        ]
        summary = paragraphs[0] if paragraphs else ""

    topic_values: list[str] = []
    for blob in (dossier, tags):
        if not blob:
            continue
        for part in re.split(r"[,;]\s*", blob):
            cleaned = normalize_topic_label(part)
            if cleaned:
                topic_values.append(cleaned)
    topics = tuple(dict.fromkeys(topic_values))

    headline_values: list[str] = []
    kop_blob = clean_section_text(sections.get("kop", []))
    if kop_blob:
        for line in kop_blob.splitlines():
            cleaned = re.sub(r"\[[^\]]+\]", "", line).strip()
            if cleaned:
                headline_values.append(cleaned)
    headline_blob = clean_section_text(sections.get("kopsuggesties", []))
    if headline_blob:
        for line in headline_blob.splitlines():
            cleaned = LIST_ITEM_RE.sub("", line).strip()
            cleaned = re.sub(r"\[[^\]]+\]", "", cleaned).strip()
            if cleaned:
                headline_values.append(cleaned)
    headlines = tuple(dict.fromkeys(headline_values[:8]))
    return summary, lead, topics, headlines


def parse_gdoc_pointer(path: Path, cache_root: Path) -> GDocPointer:
    data = json.loads(path.read_text(encoding="utf-8"))
    doc_id = data.get("doc_id", "").strip()
    resource_key = data.get("resource_key", "").strip()
    email = data.get("email", "").strip()
    url = f"https://docs.google.com/document/d/{doc_id}/edit" if doc_id else ""
    cache_path = cache_root / f"{sanitize_filename(path.stem)}.md"
    cache_exists = cache_path.exists()
    cache_text = cache_path.read_text(encoding="utf-8") if cache_exists else ""
    cache_metadata, cache_body = parse_frontmatter(cache_text)
    cache_body_stripped = cache_body.strip()
    cache_mode = cache_metadata.get("cache_mode", "").strip().lower()
    if not cache_mode:
        if not cache_exists:
            cache_mode = "missing"
        elif "Replace this placeholder with fetched Google Doc content." in cache_body_stripped:
            cache_mode = "placeholder"
        elif cache_body_stripped:
            cache_mode = "fetched_body"
        else:
            cache_mode = "placeholder"
    cache_has_body = cache_mode in {"fetched_body", "structured_summary"}
    cache_counts_for_sweep = cache_mode in {"fetched_body", "structured_summary", "title_stub"}
    cache_summary, cache_lead, cache_topics, cache_headlines = extract_summary_from_cache(cache_text) if cache_exists else ("", "", (), ())
    return GDocPointer(
        path=path,
        title=path.stem,
        doc_id=doc_id,
        resource_key=resource_key,
        email=email,
        url=url,
        cache_path=cache_path,
        cache_exists=cache_exists,
        cache_mode=cache_mode,
        cache_counts_for_sweep=cache_counts_for_sweep,
        cache_has_body=cache_has_body,
        cache_summary=cache_summary,
        cache_lead=cache_lead,
        cache_topics=cache_topics,
        cache_headlines=cache_headlines,
    )


def parse_publication_artifact(path: Path) -> PublicationArtifact:
    metadata, body = parse_frontmatter(path.read_text(encoding="utf-8"))
    sections = parse_labeled_sections(body)
    headline = clean_section_text(sections.get("headline", []))
    lead = clean_section_text(sections.get("lead", []))
    summary = clean_section_text(sections.get("summary", []))
    tags_blob = clean_section_text(sections.get("tags", []))
    topics = tuple(
        dict.fromkeys(
            cleaned
            for part in re.split(r"[,;]\s*", tags_blob)
            if (cleaned := normalize_topic_label(part))
        )
    )
    return PublicationArtifact(
        path=path,
        pdf_title=metadata.get("pdf_title", path.stem),
        pdf_path=metadata.get("pdf_path", ""),
        published_year=metadata.get("published_year", ""),
        headline=headline,
        lead=lead,
        summary=summary,
        topics=topics,
    )


def collect_project_inventory(project_root: Path) -> ProjectInventory:
    readme_path = project_root / "README.md"
    derived_root = project_root / "docs" / "_derived"
    cache_root = derived_root / "google_docs"
    manifest_path = derived_root / "google_docs_manifest.json"
    cache_root.mkdir(parents=True, exist_ok=True)

    root_files = tuple(
        sorted(
            [
                path
                for path in project_root.iterdir()
                if path.is_file() and path.name not in SYSTEM_FILES and path.name != "README.md"
            ],
            key=lambda item: item.name.lower(),
        )
    )
    gdocs = tuple(parse_gdoc_pointer(path, cache_root) for path in root_files if path.suffix.lower() == ".gdoc")
    published_pdf_root = derived_root / "published_pdf_text"
    publication_artifacts = tuple(
        parse_publication_artifact(path)
        for path in sorted(published_pdf_root.glob("*.md"), key=lambda item: item.name.lower())
    )

    docs_files: list[Path] = []
    other_files: list[Path] = []
    extension_counts: dict[str, int] = {}
    for path in sorted(project_root.rglob("*")):
        if not path.is_file():
            continue
        if path.name in SYSTEM_FILES or path == readme_path:
            continue
        if any(part in DERIVED_PARTS for part in path.parts):
            continue
        rel = path.relative_to(project_root)
        extension = path.suffix.lower() or "[no_ext]"
        extension_counts[extension] = extension_counts.get(extension, 0) + 1
        if rel.parts and rel.parts[0] == "docs":
            docs_files.append(path)
        elif path not in root_files:
            other_files.append(path)

    return ProjectInventory(
        project_root=project_root,
        readme_path=readme_path,
        derived_root=derived_root,
        manifest_path=manifest_path,
        gdocs=gdocs,
        publication_artifacts=publication_artifacts,
        root_files=root_files,
        docs_files=tuple(docs_files),
        other_files=tuple(other_files),
        extension_counts=extension_counts,
    )


def ensure_cache_placeholders(inventory: ProjectInventory) -> None:
    for gdoc in inventory.gdocs:
        if gdoc.cache_exists:
            continue
        placeholder = (
            "---\n"
            f"title: {gdoc.title}\n"
            f"doc_id: {gdoc.doc_id}\n"
            f"doc_url: {gdoc.url}\n"
            f"email: {gdoc.email}\n"
            f"cached_on: {date.today().isoformat()}\n"
            "source: google_doc_pointer\n"
            "cache_mode: placeholder\n"
            "---\n\n"
            "<!-- Replace this placeholder with fetched Google Doc content. -->\n"
        )
        gdoc.cache_path.write_text(placeholder, encoding="utf-8")


def write_manifest(inventory: ProjectInventory) -> None:
    rows = []
    for gdoc in inventory.gdocs:
        rows.append(
            {
                "title": gdoc.title,
                "pointer_path": str(gdoc.path),
                "doc_id": gdoc.doc_id,
                "doc_url": gdoc.url,
                "cache_path": str(gdoc.cache_path),
                "cache_exists": gdoc.cache_exists,
                "cache_mode": gdoc.cache_mode,
                "cache_counts_for_sweep": gdoc.cache_counts_for_sweep,
                "cache_has_body": gdoc.cache_has_body,
            }
        )
    inventory.manifest_path.parent.mkdir(parents=True, exist_ok=True)
    inventory.manifest_path.write_text(json.dumps(rows, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


def sample_paths(paths: tuple[Path, ...], project_root: Path, limit: int = 8) -> list[str]:
    return [str(path.relative_to(project_root)) for path in paths[:limit]]


def clean_gdoc_title(title: str) -> str:
    cleaned = title.strip()
    cleaned = re.sub(r"^Copy of\s+", "", cleaned, flags=re.IGNORECASE)
    cleaned = re.sub(r"^Artikel\s+", "", cleaned, flags=re.IGNORECASE)
    cleaned = re.sub(r"\s+", " ", cleaned).strip(" -")
    return cleaned


def gdoc_priority(gdoc: GDocPointer) -> tuple[int, int, int, int, str]:
    title_lower = gdoc.title.lower()
    penalty = 0
    if title_lower.startswith("copy of"):
        penalty += 5
    if any(word in title_lower for word in ("aantekeningen", "notes", "meuk", "research", "notities")):
        penalty += 4
    if title_lower.startswith("artikel "):
        penalty += 2
    cache_score = 0 if gdoc.cache_has_body else 1
    summary_score = 0 if gdoc.cache_summary else 1
    headline_score = 0 if gdoc.cache_headlines else 1
    return (cache_score, summary_score, headline_score, penalty, title_lower)


def best_gdoc(inventory: ProjectInventory) -> GDocPointer | None:
    if not inventory.gdocs:
        return None
    return sorted(inventory.gdocs, key=gdoc_priority)[0]


def choose_project_title(inventory: ProjectInventory, existing_metadata: dict[str, str]) -> str:
    if existing_metadata.get("title"):
        return existing_metadata["title"]
    if inventory.publication_artifacts and inventory.publication_artifacts[0].headline:
        return inventory.publication_artifacts[0].headline
    chosen_gdoc = best_gdoc(inventory)
    if chosen_gdoc:
        cleaned_title = clean_gdoc_title(chosen_gdoc.title)
        if cleaned_title:
            return cleaned_title
    return humanize_slug(inventory.project_root.name)


def choose_project_summary(inventory: ProjectInventory) -> str:
    if inventory.publication_artifacts:
        artifact = inventory.publication_artifacts[0]
        if artifact.summary:
            return artifact.summary
        if artifact.lead:
            return artifact.lead
    chosen_gdoc = best_gdoc(inventory)
    if chosen_gdoc and chosen_gdoc.cache_summary and not is_low_signal_text(chosen_gdoc.cache_summary):
        return chosen_gdoc.cache_summary
    if chosen_gdoc:
        if chosen_gdoc.cache_has_body and chosen_gdoc.cache_lead and not is_low_signal_text(chosen_gdoc.cache_lead):
            return chosen_gdoc.cache_lead
    docs_markdowns = [path for path in inventory.docs_files if path.suffix.lower() in {".md", ".txt"}]
    if docs_markdowns:
        try:
            text = docs_markdowns[0].read_text(encoding="utf-8")
        except OSError:
            return "Local files exist, but no readable Google Doc cache is available yet."
        paragraphs = [paragraph for paragraph in split_paragraphs(text) if len(paragraph) > 80]
        if paragraphs:
            return paragraphs[0]
    if chosen_gdoc:
        return (
            f"Working project around `{chosen_gdoc.title}`. "
            "Google Doc content has not been cached locally yet, so this README is based on filenames and local evidence only."
        )
    return "Local project files exist, but the central story summary still needs to be derived from the project documents."


def build_frontmatter(inventory: ProjectInventory, existing_metadata: dict[str, str]) -> str:
    project_slug = inventory.project_root.name
    started_default = existing_metadata.get("started") or f"{inventory.project_root.parent.name}-01-01"
    lines = [
        "---",
        f"type: {existing_metadata.get('type', 'project')}",
        f"project: {existing_metadata.get('project', project_slug)}",
        f"status: {existing_metadata.get('status', 'active')}",
        f"owner: {existing_metadata.get('owner', '')}",
        f"started: {started_default}",
        f"topics: {existing_metadata.get('topics', '[]')}",
        f"entities: {existing_metadata.get('entities', '[]')}",
        f"deliverable: {existing_metadata.get('deliverable', '')}",
        "---",
    ]
    return "\n".join(lines)


def build_readme(inventory: ProjectInventory) -> str:
    existing_metadata: dict[str, str] = {}
    if inventory.readme_path.exists():
        existing_metadata, _ = parse_frontmatter(inventory.readme_path.read_text(encoding="utf-8"))

    title = choose_project_title(inventory, existing_metadata)
    summary = choose_project_summary(inventory)
    cached_gdocs = [gdoc for gdoc in inventory.gdocs if gdoc.cache_has_body]
    pending_full_text_cache = [gdoc for gdoc in inventory.gdocs if not gdoc.cache_has_body]
    missing_local_cache = [gdoc for gdoc in inventory.gdocs if not gdoc.cache_counts_for_sweep]
    chosen_gdoc = best_gdoc(inventory)
    chosen_publication = inventory.publication_artifacts[0] if inventory.publication_artifacts else None

    topic_values: list[str] = []
    if chosen_publication:
        topic_values.extend(chosen_publication.topics)
    for gdoc in cached_gdocs:
        if gdoc.cache_summary and not is_low_signal_text(gdoc.cache_summary):
            topic_values.extend(gdoc.cache_topics)
    dedup_topics = tuple(dict.fromkeys(topic_values))
    likely_headline = ""
    if chosen_publication and chosen_publication.headline:
        likely_headline = chosen_publication.headline
    elif chosen_gdoc and chosen_gdoc.cache_headlines and not is_low_signal_text(chosen_gdoc.cache_headlines[0]):
        likely_headline = chosen_gdoc.cache_headlines[0]
    readme_quality = assess_readme_quality(inventory)

    lines = [
        build_frontmatter(inventory, existing_metadata),
        "",
        f"# {title}",
        "",
        "## Snapshot",
        "",
        f"- Summary: {summary}",
        f"- Root Google Doc pointers: {len(inventory.gdocs)}",
        f"- Local Google Doc cache files: {sum(1 for gdoc in inventory.gdocs if gdoc.cache_counts_for_sweep)}",
        f"- Cached Google Doc texts: {len(cached_gdocs)}",
        f"- Published PDF text caches: {len(inventory.publication_artifacts)}",
        f"- Files in `docs/`: {len(inventory.docs_files)}",
        f"- Other non-system files: {len(inventory.other_files)}",
        f"- Readme quality: `{readme_quality}`",
    ]

    if dedup_topics:
        lines.append(f"- Observed topics: {', '.join(f'`{topic}`' for topic in dedup_topics[:8])}")
    if likely_headline and likely_headline != title:
        lines.append(f"- Likely published headline: {likely_headline}")

    lines.extend(["", "## Google Docs", ""])
    if not inventory.gdocs:
        lines.append("- No root-level `.gdoc` files found.")
    else:
        for gdoc in inventory.gdocs:
            if gdoc.cache_has_body:
                cache_status = "cached body"
            elif gdoc.cache_counts_for_sweep:
                cache_status = "title stub"
            else:
                cache_status = "placeholder only"
            lines.append(f"- `{gdoc.title}` — `{cache_status}` — `{gdoc.url}`")
            if gdoc.cache_lead:
                lines.append(f"  - Lead: {gdoc.cache_lead}")
            elif gdoc.cache_summary:
                lines.append(f"  - Summary: {gdoc.cache_summary}")
            if gdoc.cache_headlines:
                lines.append(f"  - Headline candidates: {', '.join(gdoc.cache_headlines[:3])}")

    if inventory.publication_artifacts:
        lines.extend(["", "## Published PDF Text", ""])
        for artifact in inventory.publication_artifacts[:5]:
            lines.append(f"- `{artifact.pdf_title}` — `{artifact.path.relative_to(inventory.project_root)}`")
            if artifact.pdf_path:
                lines.append(f"  - Source PDF: `{artifact.pdf_path}`")
            if artifact.headline:
                lines.append(f"  - Headline: {artifact.headline}")
            if artifact.lead:
                lines.append(f"  - Lead: {artifact.lead}")

    lines.extend(["", "## Files On Disk", ""])
    extension_bits = [f"`{ext}`: {count}" for ext, count in sorted(inventory.extension_counts.items(), key=lambda item: (-item[1], item[0]))]
    lines.append(f"- Extension counts: {', '.join(extension_bits)}")

    docs_samples = sample_paths(inventory.docs_files, inventory.project_root)
    if docs_samples:
        lines.append(f"- `docs/` examples: {', '.join(f'`{sample}`' for sample in docs_samples)}")
    root_samples = sample_paths(inventory.root_files, inventory.project_root)
    if root_samples:
        lines.append(f"- Root file examples: {', '.join(f'`{sample}`' for sample in root_samples)}")

    lines.extend(["", "## Readme Workflow", ""])
    lines.append(f"- Google Doc manifest: `{inventory.manifest_path.relative_to(inventory.project_root)}`")
    lines.append(f"- Cached Google Docs live in `{(inventory.derived_root / 'google_docs').relative_to(inventory.project_root)}`")
    if missing_local_cache:
        lines.append(
            "- Pending local cache files for: "
            + ", ".join(f"`{gdoc.title}`" for gdoc in missing_local_cache)
        )
    else:
        lines.append("- All root Google Doc pointers have local cache files.")
    if pending_full_text_cache:
        lines.append(
            "- Pending full-text exports for: "
            + ", ".join(f"`{gdoc.title}`" for gdoc in pending_full_text_cache)
        )
    else:
        lines.append("- All root Google Doc pointers have full-text or structured cache content.")

    lines.extend(["", "## Next Steps", ""])
    if missing_local_cache:
        lines.append("- Create local cache files for any remaining root Google Doc pointers, then rerun the README builder.")
    if pending_full_text_cache:
        lines.append("- Use Codex with the Google Drive connector to replace title stubs with full document exports for the highest-value secondary docs.")
    lines.append("- Link this project to any published PDFs once publication status is confirmed.")
    lines.append("- Add evergreen topic/entity links when the project scope is stable.")
    return "\n".join(lines).rstrip() + "\n"


def assess_readme_quality(inventory: ProjectInventory) -> str:
    if inventory.publication_artifacts:
        return "high"
    chosen_gdoc = best_gdoc(inventory)
    if chosen_gdoc and chosen_gdoc.cache_has_body and chosen_gdoc.cache_summary and not is_low_signal_text(chosen_gdoc.cache_summary):
        return "high"
    if inventory.gdocs:
        return "partial"
    return "low"


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Build a project README from local files and cached Google Doc content.")
    parser.add_argument("--project-root", required=True, type=Path)
    parser.add_argument("--write-readme", action="store_true", help="Write README.md to the project root.")
    parser.add_argument("--overwrite", action="store_true", help="Overwrite an existing README.md.")
    parser.add_argument("--stdout", action="store_true", help="Print the generated README to stdout.")
    parser.add_argument("--skip-placeholder-cache", action="store_true", help="Do not create placeholder cache files for `.gdoc` pointers.")
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    inventory = collect_project_inventory(args.project_root)
    if not args.skip_placeholder_cache:
        ensure_cache_placeholders(inventory)
        inventory = collect_project_inventory(args.project_root)
    write_manifest(inventory)
    readme = build_readme(inventory)

    if args.stdout:
        print(readme, end="")

    if args.write_readme:
        if inventory.readme_path.exists() and not args.overwrite:
            raise SystemExit(f"README already exists: {inventory.readme_path}. Use --overwrite to replace it.")
        inventory.readme_path.write_text(readme, encoding="utf-8")
        print(inventory.readme_path)


if __name__ == "__main__":
    main()
