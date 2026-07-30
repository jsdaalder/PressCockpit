# Standalone Pilot Audit

Date: 2026-07-06

## Goal

Make sure `Journalism Workflow Hub` can run outside Jan's personal newsroom setup before any friend-facing distribution work starts.

## Standalone definition

- the app launches on another Mac
- the app works against a bundled demo workspace
- no required dependency remains on Jan-specific local paths
- private newsroom workflows are hidden
- the app shell still feels coherent when local Python workflows are unavailable

## Dependency classification

### Required for core app

- workspace scanning and metadata parsing
- publication index reading when present
- run history stored in Application Support
- overview, workspace, workflows, and runs UI

### Optional but portable

- Finder-based navigation workflows:
  - `open-workspace-root`
  - `open-selected-folder`

### Private or local-only

- workspace-level planning project in `Projects/2026/journalism_workflow_hub_plan/` outside this app repo
- `knowledge_ops` Python workflows
- `article_brain` workflows
- `TRACES` workflows
- dossier and event-scanner workflows

## First-pass blockers addressed

- removed the hardcoded `/Users/jandaalder/...` fallback workspace root
- made plan-center loading optional and standard-profile-only
- replaced Jan-specific scaffold defaults with generic defaults
- added workflow availability levels:
  - `portable`
  - `optional_local`
  - `private_hidden`
- added a standalone app profile that shows portable workflows only by default

## Run commands

Standard mode:

```bash
swift run JournalismWorkflowHub
```

Standalone audit mode:

```bash
swift run JournalismWorkflowHub --app-profile standalone
```
