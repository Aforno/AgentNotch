import Foundation

/// Resolves whether a Codex permission hook is waiting on a person or on an
/// automatic reviewer. Codex does not currently include `approvals_reviewer`
/// in every PermissionRequest payload, so the matching turn context is used as
/// a compatibility bridge: a fail-open, 4 MiB tail read of the transcript
/// JSONL. Remove this when Codex includes the reviewer on the hook. Do not
/// add a second transcript parser.
public enum CodexApprovalContextResolver {
    public static let maximumTranscriptTailBytes = 4 * 1_024 * 1_024

    public static func permissionRequestRequiresUserInput(for payload: AgentHookPayload) -> Bool {
        guard HookEventName(rawEventName: payload.hookEventName) == .permissionRequest else {
            return true
        }

        if let reviewer = payload.approvalsReviewer?.nonEmpty {
            return !isAutomaticReviewer(reviewer)
        }

        // A transcript without turn_id has no matching turn. Using the newest
        // turn_context would hide a user-facing approval behind a later
        // auto_review / guardian_subagent context. Missing context fails open.
        guard let transcriptPath = payload.transcriptPath?.nonEmpty,
              let turnId = payload.turnId?.nonEmpty,
              let reviewer = reviewer(
                  inTranscriptAt: URL(fileURLWithPath: transcriptPath),
                  matchingTurnId: turnId
              )
        else {
            return true
        }

        return !isAutomaticReviewer(reviewer)
    }

    private static func reviewer(inTranscriptAt url: URL, matchingTurnId: String?) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }

        guard let endOffset = try? handle.seekToEnd() else { return nil }
        let maximumBytes = UInt64(maximumTranscriptTailBytes)
        let startOffset = endOffset > maximumBytes ? endOffset - maximumBytes : 0
        guard (try? handle.seek(toOffset: startOffset)) != nil,
              var data = try? handle.readToEnd(),
              !data.isEmpty
        else {
            return nil
        }

        // If the tail begins midway through a JSONL record, discard that
        // partial record before decoding from newest to oldest.
        if startOffset > 0 {
            guard let newline = data.firstIndex(of: 0x0A) else { return nil }
            data.removeSubrange(data.startIndex...newline)
        }

        for line in data.split(separator: 0x0A).reversed() {
            guard let record = try? JSONDecoder().decode(TranscriptRecord.self, from: Data(line)),
                  record.type == "turn_context",
                  let context = record.payload
            else {
                continue
            }

            if let matchingTurnId, !context.matches(turnId: matchingTurnId) {
                continue
            }

            return context.approvalsReviewer
        }

        return nil
    }

    private static func isAutomaticReviewer(_ reviewer: String) -> Bool {
        switch reviewer
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "-", with: "_")
            .lowercased()
        {
        case "auto_review", "guardian_subagent":
            true
        default:
            false
        }
    }
}

private struct TranscriptRecord: Decodable {
    let type: String?
    let payload: TurnContextPayload?
}

private struct TurnContextPayload: Decodable {
    let snakeTurnId: String?
    let camelTurnId: String?
    let approvalsReviewer: String?

    private enum CodingKeys: String, CodingKey {
        case turnId
        case turn_id
        case approvalsReviewer
        case approvals_reviewer
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        snakeTurnId = container.lossyString(forKeys: .turn_id)
        camelTurnId = container.lossyString(forKeys: .turnId)
        // Prefer the historical snake_case spelling when both aliases exist.
        approvalsReviewer = container.lossyString(forKeys: .approvals_reviewer, .approvalsReviewer)
    }

    func matches(turnId: String) -> Bool {
        snakeTurnId == turnId || camelTurnId == turnId
    }
}

private extension KeyedDecodingContainer {
    /// Missing keys and non-string values are absent. Does not fail the record.
    func lossyString(forKeys keys: Key...) -> String? {
        for key in keys {
            if let value = try? decodeIfPresent(String.self, forKey: key) {
                return value
            }
        }
        return nil
    }
}
