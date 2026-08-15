import Foundation

extension KeyedDecodingContainer {
    func decodeEither<T: Decodable>(
        _ type: T.Type,
        forKey first: Key,
        or second: Key
    ) throws -> T {
        // contains() is true for JSON null. decode() then throws valueNotFound
        // and never tries the snake_case alias (e.g. hookEventName:null with
        // a valid hook_event_name).
        if let value = try? decodeIfPresent(type, forKey: first) { return value }
        return try decode(type, forKey: second)
    }

    func decodeEitherIfPresent<T: Decodable>(
        _ type: T.Type,
        forKey first: Key,
        or second: Key
    ) throws -> T? {
        if let value = try? decodeIfPresent(type, forKey: first) { return value }
        return try decodeIfPresent(type, forKey: second)
    }

    func decodeFlexibleStringIfPresent(forKey key: Key) -> String? {
        guard contains(key) else { return nil }
        if let value = try? decodeIfPresent(String.self, forKey: key) {
            return value
        }
        guard let value = try? decode(JSONValue.self, forKey: key) else { return nil }
        if let string = value.stringValue { return string }
        if let message = value.objectValue?["message"]?.stringValue { return message }
        return value.objectValue?["error"]?.stringValue
    }

    func decodeFlexibleDateIfPresent(forKeys keys: [Key]) -> Date? {
        for key in keys where contains(key) {
            if let value = try? decode(String.self, forKey: key) {
                if let date = try? Date(
                    value,
                    strategy: Date.ISO8601FormatStyle(includingFractionalSeconds: true)
                ) {
                    return date
                }
                if let date = try? Date(value, strategy: Date.ISO8601FormatStyle()) {
                    return date
                }
            }
            if let value = try? decode(Double.self, forKey: key) {
                let seconds = value > 10_000_000_000 ? value / 1_000 : value
                return Date(timeIntervalSince1970: seconds)
            }
        }
        return nil
    }
}
