import SwiftUI

struct IntegrationSettingsPane: View {
    let runtime: AppRuntime

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: NotchWindowMetrics.sectionSpacing) {
                SettingsHeading(
                    title: "Integrations",
                    detail: "Install a local observer for each agent you use."
                )
                RuntimeHealthBanner(runtime: runtime)
                ProviderIntegrationList(runtime: runtime)
            }
            .settingsPanePadding()
        }
        .background(NotchWindowPalette.background)
    }
}
