# Overview Focus Spec

Date: 2026-07-31

## Purpose

Define one clear rule for the top and secondary project sections on `Workspace Overview`.

The goal is to stop duplicating projects across both lists and to separate:

- project state
- workflow stage
- current daily attention

## Canonical Model

`activity_state`

- answers whether the project is still live work

`workflow_stage`

- answers where the project sits in the reporting process

`daily_focus`

- answers whether the project should stay in the top section right now

`daily_focus` is a binary editorial attention marker.
It is not a generic favorite flag and it is not a replacement for project state.

## Trusted Metadata

Project `README.md` frontmatter may include:

```yaml
daily_focus: true
```

Rules:

- absence means `false`
- only `true` should be written explicitly
- turning focus off should remove the field rather than writing `false`

## Overview Rules

Top section:

- label: `Focus Stories`
- includes only active reporting projects with `daily_focus: true`
- projects appear once only

Second section:

- label: `Other Active Projects`
- includes active reporting projects without `daily_focus: true`
- grouped by workflow stage
- excludes every project already shown in `Focus Stories`

Excluded from both sections:

- finished projects
- archived projects
- inactive reporting projects
- non-reporting project types such as tooling

## Interaction Rules

- the overview row should provide a direct star toggle
- starring a project adds it to `Focus Stories`
- unstarring a project moves it to `Other Active Projects`
- project state editing may also expose the same `daily_focus` control

## Copy Rules

- describe the star as `daily focus`, not `favorite`
- top-section empty state should teach the model:
  `Star the projects you are working on every day to keep them in the top section.`

## Notes

This local repo note matches the current implementation.
The canonical planning spec remains the workspace-level planning project outside this writable repo.
