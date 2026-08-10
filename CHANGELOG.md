# Changelog

All notable changes to Agents Notch will be documented in this file. The format
follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and releases
use [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- Activity Center with searchable, filterable local session history and
  detailed plans, workflows, relationships, files, and events.
- First-run setup, integration health checks, and menu-bar access for displays
  without a hardware notch.
- Observer-only Gemini CLI integration using its official lifecycle hooks.
- Optional actionable macOS notifications for waiting and failed agents.
- Source-application handoff using optional terminal and application origin
  metadata captured by the local relay.
- Configurable history retention, virtual-notch support, pointer-display
  following, and GitHub release checks.

### Changed

- Multiple waiting sessions now form an explicit attention queue while routine
  activity remains collapsed.
- Parent rows surface waiting or failed descendant state.
- Settings window matches Activity Center chrome: resizable, minimizable, and
  pure-black transparent title bar with frame restoration.
- Notch agent rows and attention peeks show the chat/task name instead of only
  the provider label (provider remains identified by its icon).

## [0.1.0] - 2026-08-08

### Added

- Native notch-attached status UI for local coding-agent activity.
- Observer-only lifecycle hook integrations for Codex, Claude Code, and Grok.
- Provider-neutral local event protocol over a private Unix socket.
- Structured plan, workflow, and subagent progress rendering.
- Reproducible CI and signed/notarized release packaging workflows.
