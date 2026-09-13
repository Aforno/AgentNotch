import AgentsNotchCore
import Foundation

protocol HookInstallStrategy: Sendable {
    var hooksURL: URL { get }
    var eventNames: [String] { get }

    func timeout(for eventName: String) -> HookTimeout
    func install(io: HookConfigurationIO, relay: HookRelayIdentity) throws
    func uninstall(io: HookConfigurationIO, relay: HookRelayIdentity) throws
    func containsCurrentRelay(io: HookConfigurationIO, relay: HookRelayIdentity) -> Bool
    func looksInstalled(io: HookConfigurationIO, relay: HookRelayIdentity) -> Bool
    func updateIfNeeded(io: HookConfigurationIO, relay: HookRelayIdentity) throws
}

struct HookConfigurationIO {
    let fileSystem: ProviderFileSystem

    func fileExists(at url: URL) -> Bool {
        fileSystem.manager.fileExists(atPath: url.path)
    }

    func readData(at url: URL) throws -> Data {
        try Data(contentsOf: url)
    }

    func removeItem(at url: URL) throws {
        try fileSystem.manager.removeItem(at: url)
    }

    func readRoot(at url: URL) throws -> (root: [String: Any], originalData: Data?) {
        guard fileSystem.manager.fileExists(atPath: url.path) else {
            return ([:], nil)
        }
        let data = try Data(contentsOf: url)
        guard !data.isEmpty else {
            return ([:], data)
        }
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ProviderIntegrationError.invalidHooksFile(url.path)
        }
        return (root, data)
    }

    func hooksDictionary(in root: [String: Any], hooksURL: URL) throws -> [String: Any] {
        guard let value = root["hooks"] else { return [:] }
        guard let hooks = value as? [String: Any] else {
            throw ProviderIntegrationError.invalidHooksSection(hooksURL.path)
        }
        return hooks
    }

    func writeRoot(_ root: [String: Any], to url: URL, expectedData: Data?) throws {
        let data = try JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys])
        try write(data, to: url, expectedData: expectedData, defaultPermissions: 0o600, preserveExisting: true)
    }

    func write(
        _ data: Data,
        to url: URL,
        expectedData: Data?,
        defaultPermissions: Int,
        preserveExisting: Bool
    ) throws {
        let destination = url.resolvingSymlinksInPath()
        let existingPermissions = (try? fileSystem.manager.attributesOfItem(atPath: destination.path))?[.posixPermissions]
        try fileSystem.manager.createDirectory(
            at: destination.deletingLastPathComponent(),
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        let currentData = fileSystem.manager.fileExists(atPath: destination.path)
            ? try Data(contentsOf: destination)
            : nil
        guard currentData == expectedData else {
            throw ProviderIntegrationError.configurationChanged(url.path)
        }
        try data.write(to: destination, options: .atomic)
        let permissions = preserveExisting ? (existingPermissions ?? defaultPermissions) : defaultPermissions
        try fileSystem.manager.setAttributes(
            [.posixPermissions: permissions],
            ofItemAtPath: destination.path
        )
    }
}

struct GroupedHooksInstall: HookInstallStrategy {
    let hooksURL: URL
    let eventNames: [String]
    let usesClaudeExecForm: Bool
    let timeoutForEvent: @Sendable (String) -> HookTimeout

    init(profile: IntegratedHookProvider, homeDirectoryURL: URL) {
        hooksURL = profile.hooksURL(homeDirectoryURL: homeDirectoryURL)
        eventNames = profile.eventNames
        usesClaudeExecForm = profile == .claudeCode
        timeoutForEvent = { profile.timeout(for: $0) }
    }

    init(
        hooksURL: URL,
        eventNames: [String],
        usesClaudeExecForm: Bool = false,
        timeoutForEvent: @escaping @Sendable (String) -> HookTimeout
    ) {
        self.hooksURL = hooksURL
        self.eventNames = eventNames
        self.usesClaudeExecForm = usesClaudeExecForm
        self.timeoutForEvent = timeoutForEvent
    }

    func timeout(for eventName: String) -> HookTimeout {
        timeoutForEvent(eventName)
    }

    func install(io: HookConfigurationIO, relay: HookRelayIdentity) throws {
        let configuration = try io.readRoot(at: hooksURL)
        var root = configuration.root
        var hooks = try io.hooksDictionary(in: root, hooksURL: hooksURL)
        for eventName in eventNames {
            let newGroups = groupsToInstall(for: eventName, relay: relay)
            if hooks[eventName] == nil {
                hooks[eventName] = newGroups
                continue
            }
            guard var groups = hooks[eventName] as? [[String: Any]] else {
                throw ProviderIntegrationError.invalidHookEvent(eventName, hooksURL.path)
            }
            groups = groups.compactMap { removeOwnedHandlers(from: $0, relay: relay, eventName: eventName) }
            groups.append(contentsOf: newGroups)
            hooks[eventName] = groups
        }

        root["hooks"] = hooks
        try io.writeRoot(root, to: hooksURL, expectedData: configuration.originalData)
        guard containsCurrentRelay(io: io, relay: relay) else {
            throw ProviderIntegrationError.incompleteInstallation
        }
    }

    func uninstall(io: HookConfigurationIO, relay: HookRelayIdentity) throws {
        guard io.fileExists(at: hooksURL) else { return }
        let configuration = try io.readRoot(at: hooksURL)
        var root = configuration.root
        guard root["hooks"] != nil else { return }
        var hooks = try io.hooksDictionary(in: root, hooksURL: hooksURL)

        for eventName in Array(hooks.keys) {
            guard var groups = hooks[eventName] as? [[String: Any]] else { continue }
            groups = groups.compactMap { removeOwnedHandlers(from: $0, relay: relay, eventName: eventName) }
            if groups.isEmpty {
                hooks.removeValue(forKey: eventName)
            } else {
                hooks[eventName] = groups
            }
        }
        root["hooks"] = hooks
        try io.writeRoot(root, to: hooksURL, expectedData: configuration.originalData)
    }

    func containsCurrentRelay(io: HookConfigurationIO, relay: HookRelayIdentity) -> Bool {
        guard let configuration = try? io.readRoot(at: hooksURL),
              let hooks = try? io.hooksDictionary(in: configuration.root, hooksURL: hooksURL)
        else { return false }
        return eventNames.allSatisfy { eventName in
            let groups = hooks[eventName] as? [[String: Any]] ?? []
            if usesClaudeExecForm, relay.answersFromNotch, eventName == "PreToolUse" {
                let passiveRelay = HookRelayIdentity(provider: relay.provider, relayURL: relay.relayURL)
                let hasPassive = groups.contains { group in
                    group["matcher"] as? String == AgentReplyPolicy.claudePassiveToolMatcher
                        && handlers(in: group).contains { passiveRelay.identity(of: $0, eventName: eventName) == .current }
                }
                let hasAnswer = groups.contains { group in
                    group["matcher"] as? String == AgentReplyPolicy.claudeInteractiveToolMatcher
                        && handlers(in: group).contains {
                            $0["async"] as? Bool == false
                                && ($0["timeout"] as? Int) == AgentReplyPolicy.waitSeconds
                                && relay.identity(
                                    of: $0,
                                    eventName: eventName,
                                    blocking: true
                                ) == .current
                        }
                }
                return hasPassive && hasAnswer
            }
            return groups.contains { group in
                handlers(in: group).contains { relay.identity(of: $0, eventName: eventName) == .current }
            }
        }
    }

    func looksInstalled(io: HookConfigurationIO, relay: HookRelayIdentity) -> Bool {
        containsCurrentRelay(io: io, relay: relay) || hasAnyOwnedHandler(io: io, relay: relay)
    }

    func updateIfNeeded(io: HookConfigurationIO, relay: HookRelayIdentity) throws {
        guard !containsCurrentRelay(io: io, relay: relay) else { return }
        try install(io: io, relay: relay)
    }

    private func hasAnyOwnedHandler(io: HookConfigurationIO, relay: HookRelayIdentity) -> Bool {
        guard let configuration = try? io.readRoot(at: hooksURL),
              let hooks = try? io.hooksDictionary(in: configuration.root, hooksURL: hooksURL)
        else { return false }
        return hooks.contains { eventName, value in
            let groups = value as? [[String: Any]] ?? []
            return groups.contains { group in
                handlers(in: group).contains { relay.identity(of: $0, eventName: eventName).isOwned }
            }
        }
    }

    private func removeOwnedHandlers(
        from group: [String: Any],
        relay: HookRelayIdentity,
        eventName: String
    ) -> [String: Any]? {
        guard var hooks = group["hooks"] as? [[String: Any]] else { return group }
        hooks.removeAll { relay.identity(of: $0, eventName: eventName).isOwned }
        guard !hooks.isEmpty else { return nil }
        var updated = group
        updated["hooks"] = hooks
        return updated
    }

    private func handlers(in group: [String: Any]) -> [[String: Any]] {
        group["hooks"] as? [[String: Any]] ?? []
    }

    private func groupsToInstall(for eventName: String, relay: HookRelayIdentity) -> [[String: Any]] {
        if usesClaudeExecForm, relay.answersFromNotch, eventName == "PreToolUse" {
            let passiveRelay = HookRelayIdentity(provider: relay.provider, relayURL: relay.relayURL)
            return [
                [
                    "matcher": AgentReplyPolicy.claudePassiveToolMatcher,
                    "hooks": [passiveRelay.commandHandler(
                        timeout: timeout(for: eventName),
                        claudeExecForm: true,
                        eventName: eventName
                    )],
                ],
                [
                    "matcher": AgentReplyPolicy.claudeInteractiveToolMatcher,
                    "hooks": [relay.commandHandler(
                        timeout: timeout(for: eventName),
                        claudeExecForm: true,
                        eventName: eventName,
                        blocking: true
                    )],
                ],
            ]
        }
        return [[
            "hooks": [relay.commandHandler(
                timeout: timeout(for: eventName),
                claudeExecForm: usesClaudeExecForm,
                eventName: eventName
            )],
        ]]
    }
}

struct CursorHooksInstall: HookInstallStrategy {
    let profile: IntegratedHookProvider
    let homeDirectoryURL: URL

    var hooksURL: URL { profile.hooksURL(homeDirectoryURL: homeDirectoryURL) }
    var eventNames: [String] { profile.eventNames }

    func timeout(for eventName: String) -> HookTimeout {
        profile.timeout(for: eventName)
    }

    func install(io: HookConfigurationIO, relay: HookRelayIdentity) throws {
        let configuration = try io.readRoot(at: hooksURL)
        var root = configuration.root
        var hooks = try io.hooksDictionary(in: root, hooksURL: hooksURL)

        for eventName in eventNames {
            let handler = relay.cursorHandler(timeout: timeout(for: eventName), eventName: eventName)
            guard var handlers = hooks[eventName] as? [[String: Any]] ?? (hooks[eventName] == nil ? [] : nil) else {
                throw ProviderIntegrationError.invalidHookEvent(eventName, hooksURL.path)
            }
            handlers.removeAll { relay.identity(of: $0, eventName: eventName).isOwned }
            handlers.append(handler)
            hooks[eventName] = handlers
        }

        root["version"] = root["version"] ?? 1
        root["hooks"] = hooks
        try io.writeRoot(root, to: hooksURL, expectedData: configuration.originalData)
        guard containsCurrentRelay(io: io, relay: relay) else {
            throw ProviderIntegrationError.incompleteInstallation
        }
    }

    func uninstall(io: HookConfigurationIO, relay: HookRelayIdentity) throws {
        guard io.fileExists(at: hooksURL) else { return }
        let configuration = try io.readRoot(at: hooksURL)
        var root = configuration.root
        guard root["hooks"] != nil else { return }
        var hooks = try io.hooksDictionary(in: root, hooksURL: hooksURL)

        for eventName in Array(hooks.keys) {
            guard var handlers = hooks[eventName] as? [[String: Any]] else { continue }
            handlers.removeAll { relay.identity(of: $0, eventName: eventName).isOwned }
            if handlers.isEmpty {
                hooks.removeValue(forKey: eventName)
            } else {
                hooks[eventName] = handlers
            }
        }

        root["hooks"] = hooks
        try io.writeRoot(root, to: hooksURL, expectedData: configuration.originalData)
    }

    func containsCurrentRelay(io: HookConfigurationIO, relay: HookRelayIdentity) -> Bool {
        guard let configuration = try? io.readRoot(at: hooksURL),
              let hooks = try? io.hooksDictionary(in: configuration.root, hooksURL: hooksURL)
        else { return false }
        return eventNames.allSatisfy { eventName in
            let handlers = hooks[eventName] as? [[String: Any]] ?? []
            return handlers.contains { relay.identity(of: $0, eventName: eventName) == .current }
        }
    }

    func looksInstalled(io: HookConfigurationIO, relay: HookRelayIdentity) -> Bool {
        containsCurrentRelay(io: io, relay: relay) || hasAnyOwnedHandler(io: io, relay: relay)
    }

    func updateIfNeeded(io: HookConfigurationIO, relay: HookRelayIdentity) throws {
        guard !containsCurrentRelay(io: io, relay: relay) else { return }
        try install(io: io, relay: relay)
    }

    private func hasAnyOwnedHandler(io: HookConfigurationIO, relay: HookRelayIdentity) -> Bool {
        guard let configuration = try? io.readRoot(at: hooksURL),
              let hooks = try? io.hooksDictionary(in: configuration.root, hooksURL: hooksURL)
        else { return false }
        return hooks.contains { eventName, value in
            let handlers = value as? [[String: Any]] ?? []
            return handlers.contains { relay.identity(of: $0, eventName: eventName).isOwned }
        }
    }
}

struct OpenCodePluginInstall: HookInstallStrategy {
    let homeDirectoryURL: URL

    var hooksURL: URL {
        IntegratedHookProvider.openCode.hooksURL(homeDirectoryURL: homeDirectoryURL)
    }

    var eventNames: [String] { [] }

    func timeout(for eventName: String) -> HookTimeout {
        IntegratedHookProvider.openCode.timeout(for: eventName)
    }

    func install(io: HookConfigurationIO, relay: HookRelayIdentity) throws {
        let currentData = io.fileExists(at: hooksURL) ? try io.readData(at: hooksURL) : nil
        if let currentData, !OpenCodePluginTemplate.isOwned(currentData) {
            throw ProviderIntegrationError.existingOpenCodePlugin(hooksURL.path)
        }
        try writePlugin(io: io, relay: relay, expectedData: currentData)
        guard containsCurrentRelay(io: io, relay: relay) else {
            throw ProviderIntegrationError.incompleteInstallation
        }
    }

    func uninstall(io: HookConfigurationIO, relay: HookRelayIdentity) throws {
        _ = relay
        guard io.fileExists(at: hooksURL) else { return }
        let data = try io.readData(at: hooksURL)
        guard OpenCodePluginTemplate.isOwned(data) else { return }
        try io.removeItem(at: hooksURL)
    }

    func containsCurrentRelay(io: HookConfigurationIO, relay: HookRelayIdentity) -> Bool {
        guard let data = try? io.readData(at: hooksURL), OpenCodePluginTemplate.isOwned(data) else {
            return false
        }
        let source = String(decoding: data, as: UTF8.self)
        return source.contains(relay.relayURL.path) && source.contains("--provider\", \"opencode")
    }

    func looksInstalled(io: HookConfigurationIO, relay: HookRelayIdentity) -> Bool {
        containsCurrentRelay(io: io, relay: relay)
    }

    func updateIfNeeded(io: HookConfigurationIO, relay: HookRelayIdentity) throws {
        guard io.fileExists(at: hooksURL) else { return }
        let currentData = try io.readData(at: hooksURL)
        let pluginData = OpenCodePluginTemplate.data(relayURL: relay.relayURL)
        guard OpenCodePluginTemplate.isOwned(currentData), currentData != pluginData else { return }
        try writePlugin(io: io, relay: relay, expectedData: currentData)
    }

    private func writePlugin(io: HookConfigurationIO, relay: HookRelayIdentity, expectedData: Data?) throws {
        try io.write(
            OpenCodePluginTemplate.data(relayURL: relay.relayURL),
            to: hooksURL,
            expectedData: expectedData,
            defaultPermissions: 0o600,
            preserveExisting: false
        )
    }
}

/// Antigravity's `hooks.json` maps named hooks to events. PostToolUse uses
/// matcher groups; PreInvocation/Stop are handler lists. `*` is not a valid
/// matcher regex (`Invalid matcher regex`); match all with `.*`.
struct AntigravityHooksInstall: HookInstallStrategy {
    static let hookName = "agentnotch"
    static let matchAllTools = ".*"
    private static let matcherEvents: Set<String> = ["PostToolUse"]

    let profile: IntegratedHookProvider
    let homeDirectoryURL: URL

    var hooksURL: URL { profile.hooksURL(homeDirectoryURL: homeDirectoryURL) }
    var eventNames: [String] { profile.eventNames }

    func timeout(for eventName: String) -> HookTimeout {
        profile.timeout(for: eventName)
    }

    func install(io: HookConfigurationIO, relay: HookRelayIdentity) throws {
        let configuration = try io.readRoot(at: hooksURL)
        var root = configuration.root
        if root[Self.hookName] != nil, root[Self.hookName] as? [String: Any] == nil {
            throw ProviderIntegrationError.invalidHookEvent(Self.hookName, hooksURL.path)
        }
        var hook: [String: Any] = [:]
        for eventName in eventNames {
            hook[eventName] = entriesToInstall(for: eventName, relay: relay)
        }
        root[Self.hookName] = hook
        try io.writeRoot(root, to: hooksURL, expectedData: configuration.originalData)
        guard containsCurrentRelay(io: io, relay: relay) else {
            throw ProviderIntegrationError.incompleteInstallation
        }
    }

    func uninstall(io: HookConfigurationIO, relay: HookRelayIdentity) throws {
        guard io.fileExists(at: hooksURL) else { return }
        let configuration = try io.readRoot(at: hooksURL)
        var root = configuration.root
        guard let hook = root[Self.hookName] as? [String: Any],
              hasOwnedHandler(in: hook, relay: relay)
        else { return }
        root.removeValue(forKey: Self.hookName)
        try io.writeRoot(root, to: hooksURL, expectedData: configuration.originalData)
    }

    func containsCurrentRelay(io: HookConfigurationIO, relay: HookRelayIdentity) -> Bool {
        guard let hook = namedHook(io: io) else { return false }
        let configuredEvents = Set(hook.keys.filter { $0 != "enabled" })
        guard configuredEvents == Set(eventNames) else { return false }
        return eventNames.allSatisfy { eventName in
            handlers(in: hook, eventName: eventName).contains {
                relay.identity(of: $0, eventName: eventName) == .current
            }
        }
    }

    func looksInstalled(io: HookConfigurationIO, relay: HookRelayIdentity) -> Bool {
        containsCurrentRelay(io: io, relay: relay)
            || namedHook(io: io).map { hasOwnedHandler(in: $0, relay: relay) } == true
    }

    func updateIfNeeded(io: HookConfigurationIO, relay: HookRelayIdentity) throws {
        guard !containsCurrentRelay(io: io, relay: relay) else { return }
        try install(io: io, relay: relay)
    }

    private func namedHook(io: HookConfigurationIO) -> [String: Any]? {
        guard let configuration = try? io.readRoot(at: hooksURL) else { return nil }
        return configuration.root[Self.hookName] as? [String: Any]
    }

    private func hasOwnedHandler(in hook: [String: Any], relay: HookRelayIdentity) -> Bool {
        hook.keys.contains { eventName in
            handlers(in: hook, eventName: eventName).contains {
                relay.identity(of: $0, eventName: eventName).isOwned
            }
        }
    }

    private func handlers(in hook: [String: Any], eventName: String) -> [[String: Any]] {
        guard let entries = hook[eventName] as? [[String: Any]] else { return [] }
        if usesMatcherGroups(eventName) {
            return entries.flatMap { $0["hooks"] as? [[String: Any]] ?? [] }
        }
        return entries
    }

    private func entriesToInstall(for eventName: String, relay: HookRelayIdentity) -> [[String: Any]] {
        let handler = relay.commandHandler(
            timeout: timeout(for: eventName),
            claudeExecForm: false,
            eventName: eventName,
            includeEventName: true
        )
        if usesMatcherGroups(eventName) {
            return [[
                "matcher": Self.matchAllTools,
                "hooks": [handler],
            ]]
        }
        return [handler]
    }

    private func usesMatcherGroups(_ eventName: String) -> Bool {
        Self.matcherEvents.contains(eventName)
    }
}
