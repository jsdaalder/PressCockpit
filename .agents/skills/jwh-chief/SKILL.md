---
name: "jwh-chief"
description: "Chief-of-staff entrypoint for journalism_workflow_hub. Use for planning, feature work, refactors, debugging, UX decisions, UI implementation, and reviews when the task may benefit from deliberate orchestration."
---

# JWH Chief

Use this skill as the default entrypoint for meaningful work in `journalism_workflow_hub`.

This skill exists so the user does not have to manage subordinate agents manually.
For non-trivial work, route through `chief_of_staff`, let the chief decide whether
delegation is warranted, and return one synthesized answer.

## When to use this skill

Use this skill for:

- planning the app
- building features
- refactoring
- debugging
- UX or product decisions
- UI implementation
- code review

Do not use this skill for trivial, single-file, low-risk tasks that can be completed cleanly by one agent without orchestration.

## Workflow

1. Classify the task.
2. If the task is trivial, stay single-agent and complete it directly.
3. If the task is non-trivial, route through `chief_of_staff`.
4. Require the chief to choose only the specialists that materially help.
5. Wait for the delegated work to finish.
6. Return a single synthesized answer to the user.

## Delegation policy

The chief should use specialists as follows:

- `ux_strategist` for workflow shape, information architecture, navigation model, priorities, and abstract UX tradeoffs
- `ui_builder` for concrete SwiftUI screen and component work once UX direction is established
- `swift_architect` for implementation shape, model/view boundaries, data flow, state ownership, and test implications
- `swift_builder` for actual code changes
- `qa_reviewer` for substantial reviews or verification before closing riskier work
- `privacy_security_reviewer` for privacy, security, secrets, permissions, export safety, redaction risk, and unsafe-default review
- `process_workflow_auditor` for planning hygiene, workflow maturity, decision traceability, onboarding clarity, and future-proofing review

Built-in `explorer` is acceptable for lightweight read-heavy inspection when a full custom specialist is unnecessary.

## Chief-of-staff requirements

When this skill routes through `chief_of_staff`, require the chief to:

- restate the goal and success criteria
- decide whether delegation is needed
- spawn the minimum useful set of specialists
- avoid broad fan-out
- reconcile conflicting specialist outputs
- apply the planning lifecycle guardrail for non-trivial work
- return one merged recommendation, plan, implementation path, or review

Never hand raw subagent output back to the user as the final result.

## Planning lifecycle guardrail

For non-trivial work, require the chief to check the planning lifecycle:

1. If the request is only a new idea or product question, capture or recommend capturing it in `Projects/2026/journalism_workflow_hub_plan/docs/backlog.md`.
2. If the work is a realistic near-term candidate, check whether it belongs in `Projects/2026/journalism_workflow_hub_plan/docs/current_priorities.md`.
3. Before implementation, check whether it touches data models, persistence, workflow execution, preflight behavior, permissions, privacy posture, document export safety, filesystem assumptions, sync/cloud/collaboration, or cross-cutting app boundaries. If yes, update or request an update to `Projects/2026/journalism_workflow_hub_plan/docs/architecture.md` before coding.
4. After implementation or review, verify appropriately with tests, focused review, or a clear statement of what could not be run.
5. Before closing, ensure planning docs still match reality or explicitly say no planning update was needed.

Skip this guardrail for trivial wording changes, obvious one-file fixes, and low-risk mechanical edits.

## Design separation

Keep abstract UX decisions separate from UI construction:

- Use `ux_strategist` before `ui_builder` when product direction is unsettled.
- Use `ui_builder` directly when the workflow model is already decided and the task is concrete interface execution.

## Operating defaults

- Keep changes minimal and auditable.
- Preserve the existing product direction unless a redesign is explicitly requested.
- Avoid automations and hooks for this workflow in v1.
