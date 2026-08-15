import XCTest
@testable import AgentsNotchCore

final class FlexibleDecodingTests: XCTestCase {
    private struct Sample: Decodable {
        let message: String?
        let stamped: Date?

        private enum CodingKeys: String, CodingKey {
            case message, error
            case stamped, createdAt = "created_at"
        }

        init(from decoder: Decoder) throws {
            let values = try decoder.container(keyedBy: CodingKeys.self)
            message = values.decodeFlexibleStringIfPresent(forKey: .message)
                ?? values.decodeFlexibleStringIfPresent(forKey: .error)
            stamped = values.decodeFlexibleDateIfPresent(forKeys: [.stamped, .createdAt])
        }
    }

    func testFlexibleStringReadsNestedErrorMessage() throws {
        let sample = try decode(#"{ "error": { "message": "boom" } }"#)
        XCTAssertEqual(sample.message, "boom")
    }

    func testFlexibleDateReadsFractionalISO8601AndEpochMillis() throws {
        let iso = try decode(#"{ "stamped": "2026-08-14T12:00:00.250Z" }"#)
        XCTAssertNotNil(iso.stamped)

        let seconds = try decode(#"{ "created_at": 100 }"#)
        XCTAssertEqual(seconds.stamped?.timeIntervalSince1970, 100)

        let millis = try decode(#"{ "created_at": 10000000000001 }"#)
        XCTAssertEqual(try XCTUnwrap(millis.stamped).timeIntervalSince1970, 10_000_000_000.001, accuracy: 0.001)
    }

    func testDecodeEitherPrefersFirstKeyThenAlias() throws {
        struct Pair: Decodable {
            let value: String
            private enum CodingKeys: String, CodingKey { case camel, snake }
            init(from decoder: Decoder) throws {
                let values = try decoder.container(keyedBy: CodingKeys.self)
                value = try values.decodeEither(String.self, forKey: .camel, or: .snake)
            }
        }

        let first = try JSONDecoder().decode(Pair.self, from: Data(#"{ "camel": "a", "snake": "b" }"#.utf8))
        XCTAssertEqual(first.value, "a")
        let alias = try JSONDecoder().decode(Pair.self, from: Data(#"{ "snake": "b" }"#.utf8))
        XCTAssertEqual(alias.value, "b")
    }

    private func decode(_ json: String) throws -> Sample {
        try JSONDecoder().decode(Sample.self, from: Data(json.utf8))
    }
}
