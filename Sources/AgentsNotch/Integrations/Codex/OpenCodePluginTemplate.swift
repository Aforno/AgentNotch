import Foundation

/// Owns the generated OpenCode bridge source so provider configuration logic
/// does not also contain a second implementation language inline.
enum OpenCodePluginTemplate {
    static let marker = "// Managed by Agents Notch."

    static func isOwned(_ data: Data) -> Bool {
        let source = String(decoding: data, as: UTF8.self)
        return source.contains(marker)
            && source.contains("export const AgentsNotchPlugin")
    }

    static func data(relayURL: URL) -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .withoutEscapingSlashes
        let encodedRelayPath = try? encoder.encode(relayURL.path)
        let relayLiteral = encodedRelayPath.map { String(decoding: $0, as: UTF8.self) } ?? "\"\""
        let source = """
        \(marker)
        // Reinstall from Agents Notch instead of editing this generated bridge.
        const relayPath = \(relayLiteral)

        const emit = async (payload) => {
          if (!payload?.session_id) return
          try {
            const process = Bun.spawn([relayPath, "--provider", "opencode"], {
              stdin: new Blob([JSON.stringify(payload)]),
              stdout: "ignore",
              stderr: "ignore",
            })
            await process.exited
          } catch {
            // Monitoring is passive and must never interrupt OpenCode.
          }
        }

        const textFromParts = (parts) => (parts ?? [])
          .filter((part) => part?.type === "text" && typeof part.text === "string")
          .map((part) => part.text)
          .join("\\n")

        const errorMessage = (error) => error?.data?.message ?? error?.message ?? String(error ?? "OpenCode session failed")

        export const AgentsNotchPlugin = async ({ directory }) => ({
          event: async ({ event }) => {
            const properties = event?.properties ?? {}
            const info = properties.info ?? {}
            const sessionID = properties.sessionID ?? info.id
            const cwd = info.directory ?? directory

            switch (event?.type) {
              case "session.created":
                await emit({
                  session_id: sessionID,
                  cwd,
                  hook_event_name: "SessionStart",
                  timestamp: info.time?.created,
                  parent_session_id: info.parentID,
                })
                break
              case "session.status":
                if (properties.status?.type === "busy") {
                  await emit({ session_id: sessionID, cwd, hook_event_name: "UserPromptSubmit" })
                }
                break
              case "session.idle":
                await emit({ session_id: sessionID, cwd, hook_event_name: "Stop" })
                break
              case "session.error":
                await emit({
                  session_id: sessionID,
                  cwd,
                  hook_event_name: "StopFailure",
                  error: errorMessage(properties.error),
                })
                break
              case "permission.replied":
                const permissionReply = properties.reply ?? properties.response
                await emit({
                  session_id: sessionID,
                  cwd,
                  hook_event_name: permissionReply === "reject" || permissionReply === "deny"
                    ? "PermissionDenied"
                    : "UserPromptSubmit",
                })
                break
              case "question.asked":
                await emit({
                  session_id: sessionID,
                  cwd,
                  hook_event_name: "Notification",
                  notification_type: "agent_needs_input",
                  message: properties.questions?.[0]?.question ?? "OpenCode needs input",
                })
                break
              case "question.replied":
              case "question.rejected":
                await emit({ session_id: sessionID, cwd, hook_event_name: "UserPromptSubmit" })
                break
              case "message.part.updated":
                if (properties.part?.type === "tool" && properties.part.state?.status === "error") {
                  await emit({
                    session_id: sessionID ?? properties.part.sessionID,
                    cwd,
                    hook_event_name: "PostToolUseFailure",
                    tool_name: properties.part.tool,
                    tool_input: properties.part.state.input,
                    error: properties.part.state.error,
                    timestamp: properties.part.state.time?.end,
                  })
                }
                break
            }
          },
          "chat.message": async (input, output) => {
            await emit({
              session_id: input.sessionID,
              cwd: directory,
              hook_event_name: "UserPromptSubmit",
              prompt: textFromParts(output.parts),
            })
          },
          "permission.ask": async (input) => {
            await emit({
              session_id: input.sessionID,
              cwd: directory,
              hook_event_name: "PermissionRequest",
              tool_name: input.type ?? input.permission ?? input.title,
              tool_input: input.metadata,
              timestamp: input.time?.created,
            })
          },
          "tool.execute.before": async (input, output) => {
            await emit({
              session_id: input.sessionID,
              cwd: directory,
              hook_event_name: "PreToolUse",
              tool_name: input.tool,
              tool_input: output.args,
            })
          },
          "tool.execute.after": async (input) => {
            await emit({
              session_id: input.sessionID,
              cwd: directory,
              hook_event_name: "PostToolUse",
              tool_name: input.tool,
              tool_input: input.args,
            })
          },
        })
        """
        return Data((source + "\n").utf8)
    }
}
