import Foundation

/// Uses the hook's reviewer or the matching transcript turn to identify automatic
/// approvals. Missing context leaves the permission request visible to the user.
public enum CodexApprovalContextResolver {
    public static let maximumTranscriptTailBytes = 4 * 1_024 * 1_024
    private static let turnContextBytes = Data("turn_context".utf8)

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

    private static func reviewer(inTranscriptAt url: URL, matchingTurnId: String) -> String? {
        guard let data = Data.jsonlTail(at: url, maxBytes: maximumTranscriptTailBytes),
              !data.isEmpty
        else {
            return nil
        }

        let decoder = JSONDecoder()
        for line in data.lines(containing: turnContextBytes).reversed() {
            guard let record = try? decoder.decode(TranscriptRecord.self, from: Data(line)),
                  record.type == "turn_context",
                  let context = record.payload
            else {
                continue
            }

            if !context.matches(turnId: matchingTurnId) {
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
