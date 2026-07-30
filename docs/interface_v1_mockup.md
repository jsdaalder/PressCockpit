# Journalism Workflow Hub Interface V1

Date: 2026-07-06

## Goal

Create a fast first interface that is good enough to judge:

- whether the app matches the actual reporting workflow
- whether the main surfaces are in the right order
- whether important features are missing before the UI hardens

This is a product-direction mock-up, not a final visual design.
It should stay aligned with the canonical workspace-level planning project outside this repo: `Projects/2026/journalism_workflow_hub_plan/docs/product/v1_product_definition.md` and `Projects/2026/journalism_workflow_hub_plan/docs/specs/overview_screen_spec_v1.md`.

For the guided project creation flow, see:

- `docs/scaffold_project_wizard_v1.md`

For concrete visual comparison of the three current `Overview` directions, see:

- `docs/overview_directions_mockups.html`

## Core Product View

The app is a newsroom operations shell with five jobs:

1. show the state of the workspace
2. help the user open the right project fast
3. make workflows runnable with clear write boundaries
4. show what happened in recent runs
5. keep the plan visible next to execution

This means the app is:

- a dispatch surface, not a generic dashboard builder
- a trustworthy view over the real workspace, not a parallel system
- a local-first shell over files, folders, and scripts that already exist

## Long-Term Portability Constraint

Very much not for v1, but the product direction should already respect this:

- the app should eventually be releasable as an open-source macOS app for other journalists
- a new user should be able to install the app and create a usable underlying workspace automatically
- the interface should avoid assuming Jan-specific absolute paths, folder names, or private tooling forever
- workflow and layout decisions should prefer reproducible, data-driven configuration over hardcoded personal assumptions

Implication for mock-ups:

- use examples like `<workspace_root>` and `<selected_project>` instead of personal absolute paths where possible
- keep empty states and first-run onboarding in mind even if they are not implemented in v1

## V1 Navigation

Use a stable left sidebar with five top-level destinations:

- Overview
- Workspace
- Workflows
- Runs
- Plan

Use the main pane for detail. Do not add multiple windows, tabs, or floating inspectors in v1.

## Primary Screen Model

### 1. Overview

Purpose:
be the calm editorial home screen for active work first, while still supporting safe new work

Contents:

- active project cards
- secondary open-project board grouped by workflow state
- suggested next actions
- compact operational follow-up
- restrained new-project entry point
- future brainstorming or intake affordances only as secondary hints, not dominant modules

Wireframe:

```text
+----------------------------------------------------------------------------------+
| Journalism Hub                                 [Refresh] [Start new project]     |
+----------------------------------------------------------------------------------+
| Overview                                                                       |
| The stories you are working on, what needs attention, and what to do next.     |
+----------------------------------------------------------------------------------+
| Active projects                                                                  |
| - Water quality exports        Need source review        Next: check interview   |
| - Housing permits              Missing project basics    Next: update README      |
| - Agro lobby timeline          Ready to move             Next: draft chronology   |
| - Methane enforcement          Workflow follow-up        Next: inspect failed run |
|----------------------------------------------------------------------------------|
| Open projects                                                                    |
| [Inbox]     [Scoped]     [Reporting]     [Drafting]     [Review]     [Ready]    |
| - Permit log - Soil map - School heat - Budget cuts - Lobby memo - Export pack  |
| - River data - Farm deal - Council Q&A                                           |
+---------------------------------------------+------------------------------------+
| Suggested next actions                       | Operations                         |
| - Needs review before sharing   2 projects   | - Publishing follow-up     3       |
| - Workflow needs attention      1 run        | - Admin cleanup            4       |
| - Project basics missing        2 projects   | - Git / workflow checks    2       |
+---------------------------------------------+------------------------------------+
| New work                                                                          |
| [Start new project]   [Brainstorm from archive]                                   |
+----------------------------------------------------------------------------------+
```

Screen contract:

- Overview should foreground active projects before global counts or abstract system state.
- Active projects stay at the top as the highest-priority dispatch surface; the broader open-project view belongs below them.
- Overview should prioritize trust, drift, and next actions over comprehensive browsing.
- If a user lands here and still does not know what to do next, the screen is failing.
- Overview should stay curated; it should not become a second Workspace screen or a dashboard of unrelated metrics.
- The secondary open-projects area should read as a horizontal kanban board, not a long vertical backlog list.
- The board should always render one column per workflow state, even when a state currently has no projects.
- Empty workflow-state columns should remain visible with a lightweight empty state so the process model stays legible.
- Projects in the open-projects board should use the same collapsible pattern as the active-project cards, so dense scanning and deeper inspection can coexist.
- Dragging a project card into the next workflow-state column should update its workflow state directly from the overview.
- Dragging should optimize for adjacent forward movement first; broader reordering or arbitrary state jumps can wait until the workflow rules are clearer.
- Flagged projects should always say why they are flagged.
- Operational and bureaucratic tasks should be visible but clearly secondary to story work.
- Future brainstorming and intake directions may start here, but should move out if they create clutter.

Future additions worth validating:

- The open-projects board may need a clear rule for horizontal overflow: either scroll the board as one strip or compress columns only down to a defined minimum width.
- If drag-to-advance is added, the card should show a clear drop target and confirm the state change without forcing the user into the workspace detail view.
- Some workflow states may eventually need WIP counts, column-level warnings, or stage-specific empty-copy, but that should be additive to the stable state-column structure rather than replacing it.
- The per-project `More` expansion may need lightweight lifecycle controls such as:
  - lower priority or standard priority
  - archive because the work is finished
  - archive because the work is discontinued
- A "finished" path should not behave like a silent archive. It should start a small offboarding flow that confirms the project is ready to leave the active list and captures publication handoff tasks such as linking or uploading the published PDF.
- Overview may also need soft housekeeping prompts at project level for gaps like missing pitch, missing draft, missing folder structure, or missing README.
- Those prompts should stay advisory, not punitive. A missing pitch is sometimes acceptable, so the user should be able to dismiss or snooze a housekeeping suggestion without making the project look broken.
- If these prompts are added, they should explain exactly what is missing and offer one direct action, rather than sending the user into a generic maintenance area.

### 2. Workspace

Purpose:
browse projects, areas, resources, and archives with enough context to decide what to open

Contents:

- searchable list grouped by section
- item badges for project type and safety posture
- detail panel with metadata, summary, local rules, linked publications, and relevant actions

Wireframe:

```text
Sidebar list                                 Detail
+--------------------------------------+    +--------------------------------------+
| Projects                             |    | Demo Story                           |
|  - Demo Story         Journalism     |    | Journalism | Active | Publishable    |
|  - Event Scanner      Tooling        |    +--------------------------------------+
| Areas                                |    | Summary                              |
|  - Food Watch         Area           |    | The first paragraph of the README... |
| Resources                            |    +--------------------------------------+
|  - Article Brain      Resource       |    | Local rules                          |
| Archives                             |    | Never overwrite raw source files...  |
|  - 2024 project X     Archive        |    +--------------------------------------+
|                                      |    | Metadata                             |
| Search: [climate______________]      |    | Path, README, AGENTS, file counts    |
+--------------------------------------+    +--------------------------------------+
                                            | Related actions                      |
                                            | [Open folder] [Open README] [Run...] |
                                            +--------------------------------------+
```

Screen contract:

- Workspace should answer “what is this folder?” before it answers “what can I run?”
- Project type, lifecycle, and safety posture should be legible at scan speed.
- This is the main trust surface for mixed reporting, tooling, archive, and resource work.

### 3. Workflows

Purpose:
run scripts safely without dropping to terminal for every task

Contents:

- workflow list by category
- parameters form
- command preview
- write-target warning
- related artifacts after run

Wireframe:

```text
+----------------------------------------------------------------------------------+
| Build project README                                                             |
| Project | writes to workspace | selection required                               |
+----------------------------------------------------------------------------------+
| Parameters                                                                       |
| selected_path: <selected_project>                                                |
+----------------------------------------------------------------------------------+
| Command preview                                                                   |
| cd <workspace_root>                                                               |
| python3 Resources/knowledge_ops/scripts/build_project_readme.py ...               |
+----------------------------------------------------------------------------------+
| Writes to: README.md                                                              |
| This workflow writes to the workspace. Confirm target paths before running.       |
+----------------------------------------------------------------------------------+
| [Run workflow]                                                [Open workspace]   |
+----------------------------------------------------------------------------------+
```

Screen contract:

- Workflows should feel explicit, inspectable, and boring in the good sense.
- Command preview and write-target visibility are more important than visual flourish.
- The screen should eventually support reproducible presets that another journalist can adopt without rewriting Swift code.

### 4. Runs

Purpose:
make recent executions inspectable and auditable

Contents:

- run metadata
- stdout and stderr
- artifact links
- rerun candidate later, not needed for first mock-up

Wireframe:

```text
+----------------------------------------------------------------------------------+
| Refresh knowledge ops                                                            |
| Started 08:01 | Finished 08:05 | Exit 1                                          |
+----------------------------------------------------------------------------------+
| Artifacts                                                                         |
| - manifest.json                                                                   |
| - stdout.txt                                                                      |
| - stderr.txt                                                                      |
+----------------------------------------------------------------------------------+
| Output                                                                            |
| STDOUT                                                                            |
| ...                                                                               |
|                                                                                    |
| STDERR                                                                            |
| ...                                                                               |
+----------------------------------------------------------------------------------+
| [Refresh output] [Open stdout] [Open stderr]                                      |
+----------------------------------------------------------------------------------+
```

Screen contract:

- Runs are for auditability and debugging, not for dashboard theater.
- Failure states should be easier to scan than success states.

### 5. Plan

Purpose:
keep roadmap and product direction visible while the app evolves

Contents:

- current priorities
- roadmap
- backlog
- architecture notes
- automation ideas

Wireframe:

```text
+----------------------------------------------------------------------------------+
| Plan center                                                                       |
| 5 docs | Journalism Workflow Hub Plan | separate from app code                    |
+----------------------------------------------------------------------------------+
| Current priorities                                                                |
| - lock the v1 product definition and screen contract                              |
| - tighten workspace classification and trust signals                              |
+----------------------------------------------------------------------------------+
| Product definition                                                                |
| JWH is a personal newsroom control surface, not a generic workspace app.          |
+----------------------------------------------------------------------------------+
| [Open doc] [Open project]                                                         |
+----------------------------------------------------------------------------------+
```

Screen contract:

- Plan should keep the product honest while the app is still fluid.
- It should show the canonical planning layer, not every supporting research artifact by default.

## Important V1 Product Decisions

- The main information architecture is operational, not document-centric.
- Workspace and workflows stay separate.
- Safety posture must be visible at list level, not only in detail.
- Command preview remains central.
- The plan stays in the product because this is still a living tool, not a finished app.
- The interface should avoid locking itself to a single private filesystem setup forever.
- Reproducibility matters even before open-source release: the product should eventually support first-run workspace creation and portable configuration.

## Missing Features To Validate With The First Mock-Up

Review the mock-up against these questions:

- Do we need a dedicated "Today" screen separate from Overview?
- Should workflows be shown inline on each workspace item by default?
- Do we need Google Docs draft visibility in v1 or can that wait?
- Is publication health important enough for Overview, or should it live only in Publication?
- Do runs need filters before we add more workflow volume?
- Should the app show git status at overview level?
- What should first-run onboarding look like when a user does not already have Jan's workspace structure?

## Fast Build Order

If turning this into a visual first pass in SwiftUI, build in this order:

1. tighten Overview so it becomes a stronger dispatch surface
2. improve Workspace trust signals and detail summaries
3. improve Workflow detail emphasis around command preview, write targets, and portable presets
4. sharpen failure visibility in Runs
5. polish Plan so it reflects the canonical planning layer cleanly

## Agent Recommendation For This App

Use one lead thread as the decision-maker. Delegate only bounded parallel work.

Good delegation targets:

- workspace classification and scanner logic
- UI implementation of one screen at a time
- test writing
- review of planning docs for stale or contradictory requirements

Bad delegation targets:

- overall product direction
- cross-cutting architecture changes touching models, scanner, store, and views at once
- final prioritization decisions

Recommended structure:

- main thread: product lead and integrator
- optional subagent 1: planning audit
- optional subagent 2: UI implementation pass
- optional subagent 3: tests and regression review

Do not create a permanent "chief of staff" agent yet. That structure pays off only when:

- multiple repos are moving at once
- handoffs become frequent
- there is ongoing autonomous work with many parallel tasks

For this project, the main thread should stay the chief of staff.
