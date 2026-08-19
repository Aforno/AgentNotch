# Agents Notch

Agents Notch sits on the MacBook notch and shows what your local coding agents
are doing. Tool calls, file edits, and completions stay collapsed. Hover to
expand, or it opens itself when an agent needs a permission or an answer. No
Dock icon. No menu-bar extra.

Pre-1.0 public beta. The local protocol is versioned. The UI and provider hook
mappings can still change before 1.0.

It talks to Codex, Claude Code, Grok, Gemini CLI, OpenCode, and Cursor. Every
integration sends the same `AgentEvent` values to a local socket.

## Install

Requirements: Apple Silicon Mac and macOS 14 or later.

When a release is up, download the ZIP and the matching `.sha256` file from the
[GitHub releases page](../../releases). Verify it before you open the app:

```sh
shasum -a 256 -c Agents-Notch-*-macOS-arm64.zip.sha256
```

Unzip the archive, move `Agents Notch.app` to `/Applications`, and open it.
Production releases are Developer ID signed and notarized. Unsigned previews are
marked as prereleases and may trip Gatekeeper. Control-click the app, choose
Open, and read the prompt.

## Develop from source

Source builds need Swift 6.

```sh
./script/build_and_run.sh --verify
```

That builds both executables in debug, stages an ad-hoc signed
`dist/Agents Notch.app`, embeds the hook relay, launches the bundle, and checks
that the process and the private event socket stay up. The Codex desktop Run
action calls the same script.

On first launch, the setup window can install and test each provider observer.
After that, press Command-1 or use the notch to open Activity Center. Hover
until the notch fully expands to see the last three updated sessions.

In debug builds only, Settings → Debug → Enable debug simulator can fake single
states, plan progress, workflow steps, subagent trees, or several providers at
once. Simulated sessions are never saved. Turning the simulator off cancels the
demo and drops simulated statuses. Real provider sessions stay. Release builds
leave the simulator, the Debug tab, and that wiring out.

## Provider integrations

Open Settings → Integrations and install Codex, Claude, Grok, Gemini, OpenCode,
Cursor, or any mix of them. Agents Notch:

1. copies its small relay to `~/.agentsnotch/bin/agentsnotch-hook`;
2. installs an observer-only hook or plugin through the provider's supported
   extension point, without replacing anything already there;
3. listens on `~/.agentsnotch/agent.sock` with directory mode `0700` and socket
   mode `0600`.

Config files:

- Codex: `~/.codex/hooks.json`
- Claude Code: `~/.claude/settings.json`
- Grok: `~/.grok/hooks/agentsnotch.json`
- Gemini CLI: `~/.gemini/settings.json`
- Cursor: `~/.cursor/hooks.json`
- OpenCode: `~/.config/opencode/plugins/agentsnotch.js`

In providers that have `/hooks`, that command shows the installed entries. Codex
also requires new command hooks to be trusted.

The observers never return a decision, inject context, or block a tool. The
relay always exits 0, even if Agents Notch is not running.

They subscribe to each provider's documented session, prompt, tool, permission,
notification, and stop events. Claude Code observers use the documented
exec-form `args` array with asynchronous command handlers, so they cannot block
or control permission, elicitation, AskUserQuestion, or ExitPlanMode.

The relay accepts the snake_case payload used by Codex, Claude Code, Gemini CLI,
and Cursor, and Grok's camelCase payload. The OpenCode bridge converts plugin
events to that same observer payload.

The only transcript read is a fail-open, size-capped Codex approval bridge. Do
not add another parser.

If a tool never goes through a provider's local hook path, we cannot show it as
fine-grained activity.

Cursor's current hook API has no passive event for its native approval prompt.
Session, prompt, tool, failure, and completion activity still show. Cursor's own
approval dialog cannot wake the notch.

Grok sessions appear on their first agent-turn event. Grok also fires
`SessionStart` for lifecycle-only CLI calls such as version probes. Those are
ignored. No agent task has started.

- [Codex hooks documentation](https://learn.chatgpt.com/docs/hooks)
- [Codex configuration reference](https://learn.chatgpt.com/docs/config-file/config-reference)
- [Claude Code hooks reference](https://code.claude.com/docs/en/hooks)
- [Grok hooks reference](https://docs.x.ai/build/features/hooks)
- [Gemini CLI hooks reference](https://geminicli.com/docs/hooks/reference/)
- [OpenCode plugins reference](https://opencode.ai/docs/plugins/)
- [Cursor hooks reference](https://cursor.com/docs/hooks)

## Activity and attention

The notch stays collapsed for routine work. It auto-expands only when an agent
is waiting for a permission or an answer. Several waiting sessions form an
attention queue. Optional macOS notifications include an Open Session action.
Displays without a hardware notch can use the virtual notch or Activity Center.

Activity Center keeps local session history. Filter by provider or status,
search, and inspect plans, workflows, parent/child agents, recent files, and
event details. Open Origin reactivates the source app the relay captured. If
that app is gone, Agents Notch reveals the working directory in Finder.
Completed-history retention is in Settings.

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
    "terminalSessionIdentifier": "...",
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
and `timestamp`. `state` is optional because the event type already has a
default state.

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
can omit them.

- `parentSessionId` and `agentRole` link a subagent to its parent. The child
  stays independently addressable.
- `plan` is the session's latest ordered plan snapshot. Optional `title` and
  `explanation`, plus `steps`. Each step has an `id`, `title`, and a status of
  `pending`, `inProgress`, `completed`, `failed`, or `blocked`.
- `workflowUpdate` is a partial lifecycle update keyed by a stable `id`. It can
  set a workflow's `title`, `status`, and ordered `steps` without repeating
  unchanged fields.
- `origin` is optional launch context from the local relay. The app can
  reactivate the source terminal or IDE. Missing origin does not invalidate the
  event.

The built-in hook mapper turns Codex `update_plan` calls into plan snapshots,
`create_goal`/`update_goal` into workflow updates, and native subagent lifecycle
events into parent-linked sessions. Other integrations can send the same fields
directly. The detail view renders progress, step states, workflows, and
parent/child navigation.

An integration can call `UnixSocketClient.send` from `AgentsNotchCore`, or
connect and write newline-delimited JSON itself.

## Architecture

- `AgentsNotchCore`: models, activity reducer, lifecycle hook mapping, Unix
  socket transport.
- `AgentsNotch`: SwiftUI views, the AppKit `NSPanel`, settings, persistence,
  integration setup. The debug event simulator is compiled out of release
  builds.
- `AgentsNotchHook`: short-lived observer process that provider lifecycle hooks
  invoke.

`ProviderIntegrationManager` installs observer hooks and the shared relay.
Hooks are push-only. Launch-time restorers may read provider-owned files as
cold-start evidence. They never invent live sessions from disk.

On launch, Agents Notch reconciles restored runners. It does not invent
completion. Dead or recycled origin process IDs complete immediately. Verified
waiting sessions stay waiting. Other actives enter a short `unknown`
(Reconnecting) grace period until a live hook arrives or the grace expires.

Session history stays on the machine. No analytics, no source upload, no remote
telemetry. If update checking is on, the app makes an HTTPS request to GitHub
Releases at most once a day. Manual checks use the same endpoint. Notifications
are opt-in and delivered by macOS.

## Remove Agents Notch

Remove each installed provider integration from Settings → Integrations before
deleting the app. That deletes only Agents Notch hook entries. Other provider
config stays.

After quitting, optional local history and the copied relay live in:

- `~/Library/Application Support/AgentsNotch`
- `~/.agentsnotch`

## Verification and releases

```sh
swift test
swift test -c release
./script/package_release.sh --adhoc
./script/check_repository.sh
```

The ad-hoc package checks release configuration and bundle structure. Do not
distribute it. Maintainers follow [`docs/RELEASING.md`](docs/RELEASING.md) for
Developer ID signing, notarization, stapling, checksums, and GitHub release
automation.

## Security and contributing

Report vulnerabilities privately. See [`SECURITY.md`](SECURITY.md). Setup and
pull-request expectations are in [`CONTRIBUTING.md`](CONTRIBUTING.md). Provider
icon licensing and trademark notices are in
[`THIRD_PARTY_NOTICES.md`](THIRD_PARTY_NOTICES.md).

Agents Notch is available under the terms in [`LICENSE`](LICENSE).
