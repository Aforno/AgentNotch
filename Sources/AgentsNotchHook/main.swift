import AgentsNotchCore
import Foundation
import os

private let logger = Logger(subsystem: "com.afonsoferreira.AgentNotch", category: "hook")

HookProcessIO.ignoreBrokenPipes()

let input = HookProcessIO.readStdin()
let invocation = HookProcessInvocation.parse()

if invocation.skipCompatibilityHook {
    HookProcessIO.writePassiveResponse(for: invocation.configuredProvider)
    exit(EXIT_SUCCESS)
}

/// Marks self-test events so the notch can distinguish them from real traffic.
func stampSelfTest(_ event: inout AgentEvent) {
    guard invocation.isSelfTest else { return }
    var metadata = event.metadata ?? [:]
    metadata["source"] = "self-test"
    event.metadata = metadata
}

if input.isEmpty {
    logger.error("Received empty hook payload on stdin for provider \(invocation.provider.rawValue, privacy: .public)")
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
        stampSelfTest(&event)
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
                    HookProcessIO.sendEvent(waitingEvent, to: invocation.socketURL)
                }
            ) {
                logger.info("Delivered notch reply \(pending.kind.rawValue, privacy: .public) for session \(event.sessionId, privacy: .private)")
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
                logger.info("No notch reply in time; failing open for session \(event.sessionId, privacy: .private)")
                event.pendingReply = nil
                HookProcessIO.sendEvent(event, to: invocation.socketURL)
            }
        } else {
            HookProcessIO.sendEvent(event, to: invocation.socketURL)
        }
    }
    if var workflowEvent = enriched.workflowEvent {
        stampSelfTest(&workflowEvent)
        HookProcessIO.sendEvent(workflowEvent, to: invocation.socketURL)
    }
    if answered {
        exit(EXIT_SUCCESS)
    }
} catch {
    logger.error(
        "Could not decode hook payload (\(input.count) bytes) for provider \(invocation.provider.rawValue, privacy: .public): \(String(describing: error), privacy: .public)"
    )
}
HookProcessIO.writePassiveResponse(for: invocation.provider)
