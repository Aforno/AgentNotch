import AgentsNotchCore
import XCTest

final class UnixReplySocketTests: XCTestCase {
    func testReplyRoundTripsAfterHello() throws {
        let socketURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("an-reply-\(UUID().uuidString.prefix(8)).sock")
        let server = UnixReplyServer(socketURL: socketURL)
        try server.start()
        defer {
            server.stop()
            try? FileManager.default.removeItem(atPath: socketURL.path + ".lock")
        }

        let replyId = UUID()
        let helloReady = expectation(description: "hook registered")
        let answered = expectation(description: "hook received decision")
        DispatchQueue.global(qos: .userInitiated).async {
            let reply = UnixReplyClient.awaitReply(
                id: replyId,
                socketURL: socketURL,
                timeoutSeconds: 2,
                afterRegistration: { helloReady.fulfill() }
            )
            XCTAssertEqual(reply?.decision, .allow)
            XCTAssertEqual(reply?.replyId, replyId)
            answered.fulfill()
        }

        wait(for: [helloReady], timeout: 2)
        XCTAssertTrue(server.isPending(replyId))
        XCTAssertTrue(server.submit(AgentReply(replyId: replyId, decision: .allow)))
        wait(for: [answered], timeout: 2)
    }

    func testDisconnectedHookIsDroppedFromPending() throws {
        let socketURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("an-reply-\(UUID().uuidString.prefix(8)).sock")
        let disconnected = expectation(description: "disconnect is published")
        let server = UnixReplyServer(socketURL: socketURL) { replyIDs in
            if replyIDs.isEmpty { disconnected.fulfill() }
        }
        try server.start()
        defer { server.stop() }

        let replyId = UUID()
        let helloReady = expectation(description: "hook registered")
        let timedOut = expectation(description: "hook timed out")
        DispatchQueue.global(qos: .userInitiated).async {
            let reply = UnixReplyClient.awaitReply(
                id: replyId,
                socketURL: socketURL,
                timeoutSeconds: 1,
                afterRegistration: { helloReady.fulfill() }
            )
            XCTAssertNil(reply)
            timedOut.fulfill()
        }

        wait(for: [helloReady], timeout: 2)
        XCTAssertTrue(server.isPending(replyId))
        wait(for: [timedOut], timeout: 3)
        wait(for: [disconnected], timeout: 2)
        XCTAssertFalse(server.isPending(replyId), "timed-out hook must close and leave pending")
        XCTAssertFalse(server.submit(AgentReply(replyId: replyId, decision: .allow)))
    }

    func testSubmitUnknownReplyIdReturnsFalse() throws {
        let socketURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("an-reply-\(UUID().uuidString.prefix(8)).sock")
        let server = UnixReplyServer(socketURL: socketURL)
        try server.start()
        defer { server.stop() }
        XCTAssertFalse(server.submit(AgentReply(replyId: UUID(), decision: .deny)))
    }
}
