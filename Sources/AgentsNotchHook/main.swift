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
    var answered = false
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
        if invocation.answersFromNotch,
           event.type == .waiting,
           AgentReplyPolicy.canDecide(provider: invocation.provider),
           AgentReplyPolicy.waitsForAnswer(
            eventName: enriched.payload.hookEventName,
            toolName: enriched.payload.toolName
           ),
           let pending = AgentReplyPromptBuilder.make(
            payload: enriched.payload,
            replyId: UUID()
           ),
           AgentReplyPolicy.shouldAwaitReply(pending)
        {
            event.pendingReply = pending
            let waitingEvent = event
            if let reply = UnixReplyClient.awaitReply(
                id: pending.replyId,
                socketURL: invocation.replySocketURL,
                afterRegistration: {
                    try? UnixSocketClient.send(waitingEvent, to: invocation.socketURL)
                }
            ) {
                HookProcessIO.writeDecision(
                    ProviderDecisionMapper.data(
                        provider: invocation.provider,
                        payload: enriched.payload,
                        reply: reply
                    )
                )
                answered = true
            } else {
                // The native provider prompt remains authoritative, but answer
                // mode must never make the observer signal disappear.
                var observerEvent = event
                observerEvent.pendingReply = nil
                try? UnixSocketClient.send(observerEvent, to: invocation.socketURL)
            }
        } else {
            try? UnixSocketClient.send(event, to: invocation.socketURL)
        }
    }
    if var workflowEvent = enriched.workflowEvent {
        if invocation.isSelfTest {
            var metadata = workflowEvent.metadata ?? [:]
            metadata["source"] = "self-test"
            workflowEvent.metadata = metadata
        }
        try? UnixSocketClient.send(workflowEvent, to: invocation.socketURL)
    }
    if answered {
        exit(EXIT_SUCCESS)
    }
    HookProcessIO.writePassiveResponse(for: invocation.provider)
} catch {
    HookProcessIO.writePassiveResponse(for: invocation.provider)
}
