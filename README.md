# PressCockpit

`PressCockpit` is the current product name for the macOS app in this repo.
The codebase and package name are still `JournalismWorkflowHub` for now.

PressCockpit is a lightweight, local-first desktop app for keeping journalism projects, source files, drafts, and AI-assisted document analysis in one practical workspace. It is built for reporters and editors who already work across several good tools, but do not want their project context scattered across all of them.

## The Problem

Modern reporting work often ends up split across disconnected places:

- Google Docs and Google Drive for drafts, shared notes, and source material
- downloaded PDFs on a Mac, which are easy to forget to upload back to Drive
- a project-management board in Notion or another kanban tool
- ChatGPT or Codex sessions for analyzing documents, extracting leads, summarizing material, and drafting next steps
- local folders that still contain the real project archive

Each tool is useful on its own. The friction comes from keeping the same story, documents, tasks, and analysis state aligned across all of them. Files drift between cloud storage and the local machine, project status lives somewhere else, and AI analysis often happens outside the folder where the underlying material belongs.

PressCockpit tries to fix that coordination problem without replacing the tools. The goal is not to become a new CMS, a new Drive, a new Notion, or a closed research database. The goal is to sit on top of the working folder structure and make the whole project easier to see, search, open, and act on.

## What The Project Does

PressCockpit gives a local desktop view of a reporting workspace. It helps you:

- see active reporting projects first
- open project folders, README files, drafts, source files, and document pointers quickly
- keep downloaded material visible so it does not stay stranded on the Mac
- scaffold new reporting projects with plain folders and starter files
- review project state without digging through Finder, Drive, Notion, and old chats
- run local workflows for document analysis, summaries, source review, and drafting support
- keep workflow outputs inside the project folder where the source material already lives

The app is intentionally lightweight. It makes the existing workspace easier to operate; it does not try to own the work.

## Why It Is Relevant

Journalism work depends on context: which documents belong to which story, what has been checked, what still needs follow-up, and where the source material came from. That context is easy to lose when the reporting process spans cloud documents, local downloads, kanban boards, and AI tools.

PressCockpit is relevant because it treats the folder structure as the durable layer. Google Drive, Notion, ChatGPT, Codex, Finder, and the app can all be useful interfaces, but the project files remain ordinary files that can be opened, moved, backed up, scripted, or reviewed without PressCockpit.

The public product direction is tracked in [ROADMAP.md](ROADMAP.md).

## Local-First Design

PressCockpit reads a normal workspace on disk. It works best when a reporting setup follows a simple structure such as:

- `Projects`
- `Areas`
- `Resources`
- `Archives`

The app reads that directory directly. It does not import the work into a separate app-owned database or require all work to happen through the app.

If you create a new workspace through PressCockpit, it creates plain folders and starter files you can inspect in Finder. If you stop using the app later, those files remain ordinary files on disk.

This is a core design requirement: you should still be able to work on and with every file without PressCockpit. The app is a layer on top of the local file structure, not the only way into it.

## Documents And Tools

The app works best with local files today, and is designed to coexist with:

- local PDFs, `.docx` drafts, notes, and data files
- Google Docs and Google Drive pointers
- synced folders from cloud providers
- kanban or planning systems such as Notion
- ChatGPT and Codex workflows for document analysis

This keeps the workflow flexible. You can keep using the tools that already work, while PressCockpit helps connect their outputs back to the project folder.

## Privacy And Storage

Your workspace stays in the selected local folder. The app reads local files and only writes where a workflow says it will write.

The app also keeps some lightweight local state on your Mac, such as:

- workspace selection
- cached catalog state
- workflow run logs
- write backups

If you use Google Docs or another sync tool, that provider keeps its own network and storage behavior.

## For A First Test

The easiest way to try PressCockpit is:

1. Open the app.
2. Choose the demo workspace if you just want to explore safely.
3. Choose an existing workspace if you want the app to read your real reporting folders.
4. Create a new workspace only if you actually want a separate reporting root.

The demo workspace is bundled with the app. It opens in standalone mode and hides local-only newsroom workflows by default.

## Current Alpha State

This is still an alpha tool.

What already works well:

- browsing a reporting workspace
- seeing active projects
- scaffolding a new project
- creating a local draft from inside the app
- running local workflows through the app shell

What is still rough:

- some advanced workflows still depend on local tooling
- Google Docs support is useful but still partial
- packaging and distribution are workable, not polished

## Run The App

From this folder:

```bash
scripts/swiftpm-local.sh run JournalismWorkflowHub
```

By default the app tries to discover the workspace root by walking up from the current directory until it finds a folder that looks like a journalism workspace.

You can also point it at a workspace directly:

```bash
scripts/swiftpm-local.sh run JournalismWorkflowHub --workspace-root "/path/to/coding_projects"
```

Or use an environment variable:

```bash
JWH_WORKSPACE_ROOT="/path/to/coding_projects" scripts/swiftpm-local.sh run JournalismWorkflowHub
```

## Why The Wrapper Script Exists

This repo currently lives under `My Drive`, so `scripts/swiftpm-local.sh` keeps SwiftPM's build database out of the synced folder. Plain `swift run` and `swift test` can hit transient `.build/build.db` disk I/O errors there.

## Run Tests

```bash
scripts/swiftpm-local.sh test --filter AppStoreNavigationTests
```

## Build A Shareable Mac App

To build a zipped macOS app bundle for alpha testers:

```bash
scripts/build-macos-release.sh --version 0.2.3
```

This creates:

- `dist/PressCockpit-0.2.3.app`
- `dist/PressCockpit-macOS-0.2.3.zip`
- `dist/PressCockpit-macOS-0.2.3.zip.sha256`

The packaged app defaults to standalone mode so testers can open the bundled demo workspace without your private newsroom setup.
These `dist/` outputs are local build artifacts and stay out of the git repo; the shareable zip and checksum should be published through GitHub Releases instead.

You can also change the default launch profile:

```bash
scripts/build-macos-release.sh --version 0.2.3 --profile standard
```

## Release Tag

Tagged pushes like `v0.2.3` trigger `.github/workflows/macos-release.yml`, which rebuilds the app on GitHub Actions and attaches the versioned zip and checksum to the GitHub Release.

Example:

```bash
git tag v0.2.3
git push origin v0.2.3
```

## Standalone Mode

Run the app in a local standalone profile without depending on your full newsroom workspace:

```bash
scripts/swiftpm-local.sh run JournalismWorkflowHub --app-profile standalone
```

This profile:

- uses the bundled demo workspace by default
- hides local-only and private workflows
- removes the requirement that the private planning project exists

You can still point standalone mode at another workspace explicitly:

```bash
scripts/swiftpm-local.sh run JournalismWorkflowHub --app-profile standalone --workspace-root "/path/to/other/workspace"
```

## Custom Workflow Presets

You can add JSON workflow presets to one of these locations:

- `Resources/Overig/journalism_workflow_hub/workflows.json`
- `~/Library/Application Support/JournalismWorkflowHub/workflows.json`

Each preset can define a shell command template with workspace tokens such as `{{workspace_root}}` and `{{selected_path}}`.

Presets can also set `availability` to:

- `portable`
- `optional_local`
- `private_hidden`

## Planning

The full product plan for this app lives in the workspace-level `Projects/2026/journalism_workflow_hub_plan/` project in the private newsroom workspace, outside this app repo.

The repo-local `Projects/2026/journalism_workflow_hub_plan/` folder is only an archived pointer copy kept for older references.

In standalone mode, the app does not require that planning project to exist.
