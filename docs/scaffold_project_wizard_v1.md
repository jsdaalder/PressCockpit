# Scaffold Project Wizard V1

Date: 2026-07-08

## Goal

Replace the current flat scaffold form with a Typeform-esque guided flow that:

- reduces first-run clutter
- asks only for information the user can answer immediately
- derives internal scaffold fields instead of exposing them
- establishes a reusable question-flow pattern for other guided features

This spec is for the `Scaffold project` workflow first, but the interaction model should be portable.

## Product stance

The project scaffold flow is not a metadata editor.
It is a guided intake flow for creating a real project folder with enough context to start work safely.

The flow should optimize for:

- momentum over completeness
- one meaningful decision per screen
- plain language over system language
- deferring optional structure until after creation
- keeping filesystem and workflow details inspectable at the end, not dominant at the start

## Reusable Question-Flow Pattern

Use these rules for future Typeform-esque flows in the app:

### 1. Ask one thing per screen

- one primary question
- one primary input mode
- short supporting explanation only if needed

Do not stack operational fields on the same screen just because they fit visually.

### 2. Branch only when the branch changes the next decision

Good branch:

- `Do you already have a pitch?`

If `yes`, offer pitch-specific follow-up.
If `no`, ask for a short description instead.

Bad branch:

- asking advanced metadata only because one answer technically allows it

### 3. Derive internal fields by default

Do not ask the user for system-facing values when the app can infer them safely.

Examples:

- `project_root` from year + slugified title + workspace conventions
- `owner` from current profile or system user
- `started` from today
- `status` from workflow default

### 4. Defer optional complexity

If a decision is useful but not necessary to create the project, move it to:

- a review screen
- an advanced details drawer
- a post-create next step

### 5. End with a confirmation screen, not a blank form tail

The final screen should summarize:

- what will be created
- where it will be created
- what content will be seeded
- what the next action will be

## What The Wizard Should Not Ask Up Front

These should not appear as first-pass questions:

- project root path
- owner
- status
- started date
- topics
- entities

Reasons:

- they are implementation details or internal metadata
- they slow down creation
- most can be inferred or captured later with better context

## Core Flow

Target length:

- 5 to 7 screens
- 2 minutes or less for a normal case

### Screen 1. Working title

Question:

- `What is the working title of this project?`

Input:

- single-line text field

Purpose:

- gives the user an immediate start
- becomes the human-facing title
- seeds the folder slug preview later

Behavior:

- enable continue only when non-empty
- do not show the filesystem path yet

### Screen 2. Project kind

Question:

- `What kind of project is this?`

Choices:

- `Journalism`
- `Data journalism`
- `Private coding project`
- `Other`

Purpose:

- determines lifecycle defaults
- informs folder templates and later guidance
- is more useful than exposing raw `status`

Notes:

- if `Other`, optionally reveal a short free-text label on the same screen or on review

### Screen 3. Starting point

Question:

- `Do you already have a pitch or brief?`

Choices:

- `Yes, I have one`
- `No, not yet`

Purpose:

- determines whether the app should ask for existing source text or a fresh summary

### Screen 4A. Pitch input

Show only if Screen 3 is `Yes`.

Question:

- `Paste the pitch or brief`

Input:

- multiline text area

Secondary option:

- `Skip for now`

Purpose:

- stores the pitch for the project
- creates a base for a later LLM summary feature

Future feature note:

- later this screen can offer `Use this to generate a short project summary`
- do not block V1 on that feature

### Screen 4B. Project summary

Show only if Screen 3 is `No`, or after Screen 4A if the pitch was skipped.

Question:

- `What is this project about?`

Prompt:

- `Describe it in 2 to 4 sentences.`

Input:

- multiline text area

Purpose:

- gives the scaffold enough context to seed the README
- avoids forcing topics and entities too early

### Screen 5. Source material

Question:

- `Do you want to add source material now?`

Choices:

- `Yes, add documents now`
- `Not now`

Examples in helper copy:

- papers
- newspaper stories
- interview transcripts
- notes

Purpose:

- captures timing preference without forcing upload into the middle of the intake flow

Behavior:

- if `Yes`, the wizard should finish project creation first, then move into a post-create import step
- do not open a file picker before the project exists

### Screen 6. Priority

Question:

- `How urgent is this project?`

Choices:

- `Low`
- `Normal`
- `High`

Optional future extension:

- replace or supplement with a deadline field if editorial planning needs more specificity

Purpose:

- keeps the signal coarse and fast
- supports future sorting and overview prioritization

## Final Screen

### Screen 7. Review and create

Purpose:

- confirm what the wizard inferred
- give the user one chance to correct important details
- keep advanced values visible but secondary

Show:

- title
- project kind
- pitch present or summary present
- source material timing
- priority
- derived location

Derived location copy example:

- `This project will be created at Projects/2026/<slug>.`

Advanced details section:

- editable folder name
- editable root path only if necessary
- optional fields such as topics and entities

Primary action:

- `Create project`

Secondary action:

- `Back`

## Data Mapping To Current Scaffold Workflow

The wizard should map onto the existing scaffold command rather than requiring a new backend contract immediately.

Current workflow fields:

- `project_root`
- `title`
- `owner`
- `status`
- `started`
- `deliverable`
- `topics`
- `entities`

Recommended mapping:

- `title` ← Screen 1 working title
- `project_root` ← derived from workspace root + year + slug
- `owner` ← current user or active profile default
- `status` ← `active`
- `started` ← current date in `YYYY-MM-DD`
- `deliverable` ← summary or pitch-derived short description
- `topics` ← leave empty in V1 unless captured later
- `entities` ← leave empty in V1 unless captured later

Implication:

- the guided flow can ship before the Python scaffold script changes
- the first implementation can remain a frontend orchestration layer over the existing workflow

## Post-Create Next Steps

After successful creation, route to one next action instead of dropping the user into a generic detail screen.

If source material choice was `Yes`:

- open a document import step targeted at the new project

If source material choice was `Not now`:

- offer `Open project`
- offer `Open README`
- offer `Add documents`

## Copy And Tone

The wizard should sound:

- calm
- editorial
- explicit
- non-technical

Avoid copy like:

- `parameter`
- `artifact`
- `workflow state`
- `selection requirement`

Prefer copy like:

- `project`
- `summary`
- `source material`
- `where it will be created`

## Screen Contract

The scaffold wizard is successful if:

- a first-time user can create a project without understanding the workspace internals
- the app asks fewer questions than the current flat form
- the derived defaults are usually correct
- the user sees path and write information before creation, not only after it
- the same interaction pattern can be reused for other guided flows

The wizard is failing if:

- it becomes another long settings form
- it asks for metadata that is not needed to create the project
- file upload interrupts the intake before the project exists
- advanced fields dominate the main path

## Implementation Notes

- implement this as a dedicated scaffold wizard, not a special case inside the generic parameter form
- keep the existing workflow runner and scaffold script as the execution backend for V1
- persist draft state while the wizard is open so a partial answer is not lost
- keep the review screen inspectable and auditable
- if this pattern works, future candidates include guided document import, archive intake, and publish handoff
