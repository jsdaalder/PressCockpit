# PressCockpit

`PressCockpit` is the current product name for the macOS app in this repo.  
The codebase and package name are still `JournalismWorkflowHub` for now.

PressCockpit is a local-first app for journalists who organize reporting work in ordinary folders.

It gives you a trustworthy view over your real workspace, helps you see what is active, open the right project fast, and run local workflows with clear write boundaries. It is not a parallel CMS or a hidden cloud system.

## What It Helps With

- See active reporting projects first
- Open project folders, README files, drafts, and docs quickly
- Create a new project scaffold and a usable first draft
- Review project state without digging through Finder
- Capture incoming material and route it into the right project
- Run local workflows from one app instead of from scattered terminal commands

## How It Works

PressCockpit reads a normal workspace on disk. It works best when your reporting setup follows a simple folder structure such as:

- `Projects`
- `Areas`
- `Resources`
- `Archives`

The app reads that directory directly. It does not import your work into a separate app-owned database.

If you create a new workspace through the app, it creates plain folders and starter files you can inspect in Finder. If you stop using the app later, those files remain ordinary files on disk.

## Documents

The app works best with local files today.

It can also work with:

- local `.docx` drafts
- Google Doc pointers
- other tools that sync documents into a local folder

This does not lock you into one provider. The app works over your local directory, and you can change document setup later without moving your workspace into a proprietary system.

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
scripts/build-macos-release.sh --version 0.2.2
```

This creates:

- `dist/PressCockpit-0.2.2.app`
- `dist/PressCockpit-macOS-0.2.2.zip`
- `dist/PressCockpit-macOS-0.2.2.zip.sha256`

The packaged app defaults to standalone mode so testers can open the bundled demo workspace without your private newsroom setup.
These `dist/` outputs are local build artifacts and stay out of the git repo; the shareable zip and checksum should be published through GitHub Releases instead.

You can also change the default launch profile:

```bash
scripts/build-macos-release.sh --version 0.2.2 --profile standard
```

## Release Tag

Tagged pushes like `v0.2.2` trigger `.github/workflows/macos-release.yml`, which rebuilds the app on GitHub Actions and attaches the versioned zip and checksum to the GitHub Release.

Example:

```bash
git tag v0.2.2
git push origin v0.2.2
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
