# Changelog

All notable changes to Agents Notch will be documented in this file. The format
follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and releases
use [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

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
