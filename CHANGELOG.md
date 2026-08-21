# Changelog

All notable changes to Agent Notch will be documented in this file. The format
follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and releases
use [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- "Answer from the notch" lets users answer Codex and Claude Code permission
  prompts with Deny, Allow, or a listed option. The setting is off by default.
  Grok, Gemini, Cursor, and OpenCode remain display-only. Privacy mode hides
  the prompt and disables its buttons.
- Session detail can reopen a Codex desktop thread or open another provider
  session or IDE separately from the captured terminal. Terminal.app and iTerm2
  also focus the recorded tab when the relay has a TTY or session id. Finder
  still reveals the working directory when no app, session, or terminal
  destination exists for another provider. Internal Codex helper sessions do
  not expose a dead open action.
- Homebrew cask install from this repository:
  `brew tap Aforno/agentnotch https://github.com/Aforno/AgentNotch` then
  `brew install --cask aforno/agentnotch/agent-notch`.

### Changed

- The product name is now "Agent Notch" (was "Agents Notch"). This rename is
  breaking for existing installs: the bundle identifier
  (`com.afonsoferreira.AgentNotch`), the local socket directory
  (`~/.agentnotch`), the relay binary (`~/.agentnotch/bin/agentnotch-hook`),
  the Grok hook file (`~/.grok/hooks/agentnotch.json`), the OpenCode plugin
  (`~/.config/opencode/plugins/agentnotch.js`), and the Homebrew cask token
  (`agent-notch`) all change. Reinstall hooks from the app and reinstall via
  `brew install --cask aforno/agentnotch/agent-notch`. Session history moves
  to `~/Library/Application Support/AgentNotch`.
- Collapsed notch provider icons drop the hairline ring. Stacked marks still
  sit on a black circle.
- Expanded notch width follows the active display. Thread detail sizes to its
  content and stays on screen. Inset controls and separators follow the outer
  notch curve.
- Removed the menu-bar extra. Open Activity Center from the notch, Command-1,
  or the global activity shortcut, and quit from Settings or Activity Center.
- Hook install is split by config shape (grouped, Cursor, OpenCode). Handler
  identity is one `{none, legacy, current}` matcher, and timeouts are named
  seconds or milliseconds (`IntegratedHookProvider` requires a unit per
  provider).
- Mapper stays a `HookEventName` switch. Skip, tool copy, and plan/goal
  snapshots live in `ProviderEventPolicy`. The hook process decodes, enriches,
  maps, and exits; Grok/Codex disk walks sit behind `ProviderHookEnricher`.
- Live events keep the session ID the mapper already namespaced. Restore still
  prefixes leftover bare history IDs, then persists. Ingest rebuilds
  `SessionIndex` once.
- Dropped `AGENTS.md`. Contributor conventions live in `CONTRIBUTING.md`.
- Repository conventions now describe the allowed disk walks: hooks stay
  push-only, while titles, hierarchy, and cold-start evidence may read
  provider-owned files. The Codex approval bridge is documented as a
  fail-open 4 MiB transcript-tail read, not a general parser.
- Dropped the unused `AgentProviderAdapter` / `HookProviderAdapter` layer.
  `AppRuntime` now talks to `ProviderIntegrationManager` directly.
- The package now uses Swift 6 language mode on every target.

### Fixed

- Provider icons with uneven SVG padding (Codex versus Grok) now share a
  vertical center in the collapsed notch.
- Final session-history writes on quit now supersede older saves already in
  flight, preserving the latest agent events.
- Restored approval rows complete when their recorded provider process is gone
  or its PID was recycled, so stale attention cannot keep the notch expanded
  after relaunch.
- Codex title enrichment now reads at most the last 4 MiB of
  `session_index.jsonl`, keeping short-lived hooks responsive as history grows.
- Session links accept only provider-owned HTTPS destinations, origin Open
  ignores a recycled PID, and update downloads always open the fixed official
  GitHub release page instead of a response-provided URL.
- Codex Open in Codex uses the parent thread ID for children, and keeps official
  title evidence after restore and later activity so helper ULIDs stay hidden.
- Clicking outside a selected notch thread now collapses the notch instead of
  leaving detail pinned until Back.
- The notch thread Back control uses the same 28-point hit target as the hover
  list chrome, so the chevron is no longer the only clickable pixels.
- Activity Center and Settings controls in the expanded notch now align with
  the macOS menu bar without reserving an empty row above the first agent.
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
