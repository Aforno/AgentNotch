import AgentsNotchCore
import XCTest

final class GrokSessionContextResolverTests: XCTestCase {
    func testResolvesChildRelationshipAndWorkflowPhasesFromWorkspaceMetadata() throws {
        let temporary = FileManager.default.temporaryDirectory
            .appendingPathComponent("AgentsNotch-GrokContext-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: temporary) }

        let parent = "parent-session"
        let child = "child-session"
        let parentDirectory = temporary
            .appendingPathComponent("sessions/%2Ftmp%2FAgentsNotch", isDirectory: true)
            .appendingPathComponent(parent, isDirectory: true)
        let metadataDirectory = parentDirectory
            .appendingPathComponent("subagents", isDirectory: true)
            .appendingPathComponent(child, isDirectory: true)
        let workflowDirectory = parentDirectory
            .appendingPathComponent("workflows/run", isDirectory: true)
        try FileManager.default.createDirectory(at: metadataDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: workflowDirectory, withIntermediateDirectories: true)

        let workflowStateURL = workflowDirectory.appendingPathComponent("state.json")
        try Data("""
        {
          "parent_session_id": "\(parent)",
          "subagent_type": "general-purpose",
          "description": "audit:core-models"
        }
        """.utf8).write(to: metadataDirectory.appendingPathComponent("meta.json"))
        try Data("""
        {
          "version": 4,
          "state": {
            "run_id": "workflow-1",
            "name": "audit-and-fix",
            "objective": "Audit and fix Agents Notch",
            "status": "active",
            "phases": [
              {"title": "Baseline"},
              {"title": "Audit"},
              {"title": "Verify"}
            ],
            "current_phase": "Audit"
          }
        }
        """.utf8).write(to: workflowStateURL)
        let workflowUpdatedAt = Date(timeIntervalSince1970: 1_786_270_000)
        try FileManager.default.setAttributes(
            [.modificationDate: workflowUpdatedAt],
            ofItemAtPath: workflowStateURL.path
        )

        let payload = try JSONDecoder().decode(AgentHookPayload.self, from: Data("""
        {
          "sessionId": "\(child)",
          "cwd": "/tmp/AgentsNotch",
          "workspaceRoot": "/tmp/AgentsNotch",
          "hookEventName": "post_tool_use",
          "toolName": "grep"
        }
        """.utf8))
        let context = GrokSessionContextResolver.resolve(payload, grokHome: temporary)

        XCTAssertEqual(context.parentSessionId, parent)
        XCTAssertEqual(context.agentRole, "audit:core-models")
        XCTAssertEqual(context.workflowOwnerSessionId, parent)
        XCTAssertEqual(context.workflowTask, "Audit and fix Agents Notch")
        XCTAssertEqual(context.workflowPhase, "Audit")
        XCTAssertEqual(context.workflowState, .running)
        XCTAssertEqual(context.workflowUpdate?.title, "audit-and-fix")
        XCTAssertEqual(context.workflowUpdate?.steps?.map(\.status), [.completed, .inProgress, .pending])
        XCTAssertEqual(
            try XCTUnwrap(context.workflowUpdatedAt).timeIntervalSince1970,
            workflowUpdatedAt.timeIntervalSince1970,
            accuracy: 1
        )
    }

    func testRejectsSessionIDPathTraversal() throws {
        let temporary = FileManager.default.temporaryDirectory
            .appendingPathComponent("AgentsNotch-GrokTraversal-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: temporary) }
        let workflowDirectory = temporary
            .appendingPathComponent("leak/workflows/run", isDirectory: true)
        try FileManager.default.createDirectory(at: workflowDirectory, withIntermediateDirectories: true)
        try Data("""
        {
          "version": 4,
          "state": {
            "run_id": "secret-run",
            "name": "secret",
            "objective": "SECRET",
            "status": "active",
            "phases": [],
            "current_phase": ""
          }
        }
        """.utf8).write(to: workflowDirectory.appendingPathComponent("state.json"))
        let bucket = temporary.appendingPathComponent("sessions/%2Ftmp%2FAgentsNotch", isDirectory: true)
        try FileManager.default.createDirectory(at: bucket, withIntermediateDirectories: true)

        let context = GrokSessionContextResolver.resolve(
            sessionId: "../../leak",
            workspaceRoot: "/tmp/AgentsNotch",
            grokHome: temporary
        )

        XCTAssertNil(context.workflowOwnerSessionId)
        XCTAssertNil(context.workflowTask)
        XCTAssertNil(context.workflowUpdate)
    }
}
