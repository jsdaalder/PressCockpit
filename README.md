# Journalism Workflow Hub

Native SwiftUI launcher for a local journalism workspace.

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

By default the app will try to discover the workspace root by walking up from the current directory until it finds a folder that looks like a journalism workspace.

You can override that explicitly:

```bash
swift run JournalismWorkflowHub --workspace-root "/path/to/coding_projects"
```

You can also set an environment variable:

```bash
JWH_WORKSPACE_ROOT="/path/to/coding_projects" swift run JournalismWorkflowHub
```

## Standalone audit mode

Run the app in a local standalone profile without depending on your full newsroom workspace:

```bash
swift run JournalismWorkflowHub --app-profile standalone
```

This profile:

- uses the bundled demo workspace by default
- hides local-only and private workflows
- removes the requirement that the private planning project exists

You can still point standalone mode at another workspace explicitly:

```bash
swift run JournalismWorkflowHub --app-profile standalone --workspace-root "/path/to/other/workspace"
```

## Custom presets

Add JSON presets to one of these locations:

- `Resources/Overig/journalism_workflow_hub/workflows.json`
- `~/Library/Application Support/JournalismWorkflowHub/workflows.json`

Each preset can define a shell command template with workspace tokens like `{{workspace_root}}` and `{{selected_path}}`.
Presets can also set `availability` to `portable`, `optional_local`, or `private_hidden`.

## Planning

The full product plan for this app lives in `Projects/2026/journalism_workflow_hub_plan/` in the private newsroom workspace.
In standalone mode, the app does not require that planning project to exist.
