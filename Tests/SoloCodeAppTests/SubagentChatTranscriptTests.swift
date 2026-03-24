import XCTest
@testable import CoderIDE

final class SubagentChatTranscriptTests: XCTestCase {

    // MARK: - SubagentTranscriptEntry Factory Tests

    func testUserPromptCreatesCorrectEntry() {
        let entry = SubagentTranscriptEntry.userPrompt(
            "Analizza l'architettura della pipeline",
            timestamp: Date(timeIntervalSince1970: 100)
        )
        XCTAssertNotNil(entry)
        XCTAssertEqual(entry?.kind, .userPrompt)
        XCTAssertEqual(entry?.title, "Task")
        XCTAssertEqual(entry?.detail, "Analizza l'architettura della pipeline")
        XCTAssertFalse(entry?.isRunning ?? true)
    }

    func testUserPromptRejectsEmptyString() {
        let entry = SubagentTranscriptEntry.userPrompt("  ", timestamp: nil)
        XCTAssertNil(entry)
    }

    func testReasoningCreatesCorrectEntry() {
        let entry = SubagentTranscriptEntry.reasoning(
            "Let me think about the authentication flow...",
            timestamp: Date(timeIntervalSince1970: 101)
        )
        XCTAssertNotNil(entry)
        XCTAssertEqual(entry?.kind, .reasoning)
        XCTAssertEqual(entry?.title, "Thinking")
        XCTAssertTrue(entry?.isRunning ?? false)
    }

    func testReasoningRejectsEmptyString() {
        let entry = SubagentTranscriptEntry.reasoning("", timestamp: nil)
        XCTAssertNil(entry)
    }

    func testAssistantTextCreatesCorrectEntry() {
        let entry = SubagentTranscriptEntry.assistantText(
            "Found 3 files with potential issues",
            timestamp: Date(timeIntervalSince1970: 102)
        )
        XCTAssertNotNil(entry)
        XCTAssertEqual(entry?.kind, .assistantText)
        XCTAssertEqual(entry?.title, "Response")
        XCTAssertTrue(entry?.isRunning ?? false)
    }

    func testResultCreatesCorrectEntry() {
        let entry = SubagentTranscriptEntry.result(
            "Analysis complete: 3 issues found, 2 critical",
            timestamp: Date(timeIntervalSince1970: 103)
        )
        XCTAssertNotNil(entry)
        XCTAssertEqual(entry?.kind, .result)
        XCTAssertEqual(entry?.title, "Result")
        XCTAssertFalse(entry?.isRunning ?? true)
    }

    func testResultRejectsEmptyString() {
        let entry = SubagentTranscriptEntry.result("  \n  ", timestamp: nil)
        XCTAssertNil(entry)
    }

    func testActivityCreatesCorrectEntry() {
        let activity = TaskActivity(
            type: "read_batch_started",
            title: "Reading files",
            detail: "/Sources/Auth/SessionManager.swift",
            payload: ["swarm_id": "sa-abc", "status": "started"],
            timestamp: Date(timeIntervalSince1970: 104),
            phase: .searching,
            isRunning: true,
            groupId: "swarm-sa-abc"
        )
        let entry = SubagentTranscriptEntry.activity(activity)
        XCTAssertNotNil(entry)
        XCTAssertEqual(entry?.kind, .activity)
        XCTAssertEqual(entry?.title, "Reading files")
        XCTAssertTrue(entry?.isRunning ?? false)
    }

    // MARK: - Reducer Transcript Integration Tests

    func testReducerInjectsUserPromptAsFirstTranscriptEntry() {
        let started = TaskActivity(
            type: "agent",
            title: "Explorer",
            detail: "started",
            payload: [
                "swarm_id": "sa-abc123",
                "group_id": "swarm-sa-abc123",
                "task_summary": "Analyze the auth token refresh flow",
                "role": "explorer",
                "readable_name": "Auth Token Refresh",
                "status": "started",
            ],
            timestamp: Date(timeIntervalSince1970: 100),
            phase: .planning,
            isRunning: true,
            groupId: "swarm-sa-abc123"
        )
        let cards = SwarmLiveReducer.reduce(activities: [started], limitRecentEvents: 80)
        let card = cards["sa-abc123"]

        XCTAssertNotNil(card)
        XCTAssertEqual(card?.taskPrompt, "Analyze the auth token refresh flow")

        // First transcript entry should be the user prompt
        let firstEntry = card?.transcript.first
        XCTAssertEqual(firstEntry?.kind, .userPrompt)
        XCTAssertEqual(firstEntry?.detail, "Analyze the auth token refresh flow")
    }

    func testReducerPopulatesRoleType() {
        let activity = TaskActivity(
            type: "agent",
            title: "Explorer",
            detail: "started",
            payload: [
                "swarm_id": "sa-xyz",
                "group_id": "swarm-sa-xyz",
                "role": "explorer",
                "status": "started",
            ],
            timestamp: Date(timeIntervalSince1970: 100),
            phase: .planning,
            isRunning: true,
            groupId: "swarm-sa-xyz"
        )
        let cards = SwarmLiveReducer.reduce(activities: [activity], limitRecentEvents: 80)
        XCTAssertEqual(cards["sa-xyz"]?.roleType, "explorer")
    }

    func testReducerPrefersReadableNameOverAgentName() {
        let activity = TaskActivity(
            type: "agent",
            title: "Explorer",
            detail: "started",
            payload: [
                "swarm_id": "sa-rn1",
                "group_id": "swarm-sa-rn1",
                "agent_name": "Explorer-AuthTokenRefresh",
                "readable_name": "Auth Token Refresh",
                "status": "started",
            ],
            timestamp: Date(timeIntervalSince1970: 100),
            phase: .planning,
            isRunning: true,
            groupId: "swarm-sa-rn1"
        )
        let cards = SwarmLiveReducer.reduce(activities: [activity], limitRecentEvents: 80)
        XCTAssertEqual(cards["sa-rn1"]?.displayName, "Auth Token Refresh")
    }

    func testReducerNeverUsesSwarmIdAsDisplayName() {
        let activity = TaskActivity(
            type: "agent",
            title: "",
            detail: "started",
            payload: [
                "swarm_id": "sa-noname123",
                "group_id": "swarm-sa-noname123",
                "status": "started",
            ],
            timestamp: Date(timeIntervalSince1970: 100),
            phase: .planning,
            isRunning: true,
            groupId: "swarm-sa-noname123"
        )
        let cards = SwarmLiveReducer.reduce(activities: [activity], limitRecentEvents: 80)
        let displayName = cards["sa-noname123"]?.displayName ?? ""
        XCTAssertEqual(displayName, "Sub Agent")
        XCTAssertFalse(displayName.contains("sa-"))
    }

    func testReducerDistinguishesReasoningFromAssistantText() {
        let reasoning = TaskActivity(
            type: "subagent_text",
            title: "Live output",
            detail: "thinking about auth flow",
            payload: [
                "swarm_id": "sa-reason1",
                "group_id": "swarm-sa-reason1",
                "status": "running",
                "text": "Let me analyze the authentication flow...",
                "source": "reasoning",
            ],
            timestamp: Date(timeIntervalSince1970: 101),
            phase: .thinking,
            isRunning: true,
            groupId: "swarm-sa-reason1"
        )
        let assistantText = TaskActivity(
            type: "subagent_text",
            title: "Live output",
            detail: "found 3 issues",
            payload: [
                "swarm_id": "sa-reason1",
                "group_id": "swarm-sa-reason1",
                "status": "running",
                "text": "Found 3 files with authentication issues",
                "source": "assistant",
            ],
            timestamp: Date(timeIntervalSince1970: 102),
            phase: .executing,
            isRunning: true,
            groupId: "swarm-sa-reason1"
        )

        let cards = SwarmLiveReducer.reduce(
            activities: [reasoning, assistantText],
            limitRecentEvents: 80
        )
        let transcript = cards["sa-reason1"]?.transcript ?? []
        XCTAssertEqual(transcript.count, 2)
        XCTAssertEqual(transcript[0].kind, .reasoning)
        XCTAssertEqual(transcript[1].kind, .assistantText)
    }

    // MARK: - FormattedTitle Tests

    func testFormattedTitleShowsNameAndRole() {
        let card = SwarmLiveCardState(
            swarmId: "sa-test1",
            displayName: "Auth Token Refresh",
            roleType: "explorer"
        )
        XCTAssertEqual(card.formattedTitle, "Auth Token Refresh - Explorer")
    }

    func testFormattedTitleOmitsRoleWhenSameAsName() {
        let card = SwarmLiveCardState(
            swarmId: "sa-test2",
            displayName: "Explorer",
            roleType: "explorer"
        )
        XCTAssertEqual(card.formattedTitle, "Explorer")
    }

    func testFormattedTitleOmitsRoleWhenNameContainsIt() {
        let card = SwarmLiveCardState(
            swarmId: "sa-test3",
            displayName: "Auth Explorer Task",
            roleType: "explorer"
        )
        XCTAssertEqual(card.formattedTitle, "Auth Explorer Task")
    }

    func testFormattedTitleFallsBackToSubAgent() {
        let card = SwarmLiveCardState(swarmId: "sa-test4")
        XCTAssertEqual(card.formattedTitle, "Sub Agent")
    }

    func testFormattedTitleHumanizesRoles() {
        let testCases: [(String, String)] = [
            ("bughunter", "Bug Hunter"),
            ("testwriter", "Test Writer"),
            ("securityauditor", "Security Auditor"),
            ("docwriter", "Doc Writer"),
        ]
        for (role, expected) in testCases {
            let card = SwarmLiveCardState(
                swarmId: "sa-role",
                displayName: "Some Task",
                roleType: role
            )
            XCTAssertTrue(
                card.formattedTitle.contains(expected),
                "Expected formattedTitle to contain '\(expected)' for role '\(role)', got '\(card.formattedTitle)'"
            )
        }
    }

    // MARK: - Presentation Filter Tests

    func testPresentationFiltersSwarmIdStrings() {
        XCTAssertNil(SwarmLivePresentation.normalizedSubtitleText("sa-AbCdEfGhIjKl"))
        XCTAssertNil(SwarmLivePresentation.normalizedSubtitleText("swarm-sa-abc123"))
        XCTAssertNil(SwarmLivePresentation.normalizedSubtitleText("Swarm Explorer started"))
        XCTAssertNil(SwarmLivePresentation.normalizedSubtitleText("Explorer-toolu_01abc"))
        XCTAssertNil(SwarmLivePresentation.normalizedSubtitleText("mcp__coderide__coderide_subagent_explorer"))
        XCTAssertNil(SwarmLivePresentation.normalizedSubtitleText("subagent_explorer"))
    }

    func testPresentationAllowsNormalSubtitles() {
        XCTAssertNotNil(SwarmLivePresentation.normalizedSubtitleText("Reading auth configuration"))
        XCTAssertNotNil(SwarmLivePresentation.normalizedSubtitleText("Found 3 files with issues"))
        XCTAssertNotNil(SwarmLivePresentation.normalizedSubtitleText("Analyzing pipeline architecture"))
    }
}
