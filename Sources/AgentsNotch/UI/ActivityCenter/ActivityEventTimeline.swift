import AgentsNotchCore
import SwiftUI

struct ActivityEventSummary: Identifiable, Equatable {
    enum Kind: Equatable {
        case tool
        case event
    }

    let id: UUID
    let kind: Kind
    let title: String
    let startedAt: Date
    let endedAt: Date
    let operationCount: Int
    let events: [AgentEvent]

    var duration: TimeInterval { max(0, endedAt.timeIntervalSince(startedAt)) }

    static func make(from recentEvents: [AgentEvent]) -> [ActivityEventSummary] {
        var summaries: [ActivityEventSummary] = []
        for event in recentEvents.sorted(by: { $0.timestamp < $1.timestamp }) {
            if let tool = toolName(for: event),
               let last = summaries.last,
               last.kind == .tool,
               last.events.last.flatMap(toolName(for:)) == tool
            {
                let combined = last.events + [event]
                summaries[summaries.count - 1] = toolSummary(tool: tool, events: combined)
            } else if let tool = toolName(for: event) {
                summaries.append(toolSummary(tool: tool, events: [event]))
            } else {
                summaries.append(ActivityEventSummary(
                    id: event.id,
                    kind: .event,
                    title: event.activity?.nonEmpty ?? event.resolvedState.displayName,
                    startedAt: event.timestamp,
                    endedAt: event.timestamp,
                    operationCount: 1,
                    events: [event]
                ))
            }
        }
        return summaries.reversed()
    }

    private static func toolSummary(tool: String, events: [AgentEvent]) -> ActivityEventSummary {
        let completed = events.filter { $0.type == .toolCompleted }.count
        let started = events.filter { $0.type == .toolStarted }.count
        let failed = events.contains { $0.resolvedState == .failed }
        let isRunning = events.last?.type == .toolStarted
        let verb = failed ? "Tool failed" : (isRunning ? "Using" : "Ran")
        return ActivityEventSummary(
            id: events.first?.id ?? UUID(),
            kind: .tool,
            title: "\(verb) \(displayName(for: tool))",
            startedAt: events.map(\.timestamp).min() ?? .distantPast,
            endedAt: events.map(\.timestamp).max() ?? .distantPast,
            operationCount: max(1, max(completed, started)),
            events: events
        )
    }

    private static func toolName(for event: AgentEvent) -> String? {
        guard event.type == .toolStarted || event.type == .toolCompleted else { return nil }
        return event.metadata?["tool"]?.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty
            ?? event.activity?.replacingOccurrences(of: "Using ", with: "")
                .replacingOccurrences(of: "Finished ", with: "")
                .nonEmpty
    }

    private static func displayName(for tool: String) -> String {
        let leaf = tool.split(separator: "__").last.map(String.init) ?? tool
        switch leaf.lowercased() {
        case "js": return "JavaScript"
        case "exec", "exec_command", "bash", "shell": return "command"
        case "apply_patch", "edit", "write": return "file edit"
        case "read", "read_file": return "file read"
        default:
            return leaf
                .replacingOccurrences(of: "_", with: " ")
                .replacingOccurrences(of: "-", with: " ")
        }
    }
}

struct ActivityEventTimeline: View {
    let events: [AgentEvent]
    @State private var showsRawEvents = false

    private var summaries: [ActivityEventSummary] {
        ActivityEventSummary.make(from: events)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(summaries) { summary in
                summaryRow(summary)
            }

            if summaries.contains(where: { $0.events.count > 1 }) {
                DisclosureGroup(isExpanded: $showsRawEvents) {
                    VStack(spacing: 7) {
                        ForEach(events) { rawEventRow($0) }
                    }
                    .padding(.top, 8)
                } label: {
                    Text("Raw events")
                        .font(NotchWindowFont.footnote)
                        .foregroundStyle(NotchWindowPalette.tertiaryText)
                }
                .tint(NotchWindowPalette.tertiaryText)
            }
        }
    }

    private func summaryRow(_ summary: ActivityEventSummary) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: symbol(for: summary))
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(color(for: summary))
                .frame(width: 14)
            Text(summary.endedAt, style: .time)
                .font(NotchWindowFont.mono)
                .foregroundStyle(NotchWindowPalette.tertiaryText)
                .frame(width: 54, alignment: .leading)
            Text(summary.title)
                .font(NotchWindowFont.caption)
                .foregroundStyle(.white.opacity(0.76))
            Spacer(minLength: 8)
            if summary.operationCount > 1 {
                Text("\(summary.operationCount) runs")
                    .font(NotchWindowFont.footnote)
                    .foregroundStyle(NotchWindowPalette.tertiaryText)
            }
            if summary.duration >= 1 {
                Text(durationText(summary.duration))
                    .font(NotchWindowFont.footnote)
                    .foregroundStyle(NotchWindowPalette.tertiaryText)
                    .monospacedDigit()
            }
        }
    }

    private func rawEventRow(_ event: AgentEvent) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(event.timestamp, style: .time)
                .font(NotchWindowFont.mono)
                .foregroundStyle(NotchWindowPalette.tertiaryText)
                .frame(width: 64, alignment: .leading)
            Text(event.activity ?? event.resolvedState.displayName)
                .font(NotchWindowFont.footnote)
                .foregroundStyle(.white.opacity(0.55))
            Spacer()
        }
    }

    private func symbol(for summary: ActivityEventSummary) -> String {
        guard let event = summary.events.last else { return "circle" }
        return switch event.type {
        case .toolStarted, .toolCompleted: "terminal"
        case .fileChanged: "doc.badge.ellipsis"
        case .waiting: "questionmark"
        case .completed: "checkmark"
        case .failed: "xmark"
        case .started, .activity: "circle.fill"
        }
    }

    private func color(for summary: ActivityEventSummary) -> Color {
        guard let state = summary.events.last?.resolvedState else { return NotchWindowPalette.tertiaryText }
        return agentStateColor(for: state)
    }

    private func durationText(_ duration: TimeInterval) -> String {
        let seconds = Int(duration.rounded())
        if seconds >= 60 { return "\(seconds / 60)m \(seconds % 60)s" }
        return "\(seconds)s"
    }
}
