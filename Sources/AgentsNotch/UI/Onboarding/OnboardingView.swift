import AgentsNotchCore
import SwiftUI

struct OnboardingView: View {
    let runtime: AppRuntime
    let onDone: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Provider rows grow with trust instructions and install errors, so
            // the list scrolls and the finish actions stay pinned. Setup is the
            // first thing a new user sees; its buttons cannot drift off-window.
            ScrollView {
                setupContent
                    .padding(24)
            }
            NotchHairline()
            actions
                .padding(.horizontal, 24)
                .padding(.vertical, 16)
        }
        .frame(
            minWidth: 560,
            idealWidth: 640,
            maxWidth: .infinity,
            minHeight: 420,
            idealHeight: 560,
            maxHeight: .infinity
        )
        .foregroundStyle(NotchWindowPalette.primaryText)
        .deepBlackWindowSurface()
    }

    private var setupContent: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(alignment: .top, spacing: 16) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 64, height: 64)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 5) {
                    Text("Agents should find you—not interrupt you")
                        .font(NotchWindowFont.title)
                        .foregroundStyle(NotchWindowPalette.primaryText)
                    Text("Install one or more local observers, then leave the notch collapsed until an agent needs input.")
                        .font(NotchWindowFont.body)
                        .foregroundStyle(NotchWindowPalette.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            RuntimeHealthBanner(runtime: runtime)

            ProviderIntegrationList(runtime: runtime, allowsRemove: false)

            Label(
                "Observers run locally. Agent Notch does not upload source code or session history.",
                systemImage: "lock"
            )
            .font(NotchWindowFont.footnote)
            .foregroundStyle(NotchWindowPalette.secondaryText)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var actions: some View {
        HStack {
            Button("Open Activity Center") { runtime.openActivityCenter() }
                .buttonStyle(NotchPillButtonStyle())
            Spacer()
            Button(finishButtonTitle) {
                UserDefaults.standard.set(
                    true,
                    forKey: AppPreferences.Key.hasCompletedOnboarding
                )
                onDone()
            }
            .buttonStyle(NotchPillButtonStyle(prominent: true))
            .keyboardShortcut(.defaultAction)
        }
    }

    private var finishButtonTitle: String {
        runtime.integrations.contains { $0.status.isInstalled }
            ? "Finish Setup"
            : "Finish without Connecting"
    }
}
