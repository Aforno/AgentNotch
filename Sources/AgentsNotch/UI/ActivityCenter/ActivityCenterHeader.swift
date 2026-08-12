import SwiftUI

struct ActivityCenterHeader: View {
    let sessionCount: Int
    let activeCount: Int
    let attentionCount: Int
    let groupingMode: Binding<ActivityGroupingMode>
    let canClearHistory: Bool
    let requestClearHistory: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 1) {
                Text("Activity")
                    .font(NotchWindowFont.display)
                    .foregroundStyle(.white.opacity(0.92))
                Text(sessionCount == 1 ? "1 session on this Mac" : "\(sessionCount) sessions on this Mac")
                    .font(NotchWindowFont.footnote)
                    .foregroundStyle(NotchWindowPalette.secondaryText)
            }
            Spacer()
            ActivityMetric(title: "Active", value: activeCount, color: .blue)
            ActivityMetric(title: "Attention", value: attentionCount, color: .orange)
            Menu {
                Picker("Session Grouping", selection: groupingMode) {
                    ForEach(ActivityGroupingMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                Divider()
                Button("Clear Completed History", role: .destructive, action: requestClearHistory)
                    .disabled(!canClearHistory)
            } label: {
                NotchIconControlLabel(systemName: "ellipsis").contentShape(Rectangle())
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("Activity options")
        }
        .padding(.horizontal, NotchWindowMetrics.contentInset)
        .padding(.vertical, 14)
        .background(NotchWindowPalette.background)
    }
}

struct ActivityCenterEmptyDetail: View {
    var body: some View {
        VStack(spacing: 10) {
            NotchShape(bottomRadius: 12)
                .fill(.white.opacity(0.09))
                .frame(width: 66, height: 34)
            Text("Select a session")
                .font(NotchWindowFont.title)
                .foregroundStyle(.white.opacity(0.82))
            Text("Plans, workflows, files, and recent events appear here.")
                .font(NotchWindowFont.caption)
                .foregroundStyle(NotchWindowPalette.secondaryText)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(NotchWindowPalette.background)
    }
}
