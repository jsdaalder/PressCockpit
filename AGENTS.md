# AGENTS.md

This file applies to the `journalism_workflow_hub` app repository.

## Workflow

- For non-trivial work in this app, use the `jwh-chief` workflow.
- The user should not have to manage subordinate agents directly.
- Prefer one `chief_of_staff` and a small number of specialists.
- Keep changes minimal, auditable, and scoped to the task.

## Planning Source Of Truth

- The canonical planning project for this app is `/Users/jandaalder/My Drive/coding_projects/Projects/2026/journalism_workflow_hub_plan`.
- Use that workspace-level project for live updates to `docs/current_priorities.md`, `docs/backlog.md`, `docs/roadmap.md`, `docs/architecture.md`, and related planning docs.
- Treat the repo-local `Projects/2026/journalism_workflow_hub_plan/` folder inside this app repo as a non-canonical pointer copy only.
- If a repo-local planning file and the workspace-level planning project appear to disagree, follow the workspace-level planning project and fix the pointer copy only if needed to keep the distinction explicit.

## Design And Engineering Split

- Separate abstract UX decisions from UI construction.
- Use `ux_strategist` before `ui_builder` when product direction is not already settled.
- Use `swift_architect` for technical shape when code impact is unclear.
- Use `swift_builder` for focused implementation.
- Use `qa_reviewer` for substantial review and regression checking.

## Constraints

- Do not encode the full orchestration logic only in this file. The source of truth for workflow behavior lives in `.agents/skills/jwh-chief/` and `.codex/agents/`.
- Do not add hooks or recurring automations for this workflow in v1 unless explicitly requested.
- Preserve the existing SwiftUI launcher direction unless the user asks for a redesign.
