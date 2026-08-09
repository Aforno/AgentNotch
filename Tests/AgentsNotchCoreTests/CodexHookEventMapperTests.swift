import AgentsNotchCore
import XCTest

final class CodexHookEventMapperTests: XCTestCase {
    func testPermissionRequestBecomesPersistentAttention() throws {
        let payload = try decode("""
        {
          "session_id": "thr_123",
          "cwd": "/tmp/AgentsNotch",
          "hook_event_name": "PermissionRequest",
          "tool_name": "Bash",
          "tool_input": {"command": "swift test"}
        }
        """)

        let event = try XCTUnwrap(CodexHookEventMapper.map(payload))
        XCTAssertEqual(event.type, .waiting)
        XCTAssertEqual(event.state, .waitingForUser)
        XCTAssertEqual(event.activity, "Needs command approval")
        XCTAssertEqual(event.sessionId, "codex:thr_123")
    }

    func testApplyPatchExtractsChangedFile() throws {
        let payload = try decode("""
        {
          "session_id": "thr_123",
          "cwd": "/tmp/AgentsNotch",
          "hook_event_name": "PreToolUse",
          "tool_name": "apply_patch",
          "tool_input": {"command": "*** Begin Patch\\n*** Update File: Sources/App.swift\\n*** End Patch"}
        }
        """)

        let event = try XCTUnwrap(CodexHookEventMapper.map(payload))
        XCTAssertEqual(event.type, .fileChanged)
        XCTAssertEqual(event.state, .editing)
        XCTAssertEqual(event.file, "Sources/App.swift")
        XCTAssertEqual(event.activity, "Editing App.swift")
    }

    func testPromptBecomesTaskWithoutReadingTranscript() throws {
        let payload = try decode("""
        {
          "session_id": "thr_123",
          "transcript_path": "/private/transcript.jsonl",
          "cwd": "/tmp/AgentsNotch",
          "hook_event_name": "UserPromptSubmit",
          "prompt": "Build the native notch surface"
        }
        """)

        let event = try XCTUnwrap(CodexHookEventMapper.map(payload))
        XCTAssertEqual(event.task, "Build the native notch surface")
        XCTAssertEqual(event.state, .thinking)
    }

    func testClaudeSnakeCasePayloadUsesClaudeProviderAndFilePath() throws {
        let payload = try decode("""
        {
          "session_id": "claude_123",
          "cwd": "/tmp/AgentsNotch",
          "hook_event_name": "PreToolUse",
          "tool_name": "Edit",
          "tool_input": {"file_path": "/tmp/AgentsNotch/Sources/App.swift"}
        }
        """)

        let event = try XCTUnwrap(AgentHookEventMapper.map(payload, provider: .claudeCode))
        XCTAssertEqual(event.provider, .claudeCode)
        XCTAssertEqual(event.sessionId, "claude-code:claude_123")
        XCTAssertEqual(event.state, .editing)
        XCTAssertEqual(event.file, "/tmp/AgentsNotch/Sources/App.swift")
    }

    func testGrokCamelCasePayloadAndToolFailureStayActive() throws {
        let payload = try decode("""
        {
          "sessionId": "grok_123",
          "cwd": "/tmp/AgentsNotch",
          "hookEventName": "post_tool_use_failure",
          "toolName": "run_terminal_command",
          "toolInput": {"command": "swift test"},
          "error": "Tests failed"
        }
        """)

        let event = try XCTUnwrap(AgentHookEventMapper.map(payload, provider: .grok))
        XCTAssertEqual(event.provider, .grok)
        XCTAssertEqual(event.sessionId, "grok:grok_123")
        XCTAssertEqual(event.type, .toolCompleted)
        XCTAssertEqual(event.state, .running)
        XCTAssertEqual(event.activity, "Tool failed: Tests failed")
    }

    func testGrokSessionStartWithoutAgentTurnIsIgnored() throws {
        let payload = try decode("""
        {
          "sessionId": "grok_probe",
          "cwd": "/Users/example",
          "hookEventName": "session_start"
        }
        """)

        XCTAssertNil(AgentHookEventMapper.map(payload, provider: .grok))
    }

    func testGrokParentSubagentStartDoesNotMasqueradeAsChild() throws {
        let payload = try decode("""
        {
          "sessionId": "grok_parent",
          "cwd": "/tmp/AgentsNotch",
          "hookEventName": "subagent_start"
        }
        """)

        let event = try XCTUnwrap(AgentHookEventMapper.map(payload, provider: .grok))
        XCTAssertEqual(event.sessionId, "grok:grok_parent")
        XCTAssertNil(event.parentSessionId)
        XCTAssertNil(event.task)
        XCTAssertEqual(event.activity, "Running subagents")
        XCTAssertEqual(event.state, .running)
    }

    func testExplicitParentRelationshipKeepsGrokChildSessionIdentity() throws {
        let payload = try decode("""
        {
          "sessionId": "grok_child",
          "cwd": "/tmp/AgentsNotch",
          "hookEventName": "pre_tool_use",
          "toolName": "grep",
          "parentSessionId": "grok_parent",
          "description": "audit:core-models"
        }
        """)

        let event = try XCTUnwrap(AgentHookEventMapper.map(payload, provider: .grok))
        XCTAssertEqual(event.sessionId, "grok:grok_child")
        XCTAssertEqual(event.parentSessionId, "grok:grok_parent")
        XCTAssertEqual(event.agentRole, "audit:core-models")
    }

    func testGrokPromptCreatesSessionWithoutSessionStart() throws {
        let payload = try decode("""
        {
          "sessionId": "grok_turn",
          "cwd": "/tmp/AgentsNotch",
          "hookEventName": "user_prompt_submit",
          "prompt": "Fix the active-session list"
        }
        """)

        let event = try XCTUnwrap(AgentHookEventMapper.map(payload, provider: .grok))
        XCTAssertEqual(event.sessionId, "grok:grok_turn")
        XCTAssertEqual(event.task, "Fix the active-session list")
        XCTAssertEqual(event.state, .thinking)
    }

    func testGrokSnakeCaseEventValueAndNativeToolNameMapToCommandActivity() throws {
        let payload = try decode("""
        {
          "sessionId": "grok_123",
          "cwd": "/tmp/AgentsNotch",
          "hookEventName": "pre_tool_use",
          "toolName": "run_terminal_command",
          "toolInput": {"command": "swift test"}
        }
        """)

        let event = try XCTUnwrap(AgentHookEventMapper.map(payload, provider: .grok))
        XCTAssertEqual(event.type, .toolStarted)
        XCTAssertEqual(event.state, .executingTool)
        XCTAssertEqual(event.activity, "Running swift test")
        XCTAssertEqual(event.metadata?["hookEvent"], "pre_tool_use")
        XCTAssertEqual(event.metadata?["tool"], "run_terminal_command")
    }

    func testGrokSearchReplaceMapsToFileChange() throws {
        let payload = try decode("""
        {
          "sessionId": "grok_123",
          "cwd": "/tmp/AgentsNotch",
          "hookEventName": "pre_tool_use",
          "toolName": "search_replace",
          "toolInput": {"file_path": "/tmp/AgentsNotch/Sources/App.swift"}
        }
        """)

        let event = try XCTUnwrap(AgentHookEventMapper.map(payload, provider: .grok))
        XCTAssertEqual(event.type, .fileChanged)
        XCTAssertEqual(event.state, .editing)
        XCTAssertEqual(event.file, "/tmp/AgentsNotch/Sources/App.swift")
        XCTAssertEqual(event.activity, "Editing App.swift")
    }

    func testStopFailureMarksProviderSessionFailed() throws {
        let payload = try decode("""
        {
          "session_id": "claude_123",
          "cwd": "/tmp/AgentsNotch",
          "hook_event_name": "StopFailure",
          "error": "API unavailable"
        }
        """)

        let event = try XCTUnwrap(AgentHookEventMapper.map(payload, provider: .claudeCode))
        XCTAssertEqual(event.type, .failed)
        XCTAssertEqual(event.state, .failed)
        XCTAssertEqual(event.activity, "API unavailable")
    }

    func testUpdatePlanProducesStructuredSteps() throws {
        let payload = try decode("""
        {
          "session_id": "thr_plan",
          "cwd": "/tmp/AgentsNotch",
          "hook_event_name": "PreToolUse",
          "tool_name": "update_plan",
          "tool_input": {
            "explanation": "Keep the model provider-neutral.",
            "plan": [
              {"step": "Define the model", "status": "completed"},
              {"step": "Render progress", "status": "in_progress"},
              {"step": "Verify behavior", "status": "pending"}
            ]
          }
        }
        """)

        let event = try XCTUnwrap(CodexHookEventMapper.map(payload))
        let plan = try XCTUnwrap(event.plan)
        XCTAssertEqual(event.activity, "Updating plan")
        XCTAssertEqual(plan.explanation, "Keep the model provider-neutral.")
        XCTAssertEqual(plan.steps.map(\.status), [.completed, .inProgress, .pending])
        XCTAssertEqual(plan.completedStepCount, 1)
    }

    func testGoalToolsProduceWorkflowLifecycleUpdates() throws {
        let started = try decode("""
        {
          "session_id": "thr_goal",
          "cwd": "/tmp/AgentsNotch",
          "hook_event_name": "PreToolUse",
          "tool_name": "create_goal",
          "tool_input": {"objective": "Ship structured execution"}
        }
        """)
        let completed = try decode("""
        {
          "session_id": "thr_goal",
          "cwd": "/tmp/AgentsNotch",
          "hook_event_name": "PreToolUse",
          "tool_name": "update_goal",
          "tool_input": {"status": "complete"}
        }
        """)

        let startEvent = try XCTUnwrap(CodexHookEventMapper.map(started))
        let completionEvent = try XCTUnwrap(CodexHookEventMapper.map(completed))
        XCTAssertEqual(startEvent.workflowUpdate?.title, "Ship structured execution")
        XCTAssertEqual(startEvent.workflowUpdate?.status, .running)
        XCTAssertEqual(completionEvent.workflowUpdate?.id, startEvent.workflowUpdate?.id)
        XCTAssertEqual(completionEvent.workflowUpdate?.status, .completed)
    }

    func testSubagentCarriesParentRelationshipAndRole() throws {
        let payload = try decode("""
        {
          "session_id": "thr_parent",
          "cwd": "/tmp/AgentsNotch",
          "hook_event_name": "SubagentStart",
          "agent_id": "agent_child",
          "agent_type": "reviewer"
        }
        """)

        let event = try XCTUnwrap(CodexHookEventMapper.map(payload))
        XCTAssertEqual(event.sessionId, "codex:thr_parent:agent_child")
        XCTAssertEqual(event.parentSessionId, "codex:thr_parent")
        XCTAssertEqual(event.agentRole, "reviewer")
        XCTAssertEqual(event.task, "Reviewer subagent")
    }

    private func decode(_ json: String) throws -> CodexHookPayload {
        try JSONDecoder().decode(CodexHookPayload.self, from: Data(json.utf8))
    }
}
