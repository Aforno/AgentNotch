# Provider hooks

Provider hooks are passive observers by default. They do not make permission
decisions, block tools, or inject context. The hook ignores `SIGPIPE`, drains
stdin, decodes and enriches within bounds, sends an event when applicable,
writes the provider's passive response, and exits 0 even if Agent Notch is not
running.

Enabling Answer from the notch adds `--answer` and a 120-second timeout to
Codex and Claude Code permission and elicitation handlers. Claude Code also gets
narrow synchronous `PreToolUse` matchers for `AskUserQuestion` and
`ExitPlanMode`; other tools keep a 5-second asynchronous observer. The hook
waits for a `reply.sock` registration ACK before it sends the actionable waiting event. A notch click writes
the provider decision JSON. If the app is unavailable or no answer arrives, the
hook writes the passive response and the provider shows its own prompt. Claude
permission handlers become synchronous only while this setting is enabled.
Grok, Gemini, Antigravity, Cursor, and OpenCode do not wait for a decision.
Gemini's Notification hook only reports status. Antigravity does not install
PreToolUse: that hook requires `decision` (`allow`/`deny`/`ask`) and `{}`
denies the tool. Stop writes `{"decision":"stop"}` so the turn can end.
Cursor has no approval hook, and the OpenCode plugin does not wait.

Passive stdout is provider-specific. Claude Code receives empty stdout.
Antigravity Stop writes `{"decision":"stop"}`. The other integrated providers
receive `{}` followed by a newline. Keep this in sync with
`HookProcessIO.writePassiveResponse` and its tests.

## Compatibility and enrichment

- `AgentHookPayload` accepts snake_case and camelCase provider payloads,
  supported aliases such as `conversation_id`, and the tested date formats.
- `HookEventName` is the only event alias table. `AgentHookEventMapper` is the
  single event mapper. `ProviderEventPolicy` owns skip rules.
- Codex maps plan and workflow tools, resolves titles from the last 4 MiB of
  `session_index.jsonl`, and uses a fail-open, bounded 4 MiB transcript-tail
  read only when a permission payload omits `approvals_reviewer`. Remove that
  bridge when Codex supplies the reviewer directly. `Interrupt` settles a user
  interrupt. Codex has no `StopCancelled` or `StopFailure` event.
- Grok becomes visible on its first agent turn, strips `<user_query>` wrappers,
  resolves missing title/hierarchy from its session tree, and skips duplicate
  Claude/Cursor compatibility hooks when the native Grok relay is installed.
  Turn settlement listens for `Stop`, `StopFailure`, `StopCancelled`, and Grok's
  `idle_prompt` notification so a truncated stream or usage limit cannot leave
  the spinner running. Grok `promptId` values are retained on hook events so a
  delayed turn-end report for a known older prompt cannot settle a newer turn.
  An unseen prompt id still settles, covering interrupted bash-mode work.
  `idle_prompt` is only a backstop: it does not replace a terminal outcome that
  Agent Notch already observed. Claude's `idle_prompt` is a delayed idle ping
  after Stop and is ignored.
- Claude Code uses exec-form `command`/`args` and asynchronous empty-stdout
  handlers for permission and elicitation events. Enabling Answer from the
  notch adds `--answer` handlers only for supported interactive events.
- Cursor exposes session, prompt, tool, failure, and completion hooks. It has
  no passive native approval hook, so it cannot raise notch attention for
  approval.
- Gemini CLI Before/After lifecycle aliases map to the same protocol event
  types.
- Antigravity uses a named `agentnotch` hook in `~/.agents/hooks.json`.
  Payloads are camelCase (`conversationId`, `workspacePaths`, nested
  `toolCall`) and omit the event name; the installed command passes `--event`.
  PreInvocation 0 becomes SessionStart. PostToolUse matchers use `.*` (`*` is
  not valid regex). Do not install PreToolUse: it is a permission gate.
  ACP native tools send `target_file` / `absolute_path`; those map onto
  `file_path`. JSON lifecycle hooks are gated in the harness
  (`enable_json_hooks` / `json-hooks-enabled`). If the host launches
  Antigravity without that flag, hook discovery is skipped and Agent Notch
  never receives events. Install also removes a leftover `agentnotch` entry
  from `~/.gemini/config/hooks.json`, which the customization engine does
  not scan.
- OpenCode's generated plugin converts its events to `AgentHookPayload` first.

Disk walks stay behind `ProviderHookEnricher`. Provider-owned reads are limited
to title/hierarchy resolution, cold-start evidence, and the bounded Codex
approval bridge above. They must never invent a live session.

## Observer configuration

| Provider | Configuration |
| --- | --- |
| Codex | `~/.codex/hooks.json` |
| Claude Code | `~/.claude/settings.json` |
| Grok | `~/.grok/hooks/agentnotch.json` |
| Gemini CLI | `~/.gemini/settings.json` |
| Antigravity | `~/.agents/hooks.json` |
| Cursor | `~/.cursor/hooks.json` |
| OpenCode | `~/.config/opencode/plugins/agentnotch.js` |

Install and uninstall only this app's entries. Preserve unrelated entries,
symlink targets, and file modes. Repeated operations must be idempotent.
