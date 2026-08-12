#!/usr/bin/env python3

from __future__ import annotations

import argparse
from dataclasses import dataclass
from datetime import date
import json
import os
from pathlib import Path
import re
import subprocess
import textwrap
import unicodedata


MANAGED_START = "<!-- scaffold-doc-summaries:start -->"
MANAGED_END = "<!-- scaffold-doc-summaries:end -->"
SUPPORTED_TEXT_EXTENSIONS = {
    ".csv",
    ".html",
    ".htm",
    ".ics",
    ".json",
    ".md",
    ".rst",
    ".rtf",
    ".srt",
    ".text",
    ".tsv",
    ".txt",
    ".yaml",
    ".yml",
}
PREFERRED_MODELS = ("llama3.2:latest", "mistral:latest")
FAKE_MODE_ENV = "JWH_SCAFFOLD_SUMMARY_FAKE"
FORCE_INVALID_JSON_ENV = "JWH_SCAFFOLD_SUMMARY_FORCE_INVALID_JSON"
ANSI_ESCAPE_RE = re.compile(r"\x1B(?:[@-Z\\-_]|\[[0-?]*[ -/]*[@-~])")


@dataclass(frozen=True)
class ContextDocument:
    label: str
    path: Path
    text: str


@dataclass(frozen=True)
class SourceSummary:
    relative_path: str
    title: str
    summary: str
    project_relevance: str
    research_questions: tuple[str, ...]
    follow_up: tuple[str, ...]
    cautions: str
    user_note: str = ""


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Summarize scaffold-imported documents into docs/docs_overview.md using a local Ollama model."
    )
    parser.add_argument("--project-root", required=True)
    parser.add_argument("--imported-path", action="append", default=[])
    parser.add_argument("--relevance-note", default="")
    parser.add_argument("--review-notes-file", default="")
    parser.add_argument("--docs-overview-path", default="")
    parser.add_argument("--model", default="")
    parser.add_argument("--max-context-chars", type=int, default=4000)
    parser.add_argument("--max-source-chars", type=int, default=12000)
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    project_root = Path(args.project_root).expanduser().resolve()
    if not project_root.exists():
        raise SystemExit(f"Project root does not exist: {project_root}")

    docs_overview_path = (
        Path(args.docs_overview_path).expanduser().resolve()
        if args.docs_overview_path
        else project_root / "docs" / "docs_overview.md"
    )
    docs_overview_path.parent.mkdir(parents=True, exist_ok=True)

    imported_paths = collect_imported_paths(project_root, [Path(raw) for raw in args.imported_path])
    if not imported_paths:
        raise SystemExit("No supported imported files were provided for scaffold summarization.")

    context_docs = load_context_documents(project_root, max_chars=args.max_context_chars)
    relevance_note = sanitize_multiline_text(args.relevance_note).strip()
    review_notes_by_path = load_review_notes(args.review_notes_file)
    fake_mode = os.environ.get(FAKE_MODE_ENV) == "1"
    force_invalid_json = os.environ.get(FORCE_INVALID_JSON_ENV) == "1"
    model: str | None = None
    model_issue: str | None = None
    if not fake_mode and not force_invalid_json:
        try:
            model = args.model.strip() or resolve_ollama_model()
        except SystemExit as exc:
            model_issue = str(exc)
    summaries = [
        summarize_source(
            source_path,
            project_root=project_root,
            context_docs=context_docs,
            relevance_note=relevance_note,
            review_note=review_notes_by_path.get(str(source_path.resolve()), ""),
            model=model,
            model_issue=model_issue,
            max_source_chars=args.max_source_chars,
        )
        for source_path in imported_paths
    ]

    if docs_overview_path.exists():
        existing = docs_overview_path.read_text(encoding="utf-8")
    else:
        existing = "# Docs Overview\n\n"

    updated = merge_docs_overview(
        existing,
        project_root,
        context_docs,
        summaries,
        relevance_note=relevance_note,
    )
    docs_overview_path.write_text(updated, encoding="utf-8")
    print(f"Updated {docs_overview_path} with {len(summaries)} imported document summary item(s).")
    return 0


def collect_imported_paths(project_root: Path, raw_paths: list[Path]) -> list[Path]:
    supported: list[Path] = []
    seen: set[Path] = set()
    for raw_path in raw_paths:
        candidate = raw_path.expanduser().resolve()
        if not candidate.exists():
            continue
        nested = iter_supported_files(candidate)
        for path in nested:
            resolved = path.resolve()
            if resolved in seen:
                continue
            seen.add(resolved)
            supported.append(resolved)
    supported.sort(key=lambda path: str(path.relative_to(project_root)) if path.is_relative_to(project_root) else str(path))
    return supported


def iter_supported_files(path: Path) -> list[Path]:
    if path.is_file():
        return [path] if is_supported_file(path) else []

    if not path.is_dir():
        return []

    return [
        nested
        for nested in sorted(path.rglob("*"))
        if nested.is_file() and is_supported_file(nested)
    ]


def is_supported_file(path: Path) -> bool:
    ext = path.suffix.lower()
    return ext in SUPPORTED_TEXT_EXTENSIONS or ext in {".docx", ".odt", ".pdf"}


def load_context_documents(project_root: Path, max_chars: int) -> list[ContextDocument]:
    context_docs: list[ContextDocument] = []

    readme_path = project_root / "README.md"
    if readme_path.exists():
        text = truncate_text(extract_text(readme_path), max_chars)
        if text:
            context_docs.append(ContextDocument(label="README", path=readme_path, text=text))

    draft_candidate = find_context_candidate(project_root, role="draft")
    if draft_candidate is not None:
        text = truncate_text(extract_text(draft_candidate), max_chars)
        if text:
            context_docs.append(ContextDocument(label="Draft", path=draft_candidate, text=text))

    pitch_candidate = find_context_candidate(project_root, role="pitch")
    if pitch_candidate is not None:
        text = truncate_text(extract_text(pitch_candidate), max_chars)
        if text:
            context_docs.append(ContextDocument(label="Pitch", path=pitch_candidate, text=text))

    return context_docs


def find_context_candidate(project_root: Path, role: str) -> Path | None:
    candidates = sorted(project_root.glob("*")) + sorted((project_root / "docs").glob("**/*")) if (project_root / "docs").exists() else sorted(project_root.glob("*"))
    for path in candidates:
        if not path.is_file():
            continue
        lowered = path.name.lower()
        if role == "pitch" and "pitch" in lowered:
            return path
        if role == "draft" and any(token in lowered for token in ("draft", "artikel", "story", "tekst")):
            return path
    return None


def extract_text(path: Path) -> str:
    ext = path.suffix.lower()
    if ext in SUPPORTED_TEXT_EXTENSIONS:
        return sanitize_multiline_text(read_text_file(path))
    if ext in {".docx", ".odt", ".rtf", ".html", ".htm"}:
        return sanitize_multiline_text(run_textutil(path))
    if ext == ".pdf":
        return sanitize_multiline_text(run_pdftotext(path))
    return ""


def read_text_file(path: Path) -> str:
    for encoding in ("utf-8", "utf-8-sig", "latin-1"):
        try:
            return path.read_text(encoding=encoding)
        except UnicodeDecodeError:
            continue
    return ""


def run_textutil(path: Path) -> str:
    completed = subprocess.run(
        ["textutil", "-convert", "txt", "-stdout", str(path)],
        capture_output=True,
        text=True,
        check=False,
    )
    return completed.stdout if completed.returncode == 0 else ""


def run_pdftotext(path: Path) -> str:
    try:
        completed = subprocess.run(
            ["pdftotext", "-layout", "-nopgbrk", str(path), "-"],
            capture_output=True,
            text=True,
            check=False,
        )
    except OSError:
        return ""
    return completed.stdout if completed.returncode == 0 else ""


def resolve_ollama_model() -> str:
    override = (os.environ.get("JWH_SCAFFOLD_OLLAMA_MODEL") or "").strip()
    if override:
        return override

    completed = subprocess.run(
        ["ollama", "list"],
        capture_output=True,
        text=True,
        check=False,
    )
    if completed.returncode != 0:
        stderr = completed.stderr.strip()
        raise SystemExit(stderr or "Could not query the local Ollama runtime.")

    available_models: list[str] = []
    for line in completed.stdout.splitlines()[1:]:
        stripped = line.strip()
        if not stripped:
            continue
        available_models.append(stripped.split()[0])

    for candidate in PREFERRED_MODELS:
        if candidate in available_models:
            return candidate

    if available_models:
        return available_models[0]

    raise SystemExit("No local Ollama models are installed. Install one and retry scaffold summarization.")


def summarize_source(
    source_path: Path,
    *,
    project_root: Path,
    context_docs: list[ContextDocument],
    relevance_note: str,
    review_note: str,
    model: str | None,
    model_issue: str | None,
    max_source_chars: int,
) -> SourceSummary:
    source_text = truncate_text(extract_text(source_path), max_source_chars)
    if not source_text:
        return SourceSummary(
            relative_path=relative_label(source_path, project_root),
            title=source_path.name,
            summary="The file could not be converted into readable local text yet.",
            project_relevance="Needs manual review before its project relevance can be trusted.",
            research_questions=("Can this file be converted or replaced with a readable local format?",),
            follow_up=("Open the original file manually and capture the key takeaways in a note.",),
            cautions="No local text could be extracted for the model.",
            user_note=review_note,
        )

    if os.environ.get(FAKE_MODE_ENV) == "1":
        return fake_summary(source_path, project_root=project_root, source_text=source_text, review_note=review_note)

    if os.environ.get(FORCE_INVALID_JSON_ENV) == "1":
        try:
            parse_summary_payload("This is not valid JSON.")
        except SystemExit as exc:
            return fallback_summary(
                source_path,
                project_root=project_root,
                source_text=source_text,
                reason=str(exc),
                review_note=review_note,
            )

    if model_issue:
        return fallback_summary(
            source_path,
            project_root=project_root,
            source_text=source_text,
            reason=model_issue,
            review_note=review_note,
        )

    if not model:
        return fallback_summary(
            source_path,
            project_root=project_root,
            source_text=source_text,
            reason="No local model was available for structured summarization.",
            review_note=review_note,
        )

    prompt = build_prompt(
        source_path,
        project_root=project_root,
        context_docs=context_docs,
        relevance_note=relevance_note,
        review_note=review_note,
        source_text=source_text,
    )
    try:
        response = run_ollama_prompt(model=model, prompt=prompt)
        payload = parse_summary_payload(response)
    except SystemExit as exc:
        return fallback_summary(
            source_path,
            project_root=project_root,
            source_text=source_text,
            reason=str(exc),
            review_note=review_note,
        )

    return SourceSummary(
        relative_path=relative_label(source_path, project_root),
        title=payload.get("title") or source_path.name,
        summary=compact_text(payload.get("summary")) or "Summary missing.",
        project_relevance=compact_text(payload.get("project_relevance")) or "Project relevance still needs review.",
        research_questions=tuple(clean_list(payload.get("research_questions"))[:3]) or ("What does this file change about the current reporting direction?",),
        follow_up=tuple(clean_list(payload.get("follow_up"))[:3]),
        cautions=compact_text(payload.get("cautions")) or "Model-generated working note. Review against the source before reusing it.",
        user_note=review_note,
    )


def fake_summary(source_path: Path, *, project_root: Path, source_text: str, review_note: str) -> SourceSummary:
    lead = compact_text(source_text.splitlines()[0] if source_text.splitlines() else source_text) or "No readable lead."
    return SourceSummary(
        relative_path=relative_label(source_path, project_root),
        title=source_path.name,
        summary=f"Working summary from {source_path.name}: {lead}",
        project_relevance="Likely relevant to the current project because it was imported during scaffold intake.",
        research_questions=(
            f"What claim from {source_path.name} matters most for this project?",
            "What should be verified independently before using this source?",
        ),
        follow_up=("Check the source against the README assumptions.",),
        cautions="Fake summary mode was used for verification only.",
        user_note=review_note,
    )


def fallback_summary(
    source_path: Path,
    *,
    project_root: Path,
    source_text: str,
    reason: str,
    review_note: str,
) -> SourceSummary:
    lead = compact_text(source_text.splitlines()[0] if source_text.splitlines() else source_text) or "No readable lead."
    return SourceSummary(
        relative_path=relative_label(source_path, project_root),
        title=source_path.name,
        summary=f"Fallback summary from {source_path.name}: {lead}",
        project_relevance="Imported into this project, but the structured local-model summary was unavailable. Review the source directly before relying on this note.",
        research_questions=(
            f"What does {source_path.name} change or confirm for this project?",
            "Which claims or figures from this source need manual verification?",
        ),
        follow_up=("Open the file and capture the key takeaways in a note or README update.",),
        cautions=f"{compact_text(reason) or 'The local summary step failed.'} A text-based fallback summary was written instead.",
        user_note=review_note,
    )


def build_prompt(
    source_path: Path,
    *,
    project_root: Path,
    context_docs: list[ContextDocument],
    relevance_note: str,
    review_note: str,
    source_text: str,
) -> str:
    context_block = "\n\n".join(
        f"[{doc.label} | {relative_label(doc.path, project_root)}]\n{doc.text}"
        for doc in context_docs
    ) or "No extra context documents were readable."
    note_parts = [note for note in (review_note, relevance_note) if note]
    user_note_block = "\n\n".join(note_parts) if note_parts else "No user-entered relevance note was provided."

    return textwrap.dedent(
        f"""\
        You are helping maintain a local journalism project workspace.
        Read the project context first, then summarize the imported source file.
        Focus on:
        - the source's concrete content
        - why it matters for this project
        - the research questions or checks it suggests next

        Return strict JSON with these keys:
        {{
          "title": string,
          "summary": string,
          "project_relevance": string,
          "research_questions": [string],
          "follow_up": [string],
          "cautions": string
        }}

        Project root: {project_root.name}

        Context:
        {context_block}

        User relevance note:
        {user_note_block}

        Imported source:
        [Source | {source_path.name}]
        {source_text}
        """
    )


def run_ollama_prompt(*, model: str, prompt: str) -> str:
    completed = subprocess.run(
        ["ollama", "run", model],
        input=prompt,
        capture_output=True,
        text=True,
        check=False,
    )
    if completed.returncode != 0:
        stderr = completed.stderr.strip()
        stdout = completed.stdout.strip()
        raise SystemExit(stderr or stdout or "The local Ollama prompt failed.")
    return completed.stdout


def parse_summary_payload(raw_text: str) -> dict[str, object]:
    stripped = strip_code_fences(raw_text.strip())
    payload = extract_json_payload(stripped)
    if payload is None:
        raise SystemExit("The local model did not return parseable JSON for the scaffold summary step.")
    return payload


def extract_json_payload(text: str) -> dict[str, object] | None:
    decoder = json.JSONDecoder(strict=False)
    for index, char in enumerate(text):
        if char != "{":
            continue
        try:
            payload, _ = decoder.raw_decode(text[index:])
        except json.JSONDecodeError:
            continue
        if isinstance(payload, dict):
            return payload
    return None


def strip_code_fences(text: str) -> str:
    if text.startswith("```"):
        text = re.sub(r"^```[a-zA-Z0-9_-]*\n?", "", text)
        text = re.sub(r"\n?```$", "", text)
    return text.strip()


def clean_list(raw_value: object) -> list[str]:
    if isinstance(raw_value, list):
        return [compact_text(str(item)) for item in raw_value if compact_text(str(item))]
    return []


def compact_text(raw_value: object | None) -> str:
    if raw_value is None:
        return ""
    sanitized = sanitize_multiline_text(str(raw_value))
    return re.sub(r"\s+", " ", sanitized).strip()


def truncate_text(text: str, max_chars: int) -> str:
    compact = sanitize_multiline_text(text).strip()
    if len(compact) <= max_chars:
        return compact
    return compact[: max_chars - 1].rstrip() + "…"


def sanitize_multiline_text(text: str) -> str:
    if not text:
        return ""

    stripped = ANSI_ESCAPE_RE.sub("", text)
    normalized: list[str] = []
    for char in stripped:
        if char in ("\n", "\r", "\t"):
            normalized.append(char)
            continue
        if unicodedata.category(char).startswith("C"):
            normalized.append(" ")
            continue
        normalized.append(char)
    return "".join(normalized)


def merge_docs_overview(
    existing_text: str,
    project_root: Path,
    context_docs: list[ContextDocument],
    summaries: list[SourceSummary],
    relevance_note: str,
) -> str:
    section_body = build_managed_summary_section(
        project_root,
        context_docs,
        summaries,
        relevance_note=relevance_note,
    )
    managed_block = f"{MANAGED_START}\n{section_body}\n{MANAGED_END}"

    if MANAGED_START in existing_text and MANAGED_END in existing_text:
        pattern = re.compile(
            rf"{re.escape(MANAGED_START)}.*?{re.escape(MANAGED_END)}",
            flags=re.S,
        )
        return pattern.sub(managed_block, existing_text, count=1)

    insertion = "\n\n## Imported document synthesis\n\n" + managed_block + "\n"
    if "## Next steps" in existing_text:
        return existing_text.replace("## Next steps", insertion + "\n## Next steps", 1)
    return existing_text.rstrip() + insertion


def build_managed_summary_section(
    project_root: Path,
    context_docs: list[ContextDocument],
    summaries: list[SourceSummary],
    relevance_note: str,
) -> str:
    lines = [
        f"_Updated: {date.today().isoformat()}_",
        "",
        "_Local-model working notes. Review against the original files before treating these summaries as settled project facts._",
        "",
        "### Context used",
    ]

    if context_docs:
        for doc in context_docs:
            lines.append(f"- {doc.label}: `{relative_label(doc.path, project_root)}`")
    else:
        lines.append("- README, draft, or pitch text was not readable locally, so the summaries rely on the imported files alone.")

    if relevance_note:
        lines.extend(["", "### Why these files matter now", ""])
        lines.extend(relevance_note.splitlines())

    lines.extend(["", "### Imported file summaries", ""])

    for summary in summaries:
        lines.extend(
            [
                f"#### {summary.title}",
                f"- Path: `{summary.relative_path}`",
                f"- Summary: {summary.summary}",
                f"- Project relevance: {summary.project_relevance}",
                f"- Research questions: {join_inline(summary.research_questions)}",
            ]
        )
        if summary.user_note:
            lines.append(f"- Note: {summary.user_note}")
        if summary.follow_up:
            lines.append(f"- Follow-up: {join_inline(summary.follow_up)}")
        lines.append(f"- Cautions: {summary.cautions}")
        lines.append("")

    return "\n".join(lines).rstrip()


def join_inline(items: tuple[str, ...]) -> str:
    cleaned = [item for item in items if item]
    return "; ".join(cleaned) if cleaned else "None captured yet."


def load_review_notes(raw_path: str) -> dict[str, str]:
    if not raw_path:
        return {}

    path = Path(raw_path).expanduser().resolve()
    if not path.exists():
        raise SystemExit(f"Review notes file does not exist: {path}")

    payload = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(payload, dict):
        raise SystemExit("Review notes file must contain a JSON object keyed by imported path.")

    normalized: dict[str, str] = {}
    for raw_key, raw_value in payload.items():
        if not isinstance(raw_key, str) or not isinstance(raw_value, str):
            continue
        note = sanitize_multiline_text(raw_value).strip()
        if note:
            normalized[str(Path(raw_key).expanduser().resolve())] = note
    return normalized


def relative_label(path: Path, project_root: Path) -> str:
    try:
        return str(path.resolve().relative_to(project_root.resolve()))
    except ValueError:
        return str(path.resolve())


if __name__ == "__main__":
    raise SystemExit(main())
