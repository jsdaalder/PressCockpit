# Roadmap

This roadmap describes the public product direction for PressCockpit. It is a cleaned-up version of the working plan used during development, focused on what the app is trying to become rather than private implementation notes.

The roadmap is directional. Priorities may change as the app is tested on real reporting projects.

## Product Direction

PressCockpit is being built as a lightweight desktop layer on top of a local reporting workspace. The core principle is that the project folder remains the durable source of truth: documents, notes, workflow outputs, and project metadata should stay usable from Finder, Google Drive, editors, scripts, and AI tools even when PressCockpit is not open.

The app is meant to connect the tools already used in reporting work:

- local folders for project structure and archives
- Google Docs and Google Drive for shared drafts and source material
- downloaded PDFs and other local source files
- kanban-style planning systems such as Notion
- ChatGPT and Codex workflows for document analysis and drafting support

It should make those pieces easier to coordinate without becoming a closed CMS or a replacement for the underlying tools.

## Already Working

The current alpha already supports the basic local-first workspace model:

- browsing a reporting workspace on disk
- showing active projects and project state
- opening folders, drafts, README files, and project material quickly
- scaffolding new projects with plain folders and starter files
- creating a local draft during project setup
- adding documents during scaffold and project workflows
- capturing incoming material and assigning it to projects
- creating lightweight placeholder projects from captured material
- running local workflows through the app shell
- keeping workflow runs inspectable through local run history
- using a bundled demo workspace for safer testing

These pieces are still alpha-quality, but they define the shape of the product.

## Current Focus

The current milestone is about making the app useful for daily newsroom work before expanding scope. The main focus areas are:

- tighten new-project setup so a project can be linked to a broader dossier or investigation from the start
- make Capture clearer after file upload, assignment, and placeholder-project creation
- improve follow-up paths for material that is captured now but needs attention later
- keep downloaded or externally added files visible when they belong in a project folder
- make project state, draft ownership, dossier links, and other trust signals read consistently across screens
- keep backend and workflow changes narrow, inspectable, and tied to visible user value

The priority is trust and coordination, not feature volume.

## Next

Once the daily utility baseline is steadier, the next planned work is to broaden the app from project browsing into more useful investigation support:

- build a bounded investigation workbench for selected source sets, named analysis passes, and review-before-save outputs
- evolve the current project and publication metadata into a rebuildable investigation index
- make the local catalog the query layer for Overview, project pages, and later search
- use dossier-scoped retrieval so related projects can share context without mixing unrelated stories
- decide whether operational follow-up needs a dedicated surface separate from Overview and Capture
- refine the Overview project desk into a more board-like view if it genuinely helps daily work

This work should still preserve the local-first rule: generated analysis and indexes should point back to ordinary project files and stay auditable.

## Later

Longer-term candidates include:

- better Google Docs and Google Drive integration, including explicit promotion paths from local drafts to provider-native documents
- stronger local search across previous projects, saved source files, and investigation material
- richer previews for PDFs, drafts, and generated artifacts
- more data-driven workflow definitions so project-specific behavior does not accumulate in app code
- safer background scanning and refresh behavior for larger workspaces
- optional reminders or digests for stale projects, captured material, and follow-up work
- a more complete dossier knowledge graph once the investigation index has proven useful
- clearer product identity, packaging, and distribution for testers

These are not first-wave promises. They are areas to revisit once the core workflow is reliable.

## Non-Goals For Now

PressCockpit is not currently trying to become:

- a generic project-management platform
- a full automation builder
- a replacement for Google Drive, Google Docs, Notion, Finder, ChatGPT, or Codex
- a cloud-only research database
- a full semantic search engine across the entire archive
- a system that locks project files behind the app

The app should make reporting work easier to operate, while leaving the underlying files and tools independent.
