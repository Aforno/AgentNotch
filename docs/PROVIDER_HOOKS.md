# Provider hooks

Provider hooks are passive observers by default. They must not make permission
decisions, block tools, or inject context unless Settings → Answer from the
notch is on. The hook ignores `SIGPIPE`, drains stdin, decodes and enriches
within bounds, sends an event when applicable, writes the provider's passive
response, and exits 0 even if Agents Notch is not running.

With Answer from the notch, permission, PreToolUse, and elicitation handlers
gain `--answer` and a 120-second timeout. Waiting events register on
`reply.sock` before the activity event is sent. A notch click writes the
provider decision JSON. Timeout or a missing app still writes the passive
response so the provider UI can take over. Claude permission handlers become
synchronous only in that mode. Cursor has no approval hook. OpenCode's plugin
does not wait.

Passive stdout is provider-specific. Claude Code receives empty stdout. The
other integrated providers receive `{}` followed by a newline. Keep this in
sync with `HookProcessIO.writePassiveResponse` and its tests.

## Compatibility and enrichment

- `AgentHookPayload` accepts snake_case and camelCase provider payloads,
  supported aliases such as `conversation_id`, and the tested date formats.
- `HookEventName` is the only event alias table. `AgentHookEventMapper` is the
  single event mapper. `ProviderEventPolicy` owns skip rules.
- Codex maps plan and workflow tools, resolves titles from the last 4 MiB of
  `session_index.jsonl`, and uses a fail-open, bounded 4 MiB transcript-tail
  read only when a permission payload omits `approvals_reviewer`. Remove that
  bridge when Codex supplies the reviewer directly.
- Grok becomes visible on its first agent turn, strips `<user_query>` wrappers,
  resolves missing title/hierarchy from its session tree, and skips duplicate
  Claude/Cursor compatibility hooks when the native Grok relay is installed.
- Claude Code uses exec-form `command`/`args` and asynchronous empty-stdout
  no-decision handlers for permission and elicitation events. Answer from the
  notch rewrites those handlers to `--answer` and a 120-second blocking wait.
- Cursor exposes session, prompt, tool, failure, and completion hooks. It has
  no passive native approval hook, so it cannot raise notch attention for
  approval.
- Gemini CLI Before/After lifecycle aliases map to the same protocol event
  types.
- OpenCode's generated plugin converts its events to `AgentHookPayload` first.

Disk walks stay behind `ProviderHookEnricher`. Provider-owned reads are limited
to title/hierarchy resolution, cold-start evidence, and the bounded Codex
approval bridge above. They must never invent a live session.

## Observer configuration

| Provider | Configuration |
| --- | --- |
| Codex | `~/.codex/hooks.json` |
| Claude Code | `~/.claude/settings.json` |
| Grok | `~/.grok/hooks/agentsnotch.json` |
| Gemini CLI | `~/.gemini/settings.json` |
| Cursor | `~/.cursor/hooks.json` |
| OpenCode | `~/.config/opencode/plugins/agentsnotch.js` |

Install and uninstall only this app's entries. Preserve unrelated entries,
symlink targets, and file modes. Repeated operations must be idempotent.
