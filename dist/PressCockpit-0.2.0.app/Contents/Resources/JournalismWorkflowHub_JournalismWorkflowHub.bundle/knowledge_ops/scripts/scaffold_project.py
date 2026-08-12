#!/usr/bin/env python3

from __future__ import annotations

import argparse
from pathlib import Path
import sys
import textwrap


PROJECT_TYPE_MAP = {
    "journalism": "journalism",
    "data_journalism": "data_journalism",
    "private_coding": "tooling",
    "other": "general",
}

LEGACY_STATUS_MAP = {
    "active": ("active", "lead", "", "active"),
    "scaffold_demo": ("active", "lead", "", "active"),
    "on_hold": ("inactive", "active_investigation", "waiting", "on_hold"),
    "paused": ("inactive", "active_investigation", "waiting", "on_hold"),
    "done": ("inactive", "published", "finished", "done"),
    "published": ("inactive", "published", "finished", "done"),
    "archived": ("inactive", "published", "finished", "archived"),
}


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Create a starter journalism project with README, AGENTS, and docs overview."
    )
    parser.add_argument("--project-root", required=True)
    parser.add_argument("--title", required=True)
    parser.add_argument("--owner", required=True)
    parser.add_argument("--activity-state", default="")
    parser.add_argument("--workflow-stage", default="")
    parser.add_argument("--inactive-reason", default="")
    parser.add_argument("--status", default="active")
    parser.add_argument("--project-type", default="journalism")
    parser.add_argument("--dossier", default="")
    parser.add_argument("--started", required=True)
    parser.add_argument("--deliverable", default="")
    parser.add_argument("--section-answer-1", default="")
    parser.add_argument("--section-answer-2", default="")
    parser.add_argument("--section-answer-3", default="")
    parser.add_argument("--topics", nargs="*", default=[])
    parser.add_argument("--entities", nargs="*", default=[])
    return parser.parse_args()


def normalize_project_type(raw_value: str) -> str:
    normalized = raw_value.strip().lower().replace("-", "_").replace(" ", "_")
    return PROJECT_TYPE_MAP.get(normalized, normalized or "general")


def yaml_list(values: list[str]) -> str:
    cleaned = [value.strip() for value in values if value.strip()]
    return "[" + ", ".join(f'"{value}"' for value in cleaned) + "]"


def normalize_state_token(value: str) -> str:
    return value.strip().lower().replace("-", "_").replace(" ", "_")


def derive_project_state(status: str) -> tuple[str, str, str, str]:
    normalized = normalize_state_token(status)
    return LEGACY_STATUS_MAP.get(normalized, ("active", "lead", "", "active"))


def derive_legacy_status(
    activity_state: str,
    workflow_stage: str,
    inactive_reason: str,
) -> str:
    if activity_state == "active":
        return "active"
    if inactive_reason == "finished" or workflow_stage == "published":
        return "done"
    return "on_hold"


def resolve_project_state(
    activity_state: str,
    workflow_stage: str,
    inactive_reason: str,
    status: str,
) -> tuple[str, str, str, str]:
    normalized_activity = normalize_state_token(activity_state)
    normalized_stage = normalize_state_token(workflow_stage)
    normalized_reason = normalize_state_token(inactive_reason)

    if not normalized_activity and not normalized_stage and not normalized_reason:
        return derive_project_state(status)

    if not normalized_activity or not normalized_stage:
        raise ValueError("Explicit project state requires both --activity-state and --workflow-stage.")

    if normalized_activity not in {"active", "inactive"}:
        raise ValueError(f"Unsupported activity_state: {activity_state}")

    if normalized_activity == "active":
        normalized_reason = ""
    elif not normalized_reason:
        raise ValueError("inactive_reason is required when activity_state is inactive.")

    legacy_status = derive_legacy_status(
        normalized_activity,
        normalized_stage,
        normalized_reason,
    )
    return normalized_activity, normalized_stage, normalized_reason, legacy_status


def write_new_file(path: Path, contents: str) -> None:
    if path.exists():
        raise FileExistsError(f"Refusing to overwrite existing file: {path}")
    path.write_text(contents, encoding="utf-8")


def build_readme(
    title: str,
    owner: str,
    activity_state: str,
    workflow_stage: str,
    inactive_reason: str,
    status: str,
    project_type: str,
    dossier: str,
    started: str,
    deliverable: str,
    structured_answers: list[str],
    topics: list[str],
    entities: list[str],
) -> str:
    summary = deliverable.strip() or "Short project summary."
    sections = readme_sections(project_type, structured_answers)
    activity_state, workflow_stage, inactive_reason, legacy_status = resolve_project_state(
        activity_state,
        workflow_stage,
        inactive_reason,
        status,
    )
    lines = [
        "---",
        "type: project",
        f"project: {title}",
        f"owner: {owner}",
        f"activity_state: {activity_state}",
        f"workflow_stage: {workflow_stage}",
    ]
    if inactive_reason:
        lines.append(f"inactive_reason: {inactive_reason}")
    lines.extend([
        f"status: {legacy_status}",
        f"project_type: {project_type}",
    ])
    trimmed_dossier = dossier.strip()
    if trimmed_dossier:
        lines.append(f"dossier: {trimmed_dossier}")
    lines.extend([
        f"started: {started}",
        f"deliverable: {summary}",
        f"topics: {yaml_list(topics)}",
        f"entities: {yaml_list(entities)}",
        "safety: internal",
        "---",
        "",
        f"# {title}",
        "",
        summary,
        "",
        sections,
    ])
    return "\n".join(lines) + "\n"


def build_agents() -> str:
    return textwrap.dedent(
        """\
        # AGENTS.md

        This file applies to this project root.

        ## Safety

        - Keep raw source material unchanged.
        - Write transformed outputs to derived folders or clearly named files.
        - Preserve notes about provenance, sourcing, and publication checks.

        ## Workflow

        - Use `docs/` for working material, references, and reporting notes.
        - Keep the project README current as the reporting direction sharpens.
        """
    )


def build_docs_overview(title: str, project_type: str) -> str:
    expected_contents = docs_overview_expected_contents(project_type)
    next_steps = docs_overview_next_steps(project_type)
    lines = [
        "# Docs Overview",
        "",
        f"Date created: {current_date()}",
        "",
        "## Project",
        "",
        f"- Title: {title}",
        "",
        "## Expected contents",
        "",
        expected_contents,
        "",
        "## Imported document synthesis",
        "",
        "<!-- scaffold-doc-summaries:start -->",
        "_No imported source summaries yet. The local summary step can fold working notes here after scaffold uploads._",
        "<!-- scaffold-doc-summaries:end -->",
        "",
        "## Next steps",
        "",
        next_steps,
    ]
    return "\n".join(lines) + "\n"


def current_date() -> str:
    from datetime import date

    return date.today().isoformat()


def readme_sections(project_type: str, structured_answers: list[str]) -> str:
    prompts = structured_section_prompts(project_type)
    first_section_lines = [
        render_structured_line(label, answer)
        for label, answer in zip(prompts, structured_answers)
    ]

    sections_by_type = {
        "journalism": [
            (
                "Reporting question",
                first_section_lines,
            ),
            (
                "Source status",
                [
                    "Key documents:",
                    "Interviews:",
                    "Known gaps:",
                ],
            ),
            (
                "Next reporting steps",
                [
                    "Add the first source materials to `docs/`",
                    "Record the first reporting questions and assumptions",
                    "Note the first fact-check and publication risks",
                ],
            ),
        ],
        "data_journalism": [
            (
                "Core question",
                first_section_lines,
            ),
            (
                "Data plan",
                [
                    "Primary datasets:",
                    "Join keys or units of analysis:",
                    "Cleaning or transformation needs:",
                ],
            ),
            (
                "Next analysis steps",
                [
                    "Add raw data sources with provenance notes",
                    "Record the first transformation and validation steps",
                    "Note likely charts, tables, or publication outputs",
                ],
            ),
        ],
        "tooling": [
            (
                "Problem",
                first_section_lines,
            ),
            (
                "Technical shape",
                [
                    "Inputs and outputs:",
                    "Runtime or stack:",
                    "Dependencies or integrations:",
                ],
            ),
            (
                "Next build steps",
                [
                    "Define the smallest working slice",
                    "Record setup and run commands",
                    "Keep implementation notes and risks explicit",
                ],
            ),
        ],
        "general": [
            (
                "Scope",
                first_section_lines,
            ),
            (
                "Current context",
                [
                    "Relevant inputs:",
                    "Open questions:",
                    "Risks or unknowns:",
                ],
            ),
            (
                "Next steps",
                [
                    "Add the first materials or references",
                    "Clarify the first concrete goal",
                    "Keep assumptions and decisions visible in the README",
                ],
            ),
        ],
    }
    sections = sections_by_type.get(project_type, sections_by_type["general"])
    return "\n\n".join(render_section(title, bullets) for title, bullets in sections)


def structured_section_prompts(project_type: str) -> list[str]:
    prompts_by_type = {
        "journalism": [
            "Main reporting question:",
            "Working hypothesis:",
            "Why this matters now:",
        ],
        "data_journalism": [
            "Main question:",
            "Expected pattern or claim:",
            "Why data is needed here:",
        ],
        "tooling": [
            "What this tool should unblock:",
            "Who it is for:",
            "Constraints or non-goals:",
        ],
        "general": [
            "What this project is:",
            "What it is not:",
            "Why it exists:",
        ],
    }
    return prompts_by_type.get(project_type, prompts_by_type["general"])


def render_structured_line(label: str, answer: str) -> str:
    trimmed = answer.strip()
    return f"{label} {trimmed}" if trimmed else label


def render_section(title: str, bullets: list[str]) -> str:
    return textwrap.dedent(
        "\n".join(
            [f"## {title}", ""]
            + [f"- {bullet}" for bullet in bullets]
        )
    ).strip()


def docs_overview_expected_contents(project_type: str) -> str:
    contents_by_type = {
        "journalism": """
        - source documents and reference material
        - notes and research
        - interview transcripts
        - drafts or linked document pointers
        """,
        "data_journalism": """
        - raw datasets and provenance notes
        - data dictionaries or schema notes
        - cleaning and transformation notes
        - charts, tables, and reporting drafts
        """,
        "tooling": """
        - product notes and requirements
        - technical references
        - test inputs or fixtures
        - screenshots, demos, or implementation notes
        """,
        "general": """
        - project notes and references
        - working materials
        - supporting documents
        - drafts, decisions, or follow-up notes
        """,
    }
    return textwrap.dedent(contents_by_type.get(project_type, contents_by_type["general"])).strip()


def docs_overview_next_steps(project_type: str) -> str:
    steps_by_type = {
        "journalism": """
        - add source material
        - record key reporting questions
        - keep provenance and publication checks explicit
        """,
        "data_journalism": """
        - add source datasets with provenance notes
        - define the first cleaning or transformation pass
        - record validation checks before publication use
        """,
        "tooling": """
        - define the smallest useful build slice
        - record setup and run steps
        - keep technical decisions and risks explicit
        """,
        "general": """
        - add the first supporting materials
        - clarify the first concrete output
        - keep decisions and unknowns visible
        """,
    }
    return textwrap.dedent(steps_by_type.get(project_type, steps_by_type["general"])).strip()


def main() -> int:
    args = parse_args()
    project_root = Path(args.project_root).expanduser()
    project_type = normalize_project_type(args.project_type)

    if project_root.exists() and any(project_root.iterdir()):
        print(f"Project root already exists and is not empty: {project_root}", file=sys.stderr)
        return 1

    project_root.mkdir(parents=True, exist_ok=True)
    docs_root = project_root / "docs"
    docs_root.mkdir(parents=True, exist_ok=True)

    try:
        write_new_file(
            project_root / "README.md",
            build_readme(
                title=args.title.strip(),
                owner=args.owner.strip(),
                activity_state=args.activity_state,
                workflow_stage=args.workflow_stage,
                inactive_reason=args.inactive_reason,
                status=args.status.strip(),
                project_type=project_type,
                dossier=args.dossier,
                started=args.started.strip(),
                deliverable=args.deliverable,
                structured_answers=[
                    args.section_answer_1,
                    args.section_answer_2,
                    args.section_answer_3,
                ],
                topics=args.topics,
                entities=args.entities,
            ),
        )
        write_new_file(project_root / "AGENTS.md", build_agents())
        write_new_file(docs_root / "docs_overview.md", build_docs_overview(args.title.strip(), project_type))
    except (FileExistsError, ValueError) as error:
        print(str(error), file=sys.stderr)
        return 1

    print(f"Created project scaffold at {project_root}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
