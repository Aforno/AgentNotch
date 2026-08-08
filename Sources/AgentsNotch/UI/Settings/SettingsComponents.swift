import SwiftUI

struct PageHeader: View {
    let title: String
    let subtitle: String
    let symbol: String

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: symbol)
                .font(.system(size: 19, weight: .semibold))
                .foregroundStyle(Color.accentColor)
                .frame(width: 42, height: 42)
                .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 12, style: .continuous))

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 22, weight: .bold))
                Text(subtitle)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }
        }
    }
}

struct SettingsCard<Content: View>: View {
    private let title: String?
    @ViewBuilder private let content: Content

    init(title: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let title {
                Text(title.uppercased())
                    .font(.system(size: 10, weight: .semibold))
                    .tracking(0.7)
                    .foregroundStyle(.secondary)
                    .padding(.bottom, 13)
            }

            content
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(.separator.opacity(0.55), lineWidth: 1)
        }
    }
}

struct PreferenceRow<Accessory: View>: View {
    let title: String
    let detail: String
    @ViewBuilder let accessory: Accessory

    init(title: String, detail: String, @ViewBuilder accessory: () -> Accessory) {
        self.title = title
        self.detail = detail
        self.accessory = accessory()
    }

    var body: some View {
        HStack(spacing: 18) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 13, weight: .medium))
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 16)
            accessory
        }
        .frame(minHeight: 36)
    }
}

struct SettingsDivider: View {
    var body: some View {
        Divider()
            .padding(.vertical, 13)
    }
}

struct InlineMessage: View {
    let text: String
    let symbol: String
    let color: Color

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: symbol)
                .foregroundStyle(color)
            Text(text)
                .font(.caption)
                .foregroundStyle(color)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
        }
    }
}

struct StatusBadge: View {
    let status: ProviderIntegrationStatus

    private var color: Color {
        switch status {
        case .ready: .green
        case .installedNeedsTrust: .orange
        case .notInstalled: .secondary
        case .unavailable: .red
        }
    }

    var body: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(color)
                .frame(width: 6, height: 6)
            Text(status.title)
                .font(.system(size: 11, weight: .medium))
        }
        .foregroundStyle(color)
        .accessibilityElement(children: .combine)
    }
}

#if DEBUG
struct DebugAction {
    let title: String
    let role: ButtonRole?
    let action: () -> Void

    init(_ title: String, role: ButtonRole? = nil, action: @escaping () -> Void) {
        self.title = title
        self.role = role
        self.action = action
    }
}

struct DebugActionCard: View {
    let title: String
    let actions: [DebugAction]

    init(title: String, @DebugActionBuilder actions: () -> [DebugAction]) {
        self.title = title
        self.actions = actions()
    }

    private let columns = [GridItem(.adaptive(minimum: 120), spacing: 8)]

    var body: some View {
        SettingsCard(title: title) {
            LazyVGrid(columns: columns, alignment: .leading, spacing: 8) {
                ForEach(Array(actions.enumerated()), id: \.offset) { _, item in
                    Button(item.title, role: item.role, action: item.action)
                        .buttonStyle(.bordered)
                        .frame(maxWidth: .infinity)
                }
            }
        }
    }
}

@resultBuilder
enum DebugActionBuilder {
    static func buildBlock(_ components: DebugAction...) -> [DebugAction] { components }
}
#endif
