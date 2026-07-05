# Journalism Workflow Hub

Native SwiftUI launcher for the workspace in `/Users/jandaalder/My Drive/coding_projects`.

## What it does

- Scans `Projects/`, `Areas/`, `Resources/`, and `Archives/`
- Reads project README metadata and local publication trackers
- Launches the existing Python workflows from a single macOS interface
- Stores run history and logs locally in Application Support
- Lets you add custom command presets without changing Swift code

## Run

From this folder:

```bash
swift run JournalismWorkflowHub
```

## Custom presets

Add JSON presets to one of these locations:

- `Resources/Overig/journalism_workflow_hub/workflows.json`
- `~/Library/Application Support/JournalismWorkflowHub/workflows.json`

Each preset can define a shell command template with workspace tokens like `{{workspace_root}}` and `{{selected_path}}`.

## Planning

The product plan for this app lives in `Projects/2026/journalism_workflow_hub_plan/`.
That folder is the source of truth for roadmap, backlog, architecture decisions, and automation ideas.
