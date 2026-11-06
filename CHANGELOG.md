# Changelog

## [2.0.0](https://github.com/swihpi/PromptFoundry/releases/tag/v2.0.0) — 2026-11-06

### Added

- **Answer & Refine:** optional answers to questions and missing information are saved in Additional Context and incorporated into an improved prompt.
- **Explicit file context:** opt in to including supported UTF-8 text, Markdown and source-file contents in a refinement request. Files remain references by default. Limits: 64 KB per file and 256 KB combined context; content selections reset when switching prompts.
- **Version comparison:** red deletions, blue additions, plain preview and restoration in the Versions window.
- **Separate V2 installation:** `PromptFoundry-V2.app` has its own identity, preferences, store and optional API-key service. A one-time read-only import copies an existing V1 library; later edits are independent.
- **Downloadable V2 DMG:** `PromptFoundry-V2-2.0.0-unsigned.dmg` is attached to this release. V1 remains available at its original release URL.

### Changed

- New dark editorial workspace with horizontal library navigation, recent prompt shortcuts, larger proportional typography, aligned text boxes and depth controls below the rough idea.
- Existing search, tags, favorites, sorting, rename, duplication, export, deletion, target/task selection, prompt depth, model options and shaping controls remain available.
- Generation uses a temporary preview and keeps the previous completed prompt saved. Copy and handoff actions are disabled while generation is in progress.
- Desktop handoff reviews the complete prompt and directory, with execution settings chosen inside Codex. Create Codex Task shows its applicable model, reasoning and file-access settings.
- Referenced local file paths are included in the complete Codex handoff review.
- Depth 5 continues to default to comprehensive coverage, with relevance taking priority over word count.

### Fixed

- Failure and cancellation preserve the previous prompt; cancelled work cannot overwrite a newly selected workspace.
- Current ChatGPT embedded CLI locations are detected and stale saved executable paths are repaired.
- App-server startup uses the CLI's default stdio transport.
- Unsupported saved refinement models fall back to an available advertised model.
- Both text boxes use matched header/control spacing and equal heights.

### Release notes and limits

- Apple Silicon; macOS 14 or later. Requires the user's own local Codex installation and authentication.
- Ad-hoc signed only; no Apple Developer ID and no notarization. Follow the per-app Gatekeeper instructions in the README.
- During V2 implementation, all 14 existing verification checks and 5 focused workflow checks passed. Live refinement, model discovery, Create Task, clarification-driven improvement, comparison and restoration were exercised.
- Application tests were not rerun for the later alignment-only adjustment or this publication. The DMG and public download are checked separately.
- Desktop handoff was accepted by macOS. Visual confirmation of the resulting draft inside Codex was unavailable because computer access to Codex was blocked. A dispatch confirmation is not a guarantee that the destination created a task.
- The original V1 DMG and release are preserved unchanged.

## 1.0.1 — 2026-10-07

Local maintenance update; no separate public DMG release was published.

- Added the newer `codex-cli/bin/codex` and nested `CodexCLI.app` locations used by ChatGPT.
- Recovered stale stored executable paths automatically.
- Installed locally as build 2 with the neutral application identifier.

## [1.0.0](https://github.com/swihpi/PromptFoundry/releases/tag/v1.0.0) — 2026-09-16

Initial public source and macOS installer release.

- Native SwiftUI/SwiftData prompt workspace with local history, versions, search and import/export.
- Rough idea to structured professional prompt using a signed-in local Codex installation by default.
- Prompt Depth 1–10, with comprehensive depth 5 as the default.
- Prompt shaping, assumptions, questions, missing information and risk disclosures.
- Codex task creation and desktop handoff review.
- Five-step first-launch assistant.
- Unsigned, unnotarized Apple Silicon DMG.

Original installer: [PromptFoundry-1.0.0-unsigned.dmg](https://github.com/swihpi/PromptFoundry/releases/download/v1.0.0/PromptFoundry-1.0.0-unsigned.dmg).

SHA-256: `378ac6370cd1e5c902dfc99d1645242269eea14ac53c3f76eccfb773744a84d9`.
