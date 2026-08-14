# Changelog

All notable changes to Agents Notch will be documented in this file. The format
follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and releases
use [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Changed

- Repository conventions now describe the allowed disk walks: hooks stay
  push-only, while titles, hierarchy, and cold-start evidence may read
  provider-owned files. The Codex approval bridge is documented as a
  fail-open 4 MiB transcript-tail read, not a general parser.
- Dropped the unused `AgentProviderAdapter` / `HookProviderAdapter` layer.
  `AppRuntime` now talks to `ProviderIntegrationManager` directly.
- Restored session history is rewritten to always-prefixed
  `provider:nativeId` identities on load, then persisted. Live ingest no
  longer remaps bare IDs.
- The package now uses Swift 6 language mode on every target.

### Fixed

- Activity Center no longer draws a system focus ring around the session
  list after a row is selected. Keyboard navigation is unchanged.
- Duplicate Claude-compatibility hooks under Grok no longer write `{}` to
  stdout. The relay stays silent for Claude, matching observer-only rules.
- Activity Center timeline titles ignore whitespace-only tool metadata.
- Claude Code observers now follow the documented hook schema: exec-form
  `command`/`args` and asynchronous handlers that cannot block or control
  permission, elicitation, AskUserQuestion, or ExitPlanMode behavior, plus the
  missing `PermissionDenied`, `Elicitation`, and `ElicitationResult` events.
  AskUserQuestion and ExitPlanMode surface as waiting. Existing installs are
  upgraded on launch.

## [0.1.1] - 2026-08-13

### Changed

- Notch hover list leads with the task and project instead of the provider name.
  Subagent roles use a compact capsule. Activity Center and Settings sit on
  their own chrome row so they no longer cover the first session.
- Prompt titles unwrap Grok `<user_query>` wrappers so the tag is not shown as
  the session task.
- Image-only follow-ups no longer replace a real session title. Grok's
  generated title is used when the prompt is just a wrapper or attachment.
  Codex memory-writer sessions stay out of the notch list.
- Codex rows use the thread title from `session_index.jsonl` instead of the
  last user message.

## [0.1.0] - 2026-08-11

### Added

- Native notch-attached status UI for local coding-agent activity.
- Observer-only lifecycle hook integrations for Codex, Claude Code, and Grok.
- Provider-neutral local event protocol over a private Unix socket.
- Structured plan, workflow, and subagent progress rendering.
- Reproducible CI and signed/notarized release packaging workflows.
- Activity Center with searchable, filterable local session history and
  detailed plans, workflows, relationships, files, and events.
- First-run setup, integration health checks, and menu-bar access for displays
  without a hardware notch.
- Observer-only Gemini CLI integration using its official lifecycle hooks.
- Observer-only OpenCode plugin and Cursor lifecycle-hook integrations.
- Optional actionable macOS notifications for waiting and failed agents.
- Source-application handoff using optional terminal and application origin
  metadata captured by the local relay.
- Configurable history retention, virtual-notch support, pointer-display
  following, and GitHub release checks.

### Changed

- Cold start no longer forces restored running sessions to completed. Dead
  origin processes complete immediately; other runners enter a short
  reconnecting (`unknown`) grace period until a live hook arrives.
- Multiple waiting sessions now form an explicit attention queue while routine
  activity remains collapsed.
- Parent rows surface waiting or failed descendant state.
- Settings window matches Activity Center chrome: resizable, minimizable, and
  pure-black transparent title bar with frame restoration.
- Settings controls use T3-style rows: title + detail, switch toggles, and
  compact dark pill buttons/pickers.
- Setup/onboarding window uses the same pure-black deep surface as Settings
  and Activity Center.
- Settings dropdowns use a T3-style dark pill trigger and solid borderless
  floating menu (no speech-bubble popover) with selected-row highlight.
