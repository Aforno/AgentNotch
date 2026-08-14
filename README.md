# Agents Notch

Agents Notch is a native macOS status surface for autonomous coding agents. It
attaches to the physical MacBook notch, expands on hover or when an agent needs
input, keeps attention states visible, and stays out of the Dock. Routine tool
calls, file edits, and completions stay collapsed.

> **Project status:** pre-1.0 public beta. The local protocol is versioned, but
> UI details and provider lifecycle mappings may still evolve before 1.0.

Built-in integrations support Codex, Claude Code, Grok, Gemini CLI, OpenCode,
and Cursor. The UI is provider-neutral: every integration ultimately sends the
same `AgentEvent` values to the local socket.

## Install

Requirements: Apple Silicon Mac and macOS 14 or later.

When release assets are available, download the ZIP and matching `.sha256` file
from the [GitHub releases page](../../releases), then verify it before opening
the app:

```sh
shasum -a 256 -c Agents-Notch-*-macOS-arm64.zip.sha256
```

Unzip the archive, move **Agents Notch.app** to `/Applications`, and open it.
Production binary releases are Developer ID signed and notarized by Apple.
Unsigned previews are explicitly marked as prereleases and may trigger a
Gatekeeper warning; Control-click the app, choose **Open**, and review the
prompt before continuing.

## Develop from source

Source builds additionally require Swift 6.

```sh
./script/build_and_run.sh --verify
```

This builds both executables in the debug configuration, stages an ad-hoc signed
`dist/Agents Notch.app`, embeds the shared hook relay, launches the app bundle,
and verifies that both its process and private event socket stay available. The
Codex desktop Run action is wired to the same script.

On first launch, the setup window can install and test each provider observer.
Afterward, use the menu-bar item or press Command-1 to open Activity Center.
Hover the notch until it fully expands to see the last three updated sessions.

In **debug builds only**, open **Settings → Debug → Enable debug simulator** to
simulate single states, plan progress, workflow steps, subagent hierarchies, or
concurrent providers. Simulated sessions are never persisted; disabling the
simulator cancels its running demo and removes all simulated statuses while
leaving real provider sessions untouched. Release builds omit the simulator,
the Debug settings tab, and related wiring.

## Provider integrations

Open **Settings → Integrations** and install Codex, Claude, Grok, Gemini,
OpenCode, Cursor, or any combination of them. Agents Notch:

1. copies its small relay to `~/.agentsnotch/bin/agentsnotch-hook`;
2. installs an observer-only hook or plugin through the provider's supported
   extension point without replacing existing integrations;
3. listens on `~/.agentsnotch/agent.sock` with directory mode `0700` and socket
   mode `0600`.

The configuration locations are `~/.codex/hooks.json` for Codex,
`~/.claude/settings.json` for Claude Code,
`~/.grok/hooks/agentsnotch.json` for Grok, and `~/.gemini/settings.json` for
Gemini CLI. Cursor uses `~/.cursor/hooks.json`. OpenCode loads the generated
`~/.config/opencode/plugins/agentsnotch.js` bridge. Open `/hooks` in providers
that expose that command to inspect the installed entries; Codex also requires
new command hooks to be trusted. The observers do not return a decision,
inject context, or block a tool. The relay always exits successfully, even
when Agents Notch is not running.

The adapters use each provider's documented session, prompt, tool, permission,
notification, and stop lifecycle events. Claude Code observers use the
documented exec-form `args` array with asynchronous command handlers, so they
cannot block or control permission, elicitation, AskUserQuestion, or
ExitPlanMode behavior. The relay accepts the snake_case
payload used by Codex, Claude Code, Gemini CLI, and Cursor as well as Grok's
camelCase payload. The OpenCode bridge converts plugin events to that same
observer payload. It deliberately does not parse provider transcripts. Tools
that do not pass through a provider's local hook path cannot currently be
shown as fine-grained activity.

Cursor's current hook API does not expose a passive event for its native
approval prompt. Cursor session, prompt, tool, failure, and completion activity
is available, but its own approval dialog cannot trigger notch attention.

Grok sessions become visible on their first agent-turn event. Grok also emits a
`SessionStart` event for lifecycle-only CLI invocations such as version probes,
which the app intentionally ignores because no agent task has begun.

- [Codex hooks documentation](https://learn.chatgpt.com/docs/hooks)
- [Codex configuration reference](https://learn.chatgpt.com/docs/config-file/config-reference)
- [Claude Code hooks reference](https://code.claude.com/docs/en/hooks)
- [Grok hooks reference](https://docs.x.ai/build/features/hooks)
- [Gemini CLI hooks reference](https://geminicli.com/docs/hooks/reference/)
- [OpenCode plugins reference](https://opencode.ai/docs/plugins/)
- [Cursor hooks reference](https://cursor.com/docs/hooks)

## Activity and attention

The notch remains quiet for routine activity and expands automatically only
when an agent is waiting for a permission or answer. Multiple waiting sessions
form an attention queue. Optional macOS notifications provide an **Open
Session** action, while the menu-bar item remains available on displays without
a hardware notch.

Activity Center keeps local session history with provider and status filters,
search, plans, workflows, parent/child agents, recent files, and event details.
Use **Open Origin** to reactivate the source application captured by the relay;
when that application is unavailable, Agents Notch reveals the working
directory in Finder. Completed-history retention is configurable in Settings.

## Local event protocol

The socket is an `AF_UNIX` stream socket. Send one UTF-8 JSON object per line and
close the connection. Payloads larger than 1 MiB are discarded. Protocol v1:

```json
{
  "protocolVersion": 1,
  "id": "740C8093-EFEA-44CA-B09C-3B8F60AF97F3",
  "type": "agent.activity",
  "sessionId": "abc123",
  "provider": "codex",
  "task": "Fix authentication bug",
  "activity": "Running tests",
  "state": "running",
  "timestamp": "2026-08-08T12:00:00Z",
  "workingDirectory": "/Users/me/project",
  "file": null,
  "applicationURL": null,
  "origin": {
    "bundleIdentifier": "com.apple.Terminal",
    "processIdentifier": 12345,
    "terminalProgram": "Apple_Terminal",
    "terminalSessionIdentifier": "…",
    "tty": "/dev/ttys001"
  },
  "metadata": null,
  "parentSessionId": null,
  "agentRole": null,
  "plan": null,
  "workflowUpdate": null
}
```

Required fields are `protocolVersion`, `id`, `type`, `sessionId`, `provider`,
and `timestamp`. `state` is optional because event type has a default state.

Supported event types:

| Type | Default state |
| --- | --- |
| `agent.started` | `starting` |
| `agent.activity` | `running` |
| `agent.tool.started` | `executingTool` |
| `agent.tool.completed` | `running` |
| `agent.file.changed` | `editing` |
| `agent.waiting` | `waitingForUser` |
| `agent.completed` | `completed` |
| `agent.failed` | `failed` |

### Structured execution

Protocol v1 also accepts optional structured execution fields. Existing senders
do not need to provide them.

- `parentSessionId` and `agentRole` link a subagent to its parent while keeping
  the child independently addressable.
- `plan` is the session's latest ordered plan snapshot. It contains optional
  `title` and `explanation` values plus `steps`; each step has an `id`, `title`,
  and `pending`, `inProgress`, `completed`, `failed`, or `blocked` status.
- `workflowUpdate` is a partial lifecycle update identified by a stable `id`.
  It can set a workflow's `title`, `status`, and ordered `steps` without
  resending fields that have not changed.
- `origin` is optional launch context captured by the local relay. It lets the
  app reactivate the source terminal or IDE without making the event invalid
  when a provider cannot supply origin metadata.

The built-in hook mapper translates Codex `update_plan` calls into plan
snapshots, `create_goal`/`update_goal` calls into workflow updates, and native
subagent lifecycle events into parent-linked sessions. Other integrations can
send the same provider-neutral fields directly. The detail surface renders
progress, step states, workflows, and navigable parent/child agents.

An integration can use `UnixSocketClient.send` from `AgentsNotchCore`, or
implement the few lines needed to connect and write newline-delimited JSON.

## Architecture

- `AgentsNotchCore`: provider-neutral models, activity reducer, lifecycle hook
  mapping, and Unix socket transport.
- `AgentsNotch`: SwiftUI views, the AppKit `NSPanel`, settings, persistence,
  adapters, and integration setup. A debug-only event simulator is compiled
  out of release builds.
- `AgentsNotchHook`: short-lived observer process invoked by provider lifecycle
  hooks.

`AgentProviderAdapter` defines `startMonitoring`, `stopMonitoring`, and
`discoverSessions`. Provider adapters translate native events into `AgentEvent`
without changing the notch UI.

Hook adapters are push-only, so `discoverSessions` returns an empty list. On
launch, Agents Notch reconciles restored runners instead of inventing
completion: dead origin process IDs complete immediately, waiting sessions stay
waiting, and other actives enter a short `unknown` (Reconnecting) grace period
until a live hook arrives or the grace expires.

All activity state and recent-session persistence stays local. There is no
analytics, source upload, or remote telemetry. If update checking is enabled,
the app makes an HTTPS request to GitHub Releases at most once per day; manual
checks use the same endpoint. Notifications are opt-in and delivered by macOS.

## Remove Agents Notch

Remove each installed provider integration from **Settings → Integrations**
before deleting the app. That removes only Agents Notch hook entries and
preserves unrelated provider configuration.

After quitting the app, its optional local history and copied relay can be
removed from:

- `~/Library/Application Support/AgentsNotch`
- `~/.agentsnotch`

## Verification and releases

Run the complete local verification stack with:

```sh
swift test
swift test -c release
./script/package_release.sh --adhoc
./script/check_repository.sh
```

The ad-hoc package validates release configuration and bundle structure but is
not intended for distribution. Maintainers should follow
[`docs/RELEASING.md`](docs/RELEASING.md) for Developer ID signing,
notarization, stapling, checksums, and GitHub release automation.

## Security and contributing

Report vulnerabilities privately according to [`SECURITY.md`](SECURITY.md).
Development setup and pull-request expectations are in
[`CONTRIBUTING.md`](CONTRIBUTING.md). Provider icon licensing and trademark
notices are recorded in [`THIRD_PARTY_NOTICES.md`](THIRD_PARTY_NOTICES.md).

Agents Notch is available under the terms in [`LICENSE`](LICENSE).
