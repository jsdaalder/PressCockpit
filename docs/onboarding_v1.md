# Onboarding V1

Date: 2026-07-06

## Goal

Add a first-run launch experience that makes the app legible to a new user, helps them choose the right workspace setup path, and prevents the main shell from appearing before the app is actually ready.

## Launch structure

### 1. Splash screen

- show app name and one short status line
- keep it functional rather than decorative
- use it to cover launch-state resolution before the main UI appears

Primary status copy:

- `Loading workspace and launch state…`
- `Opening demo workspace…`

### 2. Onboarding flow

The onboarding should ask one meaningful question per screen.

#### Screen 1. Welcome

- explain that the app is local-first
- explain that it reads workspace folders such as `Projects`, `Areas`, `Resources`, and `Archives`
- explain that some advanced workflows still depend on local tooling

#### Screen 2. Start mode

Choices:

- `Try demo workspace`
- `Use existing workspace`
- `Create new workspace`

This is the key branching decision for the whole flow.

#### Screen 3. Document mode

Choices:

- `Local files only`
- `Google Docs pointers too`
- `Other sync setup`

Important product stance:

- local files are fully supported
- Google Doc pointers are partially supported
- Nextcloud, Proton Drive, and similar setups can work through local sync folders, but do not have first-class integration yet

#### Screen 4. Workspace location

Behavior depends on start mode:

- `demo`: show the bundled demo path
- `existing`: choose the current workspace root
- `create`: choose where the new workspace should be created

Default for new workspace:

- `~/Desktop/JournalismWorkflowHub/`

#### Screen 5. Workspace setup

Behavior depends on start mode:

- `demo`: explain that the sample workspace is already prepared
- `existing`: validate the required root folders
- `create`: ask permission to create the base structure

Base structure:

- `Projects`
- `Areas`
- `Resources`
- `Archives`
- root `README.md`
- root `AGENTS.md`

#### Screen 6. Finish

- summarize the selected mode, workspace, and document setup
- show a capability check in plain language
- ask what should happen first

Initial first-action choices:

- `Open workspace overview`
- `Inspect first project`
- `Start a new project`

`Start a new project` should only appear when the selected profile keeps the scaffold workflow available.
That action should open the dedicated guided flow described in `docs/scaffold_project_wizard_v1.md`.

## Implementation notes

- onboarding appears only when the user has not completed setup yet
- the app should persist onboarding completion and the selected startup profile
- selecting the demo workspace should switch the app into standalone mode
- selecting an existing or new workspace should switch the app into standard mode
- the main shell should not appear before splash and onboarding are resolved
