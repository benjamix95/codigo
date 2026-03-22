import Foundation
import XCTest
@testable import CoderEngine

extension ProviderToolEventMapperTests {
    func testWebSearchMapsCorrectly() {
        let mapped = ProviderToolEventMapper.map(
            toolName: "web_search",
            payload: ["query": "Swift concurrency"]
        )
        XCTAssertNotNil(mapped)
        XCTAssertTrue(mapped?.type.hasPrefix("web_search") ?? false)
    }

    func testWebFetchMapsCorrectly() {
        let mapped = ProviderToolEventMapper.map(
            toolName: "web_fetch",
            payload: ["url": "https://example.com"]
        )
        XCTAssertNotNil(mapped)
        XCTAssertTrue(mapped?.type.hasPrefix("web_fetch") ?? false)
    }

    func testDebugSetPhaseMapsToTypedDebugPhaseEvent() {
        let mapped = ProviderToolEventMapper.map(
            toolName: "coderide_debug_set_phase",
            payload: [
                "phase": "fixing",
                "detail": "Applying patch"
            ]
        )

        XCTAssertEqual(mapped?.type, "debug_phase_update")
        XCTAssertEqual(mapped?.payload["phase"], "fixing")
        XCTAssertEqual(mapped?.payload["detail"], "Applying patch")
    }

    func testDebugRequestUserMapsToTypedRequestEvent() {
        let mapped = ProviderToolEventMapper.map(
            toolName: "coderide_debug_request_user",
            payload: [
                "kind": "question",
                "prompt": "Can you reproduce this?"
            ]
        )

        XCTAssertEqual(mapped?.type, "debug_user_request")
        XCTAssertEqual(mapped?.payload["kind"], "question")
        XCTAssertEqual(mapped?.payload["prompt"], "Can you reproduce this?")
    }

    func testDebugRequestUserFixConfirmationMapsCorrectly() {
        let mapped = ProviderToolEventMapper.map(
            toolName: "coderide_debug_request_user",
            payload: [
                "kind": "fix_confirmation",
                "prompt": "Verify the fix before cleanup"
            ]
        )

        XCTAssertEqual(mapped?.type, "debug_user_request")
        XCTAssertEqual(mapped?.payload["kind"], "fix_confirmation")
        XCTAssertEqual(mapped?.payload["prompt"], "Verify the fix before cleanup")
    }

    func testDebugResolveUsesDetailFallbackWhenSummaryMissing() {
        let mapped = ProviderToolEventMapper.map(
            toolName: "coderide_debug_resolve",
            payload: [
                "detail": "Fixed race condition in cache invalidation"
            ]
        )

        XCTAssertEqual(mapped?.type, "debug_resolved")
        XCTAssertEqual(mapped?.payload["summary"], "Fixed race condition in cache invalidation")
    }

    func testDebugLogMapsToTypedDebugLogEvent() {
        let mapped = ProviderToolEventMapper.map(
            toolName: "coderide_debug_log",
            payload: [
                "severity": "info",
                "source": "Runtime",
                "message": "Boot complete",
                "status": "completed"
            ]
        )

        XCTAssertEqual(mapped?.type, "debug_log")
        XCTAssertEqual(mapped?.payload["message"], "Boot complete")
        XCTAssertEqual(mapped?.payload["tool"], "debug_log")
    }

    func testMCPCallCoderideDebugLogMapsToTypedDebugLogEvent() {
        let mapped = ProviderToolEventMapper.map(
            toolName: "mcp_call",
            payload: [
                "mcp_server": "coderide",
                "mcp_tool": "coderide_debug_log",
                "severity": "warning",
                "source": "Runtime",
                "message": "Slow response",
            ]
        )

        XCTAssertEqual(mapped?.type, "debug_log")
        XCTAssertEqual(mapped?.payload["tool"], "debug_log")
        XCTAssertEqual(mapped?.payload["message"], "Slow response")
    }

    func testDebugSessionMapsToTypedDebugSessionEvent() {
        let mapped = ProviderToolEventMapper.map(
            toolName: "coderide_debug_session",
            payload: [
                "action": "start",
                "detail": "session opened",
                "status": "completed"
            ]
        )

        XCTAssertEqual(mapped?.type, "debug_session")
        XCTAssertEqual(mapped?.payload["action"], "start")
        XCTAssertEqual(mapped?.payload["tool"], "debug_session")
    }

    func testDebugCleanMapsToTypedDebugCleanEvent() {
        let mapped = ProviderToolEventMapper.map(
            toolName: "coderide_debug_clean",
            payload: [
                "dry_run": "true",
                "detail": "Preview",
                "status": "preview"
            ]
        )

        XCTAssertEqual(mapped?.type, "debug_clean")
        XCTAssertEqual(mapped?.payload["dry_run"], "true")
        XCTAssertEqual(mapped?.payload["status"], "preview")
    }

    func testMCPCallCoderideActivatePlanModeMapsToActivatePlanMode() {
        let mapped = ProviderToolEventMapper.map(
            toolName: "functions.mcp_call",
            payload: [
                "mcp_server": "coderide",
                "mcp_tool": "coderide_activate_plan_mode",
                "arguments": #"{\"reason\":\"User requested explicit planning mode\"}"#
            ]
        )

        XCTAssertEqual(mapped?.type, "activate_plan_mode")
        XCTAssertEqual(mapped?.payload["reason"], "User requested explicit planning mode")
    }

    func testNamespacedActivatePlanModeMapsToActivatePlanMode() {
        let mapped = ProviderToolEventMapper.map(
            toolName: "coderide_activate_plan_mode",
            payload: ["reason": "Manual activation"]
        )

        XCTAssertEqual(mapped?.type, "activate_plan_mode")
        XCTAssertEqual(mapped?.payload["reason"], "Manual activation")
    }

    func testAskUserQuestionAliasMapsQuestionToPlanReason() {
        let mapped = ProviderToolEventMapper.map(
            toolName: "ask_user_question",
            payload: ["question": "Do you prefer SwiftUI or UIKit?"]
        )

        XCTAssertEqual(mapped?.type, "activate_plan_mode")
        XCTAssertEqual(mapped?.payload["reason"], "Do you prefer SwiftUI or UIKit?")
    }

    func testLegacyDebugPanelMapsToValidationError() {
        let mapped = ProviderToolEventMapper.map(
            toolName: "coderide_debug_panel",
            payload: [
                "action": "open",
                "phase": "describing"
            ]
        )

        XCTAssertEqual(mapped?.type, "tool_validation_error")
        XCTAssertEqual(mapped?.payload["error_code"], "legacy_debug_panel_removed")
    }

}
