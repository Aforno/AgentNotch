import AgentsNotchCore
import XCTest

final class AgentHookEventMapperTests: XCTestCase {
    func testHookInputRejectsPayloadsLargerThanOneMiB() {
        let oversized = Data(repeating: 0x20, count: AgentHookInput.maximumBytes + 1)

        XCTAssertThrowsError(try AgentHookInput.decode(oversized)) { error in
            XCTAssertEqual(error as? AgentHookInputError, .inputTooLarge)
        }
    }

    func testProviderTimestampIsPreservedInsteadOfUsingReceiptOrder() throws {
        let payload = try decode("""
        {
          "session_id": "timestamped",
          "cwd": "/tmp/AgentsNotch",
          "hook_event_name": "Stop",
          "timestamp": "2026-08-09T12:34:56.125Z"
        }
        """)
        let receipt = Date(timeIntervalSince1970: 2_000_000_000)

        let event = try XCTUnwrap(AgentHookEventMapper.map(payload, provider: .codex, now: receipt))

        XCTAssertEqual(
            event.timestamp,
            try Date("2026-08-09T12:34:56.125Z", strategy: Date.ISO8601FormatStyle(includingFractionalSeconds: true))
        )
    }

    func testProviderMillisecondTimestampIsDecoded() throws {
        let payload = try decode("""
        {
          "sessionId": "timestamped",
          "cwd": "/tmp/AgentsNotch",
          "hookEventName": "stop",
          "createdAt": 1786278896125
        }
        """)

        let event = try XCTUnwrap(AgentHookEventMapper.map(payload, provider: .grok))

        XCTAssertEqual(event.timestamp.timeIntervalSince1970, 1_786_278_896.125, accuracy: 0.001)
    }

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

        let event = try XCTUnwrap(AgentHookEventMapper.map(payload, provider: .codex))
        XCTAssertEqual(event.type, .waiting)
        XCTAssertEqual(event.state, .waitingForUser)
        XCTAssertEqual(event.activity, "Needs command approval")
        XCTAssertEqual(event.sessionId, "codex:thr_123")
    }

    func testAutoReviewedPermissionPayloadDoesNotCreateAttention() throws {
        let payload = try decode("""
        {
          "session_id": "thr_auto",
          "cwd": "/tmp/AgentsNotch",
          "hook_event_name": "PermissionRequest",
          "approvals_reviewer": "auto_review",
          "tool_name": "Bash"
        }
        """)

        let requiresUserInput = CodexApprovalContextResolver
            .permissionRequestRequiresUserInput(for: payload)

        XCTAssertFalse(requiresUserInput)
        XCTAssertNil(
            AgentHookEventMapper.map(
                payload,
                provider: .codex,
                permissionRequestRequiresUserInput: requiresUserInput
            )
        )
    }

    func testAutoReviewerIsResolvedFromMatchingTranscriptTurn() throws {
        let transcript = try temporaryTranscript("""
        {"type":"turn_context","payload":{"turn_id":"target","approvals_reviewer":"auto_review"}}
        {"type":"turn_context","payload":{"turn_id":"other","approvals_reviewer":"user"}}
        """)
        defer { try? FileManager.default.removeItem(at: transcript) }
        let payload = try decode("""
        {
          "session_id": "thr_auto",
          "turn_id": "target",
          "transcript_path": "\(transcript.path)",
          "cwd": "/tmp/AgentsNotch",
          "hook_event_name": "PermissionRequest"
        }
        """)

        XCTAssertFalse(
            CodexApprovalContextResolver.permissionRequestRequiresUserInput(for: payload)
        )
    }

    func testCamelCaseTranscriptTurnContextIsAccepted() throws {
        let transcript = try temporaryTranscript("""
        {"type":"turn_context","payload":{"turnId":"target","approvalsReviewer":"auto_review"}}
        """)
        defer { try? FileManager.default.removeItem(at: transcript) }
        let payload = try decode("""
        {
          "session_id": "thr_auto_camel",
          "turn_id": "target",
          "transcript_path": "\(transcript.path)",
          "cwd": "/tmp/AgentsNotch",
          "hook_event_name": "PermissionRequest"
        }
        """)

        XCTAssertFalse(
            CodexApprovalContextResolver.permissionRequestRequiresUserInput(for: payload)
        )
    }

    func testSnakeCaseReviewerWinsWhenBothAliasesExist() throws {
        let transcript = try temporaryTranscript("""
        {"type":"turn_context","payload":{"turn_id":"target","approvals_reviewer":"auto_review","approvalsReviewer":"user"}}
        """)
        defer { try? FileManager.default.removeItem(at: transcript) }
        let payload = try decode("""
        {
          "session_id": "thr_both",
          "turn_id": "target",
          "transcript_path": "\(transcript.path)",
          "cwd": "/tmp/AgentsNotch",
          "hook_event_name": "PermissionRequest"
        }
        """)

        XCTAssertFalse(
            CodexApprovalContextResolver.permissionRequestRequiresUserInput(for: payload)
        )
    }

    func testEitherTurnIdAliasMatchesTarget() throws {
        let transcript = try temporaryTranscript("""
        {"type":"turn_context","payload":{"turn_id":"other","turnId":"target","approvals_reviewer":"auto_review"}}
        """)
        defer { try? FileManager.default.removeItem(at: transcript) }
        let payload = try decode("""
        {
          "session_id": "thr_either",
          "turn_id": "target",
          "transcript_path": "\(transcript.path)",
          "cwd": "/tmp/AgentsNotch",
          "hook_event_name": "PermissionRequest"
        }
        """)

        XCTAssertFalse(
            CodexApprovalContextResolver.permissionRequestRequiresUserInput(for: payload)
        )
    }

    func testMalformedReviewerFallsThroughToAlternateAlias() throws {
        let transcript = try temporaryTranscript("""
        {"type":"turn_context","payload":{"turn_id":"target","approvals_reviewer":false,"approvalsReviewer":"auto_review"}}
        """)
        defer { try? FileManager.default.removeItem(at: transcript) }
        let payload = try decode("""
        {
          "session_id": "thr_lossy",
          "turn_id": "target",
          "transcript_path": "\(transcript.path)",
          "cwd": "/tmp/AgentsNotch",
          "hook_event_name": "PermissionRequest"
        }
        """)

        XCTAssertFalse(
            CodexApprovalContextResolver.permissionRequestRequiresUserInput(for: payload)
        )
    }

    func testExplicitUserReviewerOverridesAutomaticTranscriptContext() throws {
        let transcript = try temporaryTranscript("""
        {"type":"turn_context","payload":{"turn_id":"target","approvals_reviewer":"auto_review"}}
        """)
        defer { try? FileManager.default.removeItem(at: transcript) }
        let payload = try decode("""
        {
          "session_id": "thr_user",
          "turn_id": "target",
          "transcript_path": "\(transcript.path)",
          "cwd": "/tmp/AgentsNotch",
          "hook_event_name": "PermissionRequest",
          "approvals_reviewer": "user"
        }
        """)

        XCTAssertTrue(
            CodexApprovalContextResolver.permissionRequestRequiresUserInput(for: payload)
        )
    }

    func testTranscriptWithoutTurnIdFailsOpenToUserAttention() throws {
        let transcript = try temporaryTranscript("""
        {"type":"turn_context","payload":{"turn_id":"latest","approvals_reviewer":"auto_review"}}
        """)
        defer { try? FileManager.default.removeItem(at: transcript) }
        let payload = try decode("""
        {
          "session_id": "thr_open",
          "transcript_path": "\(transcript.path)",
          "cwd": "/tmp/AgentsNotch",
          "hook_event_name": "PermissionRequest"
        }
        """)

        XCTAssertTrue(
            CodexApprovalContextResolver.permissionRequestRequiresUserInput(for: payload)
        )
        XCTAssertNotNil(AgentHookEventMapper.map(payload, provider: .codex))
    }

    func testMissingOrMalformedReviewerContextKeepsUserAttention() throws {
        let transcript = try temporaryTranscript("not-json\n")
        defer { try? FileManager.default.removeItem(at: transcript) }
        let payload = try decode("""
        {
          "session_id": "thr_unknown",
          "turn_id": "target",
          "transcript_path": "\(transcript.path)",
          "cwd": "/tmp/AgentsNotch",
          "hook_event_name": "PermissionRequest"
        }
        """)

        XCTAssertTrue(
            CodexApprovalContextResolver.permissionRequestRequiresUserInput(for: payload)
        )
        XCTAssertNotNil(AgentHookEventMapper.map(payload, provider: .codex))
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

        let event = try XCTUnwrap(AgentHookEventMapper.map(payload, provider: .codex))
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

        let event = try XCTUnwrap(AgentHookEventMapper.map(payload, provider: .codex))
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

    func testClaudeElicitationBecomesWaitingAndResultClearsAttention() throws {
        let elicitation = try decode("""
        {
          "session_id": "claude_123",
          "cwd": "/tmp/AgentsNotch",
          "hook_event_name": "Elicitation",
          "mcp_server_name": "github",
          "message": "Authorize GitHub"
        }
        """)
        let waiting = try XCTUnwrap(AgentHookEventMapper.map(elicitation, provider: .claudeCode))
        XCTAssertEqual(waiting.type, .waiting)
        XCTAssertEqual(waiting.state, .waitingForUser)
        XCTAssertEqual(waiting.activity, "Authorize GitHub")

        let result = try decode("""
        {
          "session_id": "claude_123",
          "cwd": "/tmp/AgentsNotch",
          "hook_event_name": "ElicitationResult"
        }
        """)
        let received = try XCTUnwrap(AgentHookEventMapper.map(result, provider: .claudeCode))
        XCTAssertEqual(received.type, .activity)
        XCTAssertEqual(received.state, .running)
        XCTAssertEqual(received.activity, "Input received")
    }

    func testClaudePermissionDeniedKeepsSessionActive() throws {
        let payload = try decode("""
        {
          "session_id": "claude_123",
          "cwd": "/tmp/AgentsNotch",
          "hook_event_name": "PermissionDenied",
          "tool_name": "Bash",
          "reason": "Blocked by classifier"
        }
        """)
        let event = try XCTUnwrap(AgentHookEventMapper.map(payload, provider: .claudeCode))
        XCTAssertEqual(event.type, .activity)
        XCTAssertEqual(event.state, .running)
        XCTAssertEqual(event.activity, "Blocked by classifier")
    }

    func testClaudeAskUserQuestionAndExitPlanModeSurfaceWaiting() throws {
        let question = try decode("""
        {
          "session_id": "claude_123",
          "cwd": "/tmp/AgentsNotch",
          "hook_event_name": "PreToolUse",
          "tool_name": "AskUserQuestion",
          "tool_input": {
            "questions": [
              {
                "question": "Which framework?",
                "header": "Framework",
                "options": [{"label": "React"}],
                "multiSelect": false
              }
            ]
          }
        }
        """)
        let asking = try XCTUnwrap(AgentHookEventMapper.map(question, provider: .claudeCode))
        XCTAssertEqual(asking.type, .waiting)
        XCTAssertEqual(asking.state, .waitingForUser)
        XCTAssertEqual(asking.activity, "Which framework?")

        let plan = try decode("""
        {
          "session_id": "claude_123",
          "cwd": "/tmp/AgentsNotch",
          "hook_event_name": "PreToolUse",
          "tool_name": "ExitPlanMode",
          "tool_input": {
            "plan": "## Refactor auth",
            "planFilePath": "/tmp/plans/refactor-auth.md"
          }
        }
        """)
        let approving = try XCTUnwrap(AgentHookEventMapper.map(plan, provider: .claudeCode))
        XCTAssertEqual(approving.type, .waiting)
        XCTAssertEqual(approving.state, .waitingForUser)
        XCTAssertEqual(approving.activity, "Needs plan approval")

        let permission = try decode("""
        {
          "session_id": "claude_123",
          "cwd": "/tmp/AgentsNotch",
          "hook_event_name": "PermissionRequest",
          "tool_name": "AskUserQuestion"
        }
        """)
        let prompt = try XCTUnwrap(AgentHookEventMapper.map(permission, provider: .claudeCode))
        XCTAssertEqual(prompt.type, .waiting)
        XCTAssertEqual(prompt.state, .waitingForUser)
        XCTAssertEqual(prompt.activity, "Needs an answer")

        let answered = try decode("""
        {
          "session_id": "claude_123",
          "cwd": "/tmp/AgentsNotch",
          "hook_event_name": "PostToolUse",
          "tool_name": "AskUserQuestion"
        }
        """)
        let received = try XCTUnwrap(AgentHookEventMapper.map(answered, provider: .claudeCode))
        XCTAssertEqual(received.type, .toolCompleted)
        XCTAssertEqual(received.state, .running)
    }

    func testClaudeElicitationUrlNotificationIsWaiting() throws {
        let payload = try decode("""
        {
          "session_id": "claude_123",
          "cwd": "/tmp/AgentsNotch",
          "hook_event_name": "Notification",
          "notification_type": "elicitation_url_dialog",
          "message": "Open the login page"
        }
        """)
        let event = try XCTUnwrap(AgentHookEventMapper.map(payload, provider: .claudeCode))
        XCTAssertEqual(event.type, .waiting)
        XCTAssertEqual(event.state, .waitingForUser)
        XCTAssertEqual(event.activity, "Open the login page")
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

    func testWrappedUserQueryPromptUsesInnerTextAsTask() throws {
        let payload = try decode("""
        {
          "sessionId": "grok_wrapped",
          "cwd": "/tmp/AgentsNotch",
          "hookEventName": "user_prompt_submit",
          "prompt": "<user_query>\\nDo 4\\n</user_query>"
        }
        """)

        let event = try XCTUnwrap(AgentHookEventMapper.map(payload, provider: .grok))
        XCTAssertEqual(event.task, "Do 4")
    }

    func testInlineUserQueryPromptStripsWrapperTags() throws {
        let payload = try decode("""
        {
          "sessionId": "grok_inline",
          "cwd": "/tmp/AgentsNotch",
          "hookEventName": "user_prompt_submit",
          "prompt": "<user_query>Fix the user_query bug</user_query>"
        }
        """)

        let event = try XCTUnwrap(AgentHookEventMapper.map(payload, provider: .grok))
        XCTAssertEqual(event.task, "Fix the user_query bug")
    }

    func testUserQueryTagAloneDoesNotBecomeTask() throws {
        let payload = try decode("""
        {
          "sessionId": "grok_tag",
          "cwd": "/tmp/AgentsNotch",
          "hookEventName": "user_prompt_submit",
          "prompt": "<user_query>"
        }
        """)

        let event = try XCTUnwrap(AgentHookEventMapper.map(payload, provider: .grok))
        XCTAssertNil(event.task)
    }

    func testImageOnlyPromptDoesNotBecomeTask() throws {
        let payload = try decode("""
        {
          "sessionId": "grok_image",
          "cwd": "/tmp/AgentsNotch",
          "hookEventName": "user_prompt_submit",
          "prompt": "<user_query>\\n[Image #1]\\n</user_query>"
        }
        """)

        let event = try XCTUnwrap(AgentHookEventMapper.map(payload, provider: .grok))
        XCTAssertNil(event.task)
    }

    func testImagePrefixIsStrippedFromPromptTask() throws {
        let payload = try decode("""
        {
          "sessionId": "grok_image_text",
          "cwd": "/tmp/AgentsNotch",
          "hookEventName": "user_prompt_submit",
          "prompt": "<user_query>\\n[Image #1] fix the user_query bug\\n</user_query>"
        }
        """)

        let event = try XCTUnwrap(AgentHookEventMapper.map(payload, provider: .grok))
        XCTAssertEqual(event.task, "fix the user_query bug")
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

        let event = try XCTUnwrap(AgentHookEventMapper.map(payload, provider: .codex))
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

        let startEvent = try XCTUnwrap(AgentHookEventMapper.map(started, provider: .codex))
        let completionEvent = try XCTUnwrap(AgentHookEventMapper.map(completed, provider: .codex))
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

        let event = try XCTUnwrap(AgentHookEventMapper.map(payload, provider: .codex))
        XCTAssertEqual(event.sessionId, "codex:thr_parent:agent_child")
        XCTAssertEqual(event.parentSessionId, "codex:thr_parent")
        XCTAssertEqual(event.agentRole, "reviewer")
        XCTAssertEqual(event.task, "Reviewer subagent")
    }

    func testCursorPromptUsesConversationAndWorkspaceRootAliases() throws {
        let payload = try decode("""
        {
          "conversation_id": "cursor-conversation",
          "workspace_roots": ["/tmp/AgentsNotch"],
          "hook_event_name": "beforeSubmitPrompt",
          "prompt": "Add Cursor support"
        }
        """)

        let event = try XCTUnwrap(AgentHookEventMapper.map(payload, provider: .cursor))
        XCTAssertEqual(event.sessionId, "cursor:cursor-conversation")
        XCTAssertEqual(event.provider, .cursor)
        XCTAssertEqual(event.task, "Add Cursor support")
        XCTAssertEqual(event.workingDirectory, "/tmp/AgentsNotch")
        XCTAssertEqual(event.state, .thinking)
    }

    func testEmptyCwdFallsBackToWorkspaceRoots() throws {
        let payload = try decode("""
        {
          "conversation_id": "cursor-conversation",
          "cwd": "",
          "workspace_roots": ["/tmp/AgentsNotch"],
          "hook_event_name": "session_start"
        }
        """)

        XCTAssertEqual(payload.cwd, "/tmp/AgentsNotch")
        let event = try XCTUnwrap(AgentHookEventMapper.map(payload, provider: .cursor))
        XCTAssertEqual(event.workingDirectory, "/tmp/AgentsNotch")
        XCTAssertEqual(event.task, "AgentsNotch")
    }

    func testObjectErrorAndNullHookEventNameAliasDoNotDropPayload() throws {
        let payload = try decode("""
        {
          "session_id": "thr_err",
          "cwd": "/tmp/AgentsNotch",
          "hookEventName": null,
          "hook_event_name": "PostToolUseFailure",
          "error": {"message": "boom"}
        }
        """)

        XCTAssertEqual(payload.error, "boom")
        let event = try XCTUnwrap(AgentHookEventMapper.map(payload, provider: .codex))
        XCTAssertEqual(event.activity, "Tool failed: boom")
    }

    func testCursorAbortedStopIsFailure() throws {
        let payload = try decode("""
        {
          "conversation_id": "cursor-conversation",
          "workspace_roots": ["/tmp/AgentsNotch"],
          "hook_event_name": "stop",
          "status": "aborted"
        }
        """)

        let event = try XCTUnwrap(AgentHookEventMapper.map(payload, provider: .cursor))
        XCTAssertEqual(event.type, .failed)
        XCTAssertEqual(event.state, .failed)
        XCTAssertEqual(event.activity, "Task failed")
    }

    func testCursorFailureUsesStatusAndErrorMessageAliases() throws {
        let payload = try decode("""
        {
          "conversation_id": "cursor-conversation",
          "workspace_roots": ["/tmp/AgentsNotch"],
          "hook_event_name": "stop",
          "status": "error",
          "error_message": "Model request failed"
        }
        """)

        let event = try XCTUnwrap(AgentHookEventMapper.map(payload, provider: .cursor))
        XCTAssertEqual(event.type, .failed)
        XCTAssertEqual(event.state, .failed)
        XCTAssertEqual(event.activity, "Model request failed")
    }

    func testOpenCodeEditToolUsesCamelCaseFilePath() throws {
        let payload = try decode("""
        {
          "session_id": "open-code-session",
          "cwd": "/tmp/AgentsNotch",
          "hook_event_name": "PreToolUse",
          "tool_name": "edit",
          "tool_input": {"filePath": "/tmp/AgentsNotch/Sources/App.swift"}
        }
        """)

        let event = try XCTUnwrap(AgentHookEventMapper.map(payload, provider: .openCode))
        XCTAssertEqual(event.sessionId, "opencode:open-code-session")
        XCTAssertEqual(event.provider, .openCode)
        XCTAssertEqual(event.type, .fileChanged)
        XCTAssertEqual(event.state, .editing)
        XCTAssertEqual(event.file, "/tmp/AgentsNotch/Sources/App.swift")
        XCTAssertEqual(event.activity, "Editing App.swift")
    }

    func testGeminiLifecycleAliasesMapToProviderNeutralEvents() throws {
        let beforeAgent = try decode("""
        {
          "session_id": "gemini-1",
          "cwd": "/tmp/AgentsNotch",
          "hook_event_name": "BeforeAgent",
          "prompt": "Add a Gemini integration"
        }
        """)
        let promptEvent = try XCTUnwrap(AgentHookEventMapper.map(beforeAgent, provider: .geminiCLI))
        XCTAssertEqual(promptEvent.type, .activity)
        XCTAssertEqual(promptEvent.task, "Add a Gemini integration")
        XCTAssertEqual(promptEvent.state, .thinking)
        XCTAssertEqual(promptEvent.metadata?["hookEvent"], "UserPromptSubmit")

        let beforeTool = try decode("""
        {
          "session_id": "gemini-1",
          "cwd": "/tmp/AgentsNotch",
          "hook_event_name": "BeforeTool",
          "tool_name": "run_shell_command",
          "tool_input": {"command": "swift test"}
        }
        """)
        let toolEvent = try XCTUnwrap(AgentHookEventMapper.map(beforeTool, provider: .geminiCLI))
        XCTAssertEqual(toolEvent.type, .toolStarted)
        XCTAssertEqual(toolEvent.provider, .geminiCLI)

        let notification = try decode("""
        {
          "session_id": "gemini-1",
          "cwd": "/tmp/AgentsNotch",
          "hook_event_name": "Notification",
          "notification_type": "ToolPermission",
          "message": "Approve run_shell_command"
        }
        """)
        let waiting = try XCTUnwrap(AgentHookEventMapper.map(notification, provider: .geminiCLI))
        XCTAssertEqual(waiting.type, .waiting)
        XCTAssertEqual(waiting.activity, "Approve run_shell_command")

        let afterAgent = try decode("""
        {
          "session_id": "gemini-1",
          "cwd": "/tmp/AgentsNotch",
          "hook_event_name": "AfterAgent",
          "prompt_response": "Gemini integration complete"
        }
        """)
        let completed = try XCTUnwrap(AgentHookEventMapper.map(afterAgent, provider: .geminiCLI))
        XCTAssertEqual(completed.type, .completed)
        XCTAssertEqual(completed.activity, "Gemini integration complete")
    }

    func testHookEventNameCanonicalizesAliasesAndClassifiesLifecycle() {
        XCTAssertEqual(HookEventName(rawEventName: "BeforeAgent"), .userPromptSubmit)
        XCTAssertEqual(HookEventName(rawEventName: "before_submit_prompt"), .userPromptSubmit)
        XCTAssertEqual(HookEventName(rawEventName: "AfterAgent"), .stop)
        XCTAssertEqual(HookEventName(rawEventName: "subagent_end"), .subagentStop)
        XCTAssertEqual(HookEventName.metadataName(for: "BeforeAgent"), "UserPromptSubmit")
        XCTAssertEqual(HookEventName.metadataName(for: "UserPromptSubmit"), "UserPromptSubmit")
        XCTAssertEqual(HookEventName.metadataName(for: "user_prompt_submit"), "user_prompt_submit")
        XCTAssertTrue(HookEventName.stop.isTerminal)
        XCTAssertTrue(HookEventName.sessionEnd.isTerminal)
        XCTAssertFalse(HookEventName.userPromptSubmit.isTerminal)
        XCTAssertTrue(HookEventName.userPromptSubmit.resumesSession)
        XCTAssertFalse(HookEventName.sessionStart.resumesSession)
        XCTAssertNil(HookEventName(rawEventName: "UnknownVendorEvent"))
    }

    private func decode(_ json: String) throws -> AgentHookPayload {
        try JSONDecoder().decode(AgentHookPayload.self, from: Data(json.utf8))
    }

    private func temporaryTranscript(_ contents: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("agentsnotch-transcript-\(UUID().uuidString).jsonl")
        try Data(contents.utf8).write(to: url, options: .atomic)
        return url
    }
}
