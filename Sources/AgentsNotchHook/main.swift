import AgentsNotchCore
import Foundation

HookProcessIO.ignoreBrokenPipes()

let input = HookProcessIO.readStdin()
let invocation = HookProcessInvocation.parse()

if invocation.skipCompatibilityHook {
    HookProcessIO.writePassiveResponse(for: invocation.configuredProvider)
    exit(EXIT_SUCCESS)
}

do {
    let payload = try AgentHookInput.decode(input)
    let enriched = ProviderHookEnricher.enrich(payload, provider: invocation.provider)
    if var event = AgentHookEventMapper.map(
        enriched.payload,
        provider: invocation.provider,
        permissionRequestRequiresUserInput: enriched.permissionRequestRequiresUserInput
    ) {
        if let preferredTask = enriched.preferredTask {
            let shouldReplace = enriched.replaceExistingTask
                || AgentTaskTitle.displayable(event.task ?? "") == nil
            if shouldReplace {
                event.task = preferredTask
                if let titleSource = enriched.titleSource {
                    var metadata = event.metadata ?? [:]
                    metadata["titleSource"] = titleSource
                    event.metadata = metadata
                }
            }
        }
        event.origin = HookProcessIO.origin()
        if invocation.isSelfTest {
            var metadata = event.metadata ?? [:]
            metadata["source"] = "self-test"
            event.metadata = metadata
        }
        if let rawURL = ProcessInfo.processInfo.environment["AGENTS_NOTCH_APPLICATION_URL"] {
            event.applicationURL = URL(string: rawURL)
        }
        try? UnixSocketClient.send(event, to: invocation.socketURL)
    }
    if var workflowEvent = enriched.workflowEvent {
        if invocation.isSelfTest {
            var metadata = workflowEvent.metadata ?? [:]
            metadata["source"] = "self-test"
            workflowEvent.metadata = metadata
        }
        try? UnixSocketClient.send(workflowEvent, to: invocation.socketURL)
    }
    HookProcessIO.writePassiveResponse(for: invocation.provider)
} catch {
    HookProcessIO.writePassiveResponse(for: invocation.provider)
}
