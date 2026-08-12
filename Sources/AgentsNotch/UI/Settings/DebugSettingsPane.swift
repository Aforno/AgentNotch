import AgentsNotchCore
import SwiftUI

#if DEBUG
struct DebugSettingsPane: View {
    let runtime: AppRuntime
    let debugMode: Binding<Bool>

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                SettingsHeading(title: "Debug", detail: "Preview agent states without a live session.")
                SettingsSection(title: "Simulator") {
                    SettingsToggleRow(
                        title: "Enable debug simulator",
                        detail: "Inject synthetic agent activity into the notch and Activity Center.",
                        isOn: debugMode
                    )
                }
                if debugMode.wrappedValue {
                    SettingsSection(title: "Agent States") {
                        SettingsControlRow(title: "Inject state", detail: "Push one simulated agent into a state.") {
                            HStack(spacing: 8) {
                                stateButton("Running", .running)
                                stateButton("Editing", .editing)
                                stateButton("Needs Approval", .waitingForUser)
                                stateButton("Completed", .completed)
                                stateButton("Failed", .failed)
                            }
                        }
                    }
                    SettingsSection(title: "Structured Activity") {
                        SettingsControlRow(title: "Inject activity", detail: "Preview plans, workflows, and agent groups.") {
                            HStack(spacing: 8) {
                                Button("Plan") { runtime.simulator.simulatePlan() }
                                Button("Workflow") { runtime.simulator.simulateWorkflow() }
                                Button("Subagents") { runtime.simulator.simulateSubagents() }
                                Button("Concurrent") { runtime.simulator.runConcurrentDemo() }
                                Button("Clear", role: .destructive) { runtime.simulator.reset() }
                            }
                            .buttonStyle(NotchPillButtonStyle())
                        }
                    }
                }
            }
            .settingsPanePadding()
        }
        .background(NotchWindowPalette.background)
    }

    private func stateButton(_ title: String, _ state: AgentState) -> some View {
        Button(title) { runtime.simulator.simulate(state) }
            .buttonStyle(NotchPillButtonStyle())
    }
}
#endif
