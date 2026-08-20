# Local protocol

Agents Notch receives events over an `AF_UNIX` stream socket at
`~/.agentsnotch/agent.sock`. Send one UTF-8 JSON object per line, then close the
connection. The directory mode is `0700`, the socket mode is `0600`, and the
maximum payload is 1 MiB.

Protocol version 1 carries `AgentEvent` values. Required fields are
`protocolVersion`, `id`, `type`, `sessionId`, `provider`, and `timestamp`. Use
`JSONEncoder.agentsNotch` and `JSONDecoder.agentsNotch`. Optional structured
fields include `parentSessionId`, `agentRole`, `plan`, `workflowUpdate`,
`origin`, and `pendingReply`.

`applicationURL` is untrusted. The Open session action accepts it only when it
uses HTTPS and its host belongs to the event's built-in provider.

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

`pendingReply` is additive on `agent.waiting`. It carries `replyId`, `kind`
(`permission`, `question`, `plan`, `elicitation`), `prompt`, optional `detail`,
`options`, and `grants`. Missing `pendingReply` keeps the island display-only.
The hook that set `replyId` then waits on `~/.agentsnotch/reply.sock` for one
`AgentReply` line. No reply, or a missing app, fail-opens to the provider's
own prompt.

`AgentHookPayload` is a compatibility decoder, not a protocol version. It accepts
the provider payload formats that `AgentHookEventMapper` converts into protocol
v1 `AgentEvent` values. Existing senders do not need optional structured fields.
