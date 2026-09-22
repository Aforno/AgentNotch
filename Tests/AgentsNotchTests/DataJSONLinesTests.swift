import AgentsNotchCore
import XCTest

final class DataJSONLinesTests: XCTestCase {
    func testLinesContainingReturnsWholeRecordsOnce() {
        let data = Data("id-a first\nskip\nid-a id-a twice\nlast id-a".utf8)
        XCTAssertEqual(
            data.lines(containing: Data("id-a".utf8)).map { String(decoding: $0, as: UTF8.self) },
            ["id-a first", "id-a id-a twice", "last id-a"]
        )
        XCTAssertEqual(data.firstNewline, 10)
    }

    func testLinesContainingHonorsSliceIndices() {
        let data = Data("drop\nkeep id\nno".utf8)
        let slice = data[data.firstNewline! + 1..<data.endIndex]
        XCTAssertEqual(
            slice.lines(containing: Data("id".utf8)).map { String(decoding: $0, as: UTF8.self) },
            ["keep id"]
        )
    }
}
