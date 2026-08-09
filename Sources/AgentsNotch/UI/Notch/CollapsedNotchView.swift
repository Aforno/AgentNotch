import AgentsNotchCore
import SwiftUI

struct CollapsedNotchView: View {
    let activeProviders: [AgentProvider]
    let activeCount: Int

    var body: some View {
        Color.clear
            .overlay(alignment: .leading) {
                leadingStatus
                    .padding(.leading, DynamicIslandSpacing.compactInset)
            }
            .overlay(alignment: .trailing) {
                providerStack
                    .padding(.trailing, DynamicIslandSpacing.compactInset)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .accessibilityElement(children: .combine)
            .accessibilityLabel(accessibilitySummary)
    }

    private var providerStack: some View {
        let providers = Array(activeProviders.reversed())
        let reveal = providerReveal(for: providers.count)

        return ZStack(alignment: .trailing) {
            ForEach(Array(providers.enumerated()), id: \.element) { index, provider in
                ZStack {
                    Circle()
                        .fill(.black)

                    Circle()
                        .stroke(.white.opacity(0.18), lineWidth: 0.75)

                    ProviderIconView(provider: provider, size: 13)
                        .foregroundStyle(.white.opacity(0.94))
                }
                .frame(
                    width: DynamicIslandSpacing.compactProviderMarkSize,
                    height: DynamicIslandSpacing.compactProviderMarkSize
                )
                .offset(x: -CGFloat(providers.count - index - 1) * reveal)
            }
        }
        .frame(
            width: DynamicIslandSpacing.compactProviderStackWidth,
            height: DynamicIslandSpacing.compactProviderMarkSize,
            alignment: .trailing
        )
        .accessibilityHidden(true)
    }

    private func providerReveal(for count: Int) -> CGFloat {
        guard count > 1 else { return 0 }
        let availableTravel = DynamicIslandSpacing.compactProviderStackWidth
            - DynamicIslandSpacing.compactProviderMarkSize
        return min(
            DynamicIslandSpacing.compactProviderReveal,
            availableTravel / CGFloat(count - 1)
        )
    }

    private var leadingStatus: some View {
        HStack(spacing: DynamicIslandSpacing.related) {
            StateIndicator(state: .running, size: 7)
            Text("\(activeCount)")
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.92))
        }
        .fixedSize()
    }

    private var accessibilitySummary: String {
        guard activeCount > 0 else { return "No active agents" }
        let count = activeCount == 1 ? "1 active agent" : "\(activeCount) active agents"
        let names = activeProviders.map(\.displayName).joined(separator: ", ")
        return "\(count): \(names)"
    }
}
