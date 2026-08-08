public enum CodexHookConfiguration {
    public static func timeout(for eventName: String) -> Int {
        eventName == "SessionEnd" ? 3 : 5
    }
}
