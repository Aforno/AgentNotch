# Agents Notch

Native macOS status surface for local coding agents. It attaches to the MacBook
notch, stays out of the Dock, and shows provider-neutral activity from Codex,
Claude Code, Grok, Gemini CLI, OpenCode, and Cursor.

Project status is pre-1.0 public beta. The local protocol is versioned; UI
details and provider lifecycle mappings may still change.

## Working in this repository

- Keep changes focused. Explain the user-visible behavior they change.
- Prefer the existing module boundaries over new ones.
- Do not invent a remote backend, analytics, or a second transcript parser.
  Activity arrives as observer hook events over a private Unix socket.
- Hooks stay observers. Disk is allowed only for titles, hierarchy, and
  cold-start evidence; never for inventing live sessions.
- Provider hooks must never grant, deny, inject context, or block a tool.
  The relay always exits 0 with empty stdout.
- Install, refresh, and uninstall must be idempotent and must preserve
  unrelated provider configuration, including symlink targets and file modes.
- Update `CHANGELOG.md` for user-visible changes. Follow Keep a Changelog.
- Do not commit `.build/`, `dist/`, `.firecrawl/`, `.grok/`, `.codex/`,
  credentials, local agent data, or developer-specific absolute paths.

## Requirements

- Apple Silicon Mac, macOS 14 or later
- Swift 6 toolchain, language mode 6
- `rg` for `./script/check_repository.sh`

## Commands

Launch a debug app bundle (ad-hoc signed) and verify the process plus socket:

```sh
./script/build_and_run.sh --verify
```

Other launch modes: no args (run), `--debug` (lldb), `--logs`, `--telemetry`.

Full local verification, matching CI and the pull-request checklist:

```sh
swift test
swift test -c release
./script/package_release.sh --adhoc
./script/check_repository.sh
```

CI runs those checks on macOS 14 and 15. The ad-hoc package validates bundle
structure only; it is not for distribution. Signed notarized releases follow
`docs/RELEASING.md`.

Targeted tests:

```sh
swift test --filter AgentActivityServiceTests
swift test --filter AgentHookEventMapperTests
```

## Layout

| Path | Role |
| --- | --- |
| `Sources/AgentsNotchCore` | Provider-neutral models, activity reducer, hook mapping, Unix socket |
| `Sources/AgentsNotch` | SwiftUI/AppKit app, settings, persistence, integrations, setup |
| `Sources/AgentsNotchHook` | Short-lived observer process invoked by provider hooks |
| `Tests/AgentsNotchTests` | Unit tests for Core and app-adjacent behavior |
| `script/` | Build, stage, package, and repository hygiene |
| `Resources/` | App icon and provider-icon attribution |
| `docs/RELEASING.md` | Developer ID signing, notarization, GitHub release |

SwiftPM products: library `AgentsNotchCore`, executables `AgentsNotch` and
`AgentsNotchHook`. Bundle identifier is `com.afonsoferreira.AgentsNotch`.

## Architecture

```
provider hook/plugin
        │
        ▼
AgentsNotchHook  ──maps payload──►  AgentEvent JSON line
        │
        ▼
~/.agentsnotch/agent.sock   (dir 0700, socket 0600, 1 MiB max)
        │
        ▼
UnixSocketServer ──► AppRuntime ──► AgentActivityService
                                      │
                    SessionPersistence, notifications, notch UI
```

- `AgentActivityService` is the `@MainActor` reducer. All session list,
  attention queue, hierarchy, and notch snapshot logic lives there.
- `AppRuntime` owns the socket server, unknown-session grace period (90s),
  origin activation, and provider integration managers. Restore and
  persistence debounce live in `SessionRestorePipeline` and
  `SessionPersistScheduler`.
- `ProviderIntegrationManager` is the observable integration status object.
  Disk install/uninstall lives in `ProviderHookStore`. Hooks are push-only;
  there is no session-discovery adapter.
- UI never talks to a provider API. Every integration ends as the same
  `AgentEvent` values.

### Cold start

On launch, restored runners are reconciled rather than force-completed:

- dead origin process IDs complete immediately
- waiting sessions stay waiting
- other actives enter `.unknown` ("Reconnecting") until a live hook arrives
  or the grace period expires

Hooks stay push-only. Launch-time restorers and title/hierarchy resolvers
may read provider-owned files as cold-start evidence only. They must not
invent live sessions from disk.

## Local protocol

`AF_UNIX` stream socket. One UTF-8 JSON object per line, then close.
Protocol version is 1. Required fields: `protocolVersion`, `id`, `type`,
`sessionId`, `provider`, `timestamp`. Use `JSONEncoder.agentsNotch` /
`JSONDecoder.agentsNotch`.

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

Optional structured fields: `parentSessionId`, `agentRole`, `plan`,
`workflowUpdate`, `origin`. Existing senders do not need them.

Session IDs are namespaced as `provider:nativeId`. Subagents append
`:agentId`. Do not send an unprefixed provider session id into the reducer
from a hook mapper.

## Hook mapping

`AgentHookPayload` is a compatibility decoder, not a protocol version. It
accepts both snake_case (Codex, Claude Code, Gemini CLI, Cursor) and
camelCase (Grok), plus aliases such as `conversation_id` and four date
formats. Protocol v1 on the socket is `AgentEvent` only. Do not add another
payload alias without a mapper test. OpenCode's generated plugin converts to
that payload first.

`AgentHookEventMapper` is the single mapper. Return `nil` for events that
should stay invisible (Grok `SessionStart` lifecycle probes, Codex
memory-writer sessions, and similar). `HookEventName` is the only alias
table.

Provider-specific enrichment stays next to the mapper:

- Codex: `update_plan` → plan snapshot; `create_goal`/`update_goal` →
  workflow updates; `session_index.jsonl` titles via
  `CodexSessionTitleResolver`; approval context via
  `CodexApprovalContextResolver` (fail-open 4 MiB transcript-tail read of
  `turn_context` because PermissionRequest omits `approvals_reviewer`;
  remove when Codex includes the reviewer on the hook)
- Grok: first agent-turn makes the session visible; `<user_query>` wrappers
  are stripped; `GrokSessionContextResolver` walks the session tree when
  hierarchy or title is missing; skip duplicate Claude/Cursor compatibility
  hooks when the native Grok relay is installed
- Claude Code: exec-form `command`/`args`, synchronous, empty-stdout
  no-decision for permission, elicitation, AskUserQuestion, and ExitPlanMode
- Cursor: session/prompt/tool/failure/completion only. Its native approval
  dialog has no passive hook, so it cannot raise notch attention
- Gemini CLI: documented Before/After lifecycle aliases map to the same
  event types

The hook process must stay fast. Ignore `SIGPIPE`, drain stdin, write the
passive response, and exit 0 even when the app is not running.

### Config locations

| Provider | Observer config |
| --- | --- |
| Codex | `~/.codex/hooks.json` |
| Claude Code | `~/.claude/settings.json` |
| Grok | `~/.grok/hooks/agentsnotch.json` |
| Gemini CLI | `~/.gemini/settings.json` |
| Cursor | `~/.cursor/hooks.json` |
| OpenCode | `~/.config/opencode/plugins/agentsnotch.js` |

## UI conventions

Shared chrome lives in `NotchWindowStyle.swift`:

- opaque near-black surfaces (`NotchWindowPalette`)
- hairline separators, raised fills, white-opacity text ladder
- small radii (8–10), never `.black` font weights
- state colors from `agentStateColor(for:)`

Settings, Activity Center, and onboarding should stay on that vocabulary.
Settings rows are title + detail, switch toggles, and compact dark pills.

Notch presentation rules:

- stay collapsed for routine tool, edit, and completion activity
- expand automatically only for permission / answer attention
- expanded list shows the three most recently updated agent groups
- multiple waiting sessions form an attention queue
- parent rows surface waiting or failed descendant state
- Command-1 or the menu-bar item opens Activity Center

Debug simulator (`DebugEventSimulator`, Settings → Debug) is `#if DEBUG`
only. Simulated sessions use the `debug-simulator:` prefix, are never
persisted, and must be stripped when the simulator is disabled. Do not leak
simulator UI or wiring into release builds.

## Persistence and privacy

- History: `~/Library/Application Support/AgentsNotch/sessions.json`
- Relay and socket: `~/.agentsnotch`
- No analytics, source upload, or remote telemetry
- Optional update checks hit GitHub Releases at most once per day
- Notifications are opt-in and delivered by macOS
- Hook payload text, paths, URLs, and metadata are untrusted input
- Same-user processes may connect to the socket; other users must not

If history is unreadable, quarantine it. Do not overwrite the only copy.

## Tests

Add regression tests for reducer, protocol, socket, persistence, or
integration-configuration behavior. Existing coverage lives in
`Tests/AgentsNotchTests`.

Patterns to match:

- `@MainActor` XCTest methods for reducer and manager tests
- temp-directory fixtures that `defer { fixture.remove() }`
- assert install is idempotent and uninstall leaves foreign hook entries
- assert file modes (`0600` configs, `0755` relay)
- wrap DEBUG-only types in `#if DEBUG`

UI changes should be smoke-tested with `./script/build_and_run.sh --verify`
and, when the layout changed, screenshots in the pull request.

## Code style

- Swift 6 tools, `.swiftLanguageMode(.v6)`, four-space indent
- No trailing whitespace (`./script/check_repository.sh` fails on it)
- `Sendable` value types; `@MainActor` for app and activity state
- Prefer small `enum` namespaces (`AgentHookEventMapper`,
  `CodexHookConfiguration`) over scattered free functions
- Comments explain non-obvious constraints, not the change you just made
- Keep provider display names and raw values in `AgentProvider`

## Adding a provider

1. Add a static `AgentProvider` value.
2. Extend `ProviderIntegrationManager` so install/uninstall only touches this
   app's entries and stays idempotent.
3. Map native lifecycle events in `AgentHookEventMapper` (or convert to
   `AgentHookPayload` first, as OpenCode does).
4. Wire the provider into `AppRuntime.integratedProviders`. Do not add a
   scanning adapter that invents live sessions from disk.
5. Add a provider icon under `Sources/AgentsNotch/Resources/ProviderIcons.xcassets`
   and record licensing in `THIRD_PARTY_NOTICES.md` plus
   `Resources/ProviderIcons/ATTRIBUTION.md`.
6. Cover install/uninstall and mapping with tests.

Do not replace existing user hooks, return a hook decision, or make the UI
provider-specific.

## Security

Report vulnerabilities privately as described in `SECURITY.md`. Do not put
proof-of-concept exploits, credentials, or private session data in issues or
commits.
