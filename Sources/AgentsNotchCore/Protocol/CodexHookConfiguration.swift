public enum CodexHookConfiguration {
    public static func timeout(for eventName: String) -> HookTimeout {
        eventName == "SessionEnd" ? .seconds(3) : .seconds(5)
    }
}
