# Local protocol

Agent Notch receives events over an `AF_UNIX` stream socket at
`~/.agentnotch/agent.sock`. Send one UTF-8 JSON object per line, then close the
connection. The directory mode is `0700`, the socket mode is `0600`, and the
maximum payload is 1 MiB.

Protocol version 1 carries `AgentEvent` values. Required fields are
`protocolVersion`, `id`, `type`, `sessionId`, `provider`, and `timestamp`. Use
`JSONEncoder.agentsNotch` and `JSONDecoder.agentsNotch`. Optional structured
fields include `parentSessionId`, `agentRole`, `plan`, `workflowUpdate`,
`origin`, and `pendingReply`.

`applicationURL` is untrusted. The Open session action accepts it only when it
uses HTTPS and its host belongs to the event's built-in provider. Codex threads
instead use an app-owned `codex://threads/<thread-id>` URL. Child sessions use
the parent thread ID. Roots use the canonical session ID only when Codex index
evidence is present. Open terminal uses `origin` (`bundleIdentifier`,
`terminalProgram`, `tty`, `terminalSessionIdentifier`) and ignores
`applicationURL`.

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

Session IDs are `provider:nativeId`; subagents append `:agentId`. Hook mappers
must never send an unprefixed provider session ID into the reducer.

An `agent.waiting` event may include `pendingReply`. It carries `replyId`,
`kind` (`permission`, `question`, `plan`, or `elicitation`), `prompt`, optional
`detail`, `options`, provider-specific `questions`, and `grants`. Without `pendingReply`, the notch only shows
the waiting state. The hook that created `replyId` waits on
`~/.agentnotch/reply.sock` for a registration ACK and one `AgentReply` line.
The app tracks simultaneous replies by `replyId`. If the app is unavailable
or no reply arrives within 120 seconds, the provider shows its own prompt.

## Reply channel

The reply channel is a second `AF_UNIX` stream socket at
`~/.agentnotch/reply.sock` (directory mode `0700`, socket mode `0600`). A hook
process that wants an answer from the notch follows this order — registration
must complete before the waiting event is announced, or the notch can offer an
answer button for a waiter nobody will wake:

1. Connect and send one UTF-8 JSON hello line:

   ```json
   {"replyId":"<UUID>"}
   ```

2. Read one ack line. `registered: true` means the app will route a decision to
   this connection; anything else means hang up and fail open:

   ```json
   {"registered":true}
   ```

3. Only after the ack, send the `agent.waiting` event (with its `pendingReply`
   carrying the same `replyId`) over `agent.sock`.

4. Block on the reply socket. When the user answers, exactly one `AgentReply`
   line arrives, then the server closes the connection:

   ```json
   {"replyId":"<UUID>","decision":"allow","optionId":null,"answers":null}
   ```

   `decision` is one of `deny`, `allow`, `option`, or `cancel`. `optionId` is
   set only for `.option`; `answers` maps Claude question text to selected
   option labels.

Timing contract: the hook's own provider timeout must stay authoritative. The
bundled relay gives up 10 seconds before Claude Code's 120-second hook budget
so it can still print its passive response and exit 0. If you implement this
channel yourself, reserve headroom the same way.

`AgentHookPayload` is a compatibility decoder, not a protocol version. It accepts
the provider payload formats that `AgentHookEventMapper` converts into protocol
v1 `AgentEvent` values. Existing senders do not need optional structured fields.

## Adding your own provider

Any local tool can appear in the notch without changes to Agent Notch: send
protocol v1 `AgentEvent` lines directly over `~/.agentnotch/agent.sock`. This
is the same channel the built-in hooks use.

1. Pick a stable provider id (`provider` field). It keys sessions, filters, and
   history; session IDs must be namespaced as `<provider>:<nativeId>` so they
   cannot collide with other tools.
2. Emit lifecycle events as work happens:
   - `agent.started` when your agent begins a session.
   - `agent.activity` / `agent.tool.started` / `agent.tool.completed` /
     `agent.file.changed` while running. Keep them small and frequent-ish;
     they drive the live state indicator and timeline.
   - `agent.waiting` when the user must act. Include `pendingReply` if you can
     honor a decision (see the reply channel above); omit it for pure status.
   - `agent.completed` or `agent.failed` when done.
3. Set `workingDirectory` so the session groups under the right project, and
   `timestamp` (ISO 8601) on every event. Events with future timestamps are
   clamped on ingest.
4. Encode with the same conventions as `JSONEncoder.agentsNotch`: one JSON
   object per line, sorted keys optional, dates as ISO 8601 strings. Payloads
   over 1 MiB are rejected.

Reference implementations live in `Sources/AgentsNotchCore/Protocol/`
(`AgentHookEventMapper` converts each supported provider's native payloads into
these events) and the bundled relay in `Sources/AgentsNotchHook/`.

