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
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        guard var end = try? handle.seekToEnd() else { return nil }

        let decoder = JSONDecoder()
        // A record may span several reads. Keep its fragments newest first so
        // large tool outputs are assembled once instead of copied at every cut.
        var fragments: [Data] = []
        while end > 0 {
            let count = Int(min(end, UInt64(maximumTranscriptTailBytes)))
            end -= UInt64(count)
            guard (try? handle.seek(toOffset: end)) != nil,
                  let chunk = try? handle.read(upToCount: count),
                  chunk.count == count
            else { return nil }

            let recordsStart: Data.Index
            if end == 0 {
                recordsStart = chunk.startIndex
            } else if let newline = chunk.firstNewline {
                recordsStart = newline + 1
            } else {
                fragments.append(chunk)
                continue
            }

            var records = chunk[recordsStart...]
            for fragment in fragments.reversed() {
                records.append(fragment)
            }
            for line in records.lines(containing: turnContextBytes).reversed() {
                guard let record = try? decoder.decode(TranscriptRecord.self, from: line),
                      record.type == "turn_context",
                      let context = record.payload,
                      context.matches(turnId: matchingTurnId)
                else { continue }
                return context.approvalsReviewer
            }

            fragments.removeAll(keepingCapacity: true)
            if recordsStart > chunk.startIndex {
                fragments.append(chunk[..<(recordsStart - 1)])
            }
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
