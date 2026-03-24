import XCTest
@testable import CoderIDE

final class SubagentChatSegmentBuilderTests: XCTestCase {

    // MARK: - Basic Segment Building

    func testEmptyCardProducesNoSegments() {
        let card = SwarmLiveCardState(swarmId: "sa-empty")
        let segments = SubagentChatSegmentBuilder.build(from: card)
        XCTAssertTrue(segments.isEmpty)
    }

    func testUserPromptBecomesTaskPromptSegment() {
        var card = SwarmLiveCardState(swarmId: "sa-test1")
        card.transcript = [
            SubagentTranscriptEntry(kind: .userPrompt, title: "Task", detail: "Analizza il codice")!,
        ].compactMap { $0 }
        let segments = SubagentChatSegmentBuilder.build(from: card)
        XCTAssertEqual(segments.count, 1)
        if case .taskPrompt(_, let text) = segments[0] {
            XCTAssertEqual(text, "Analizza il codice")
        } else {
            XCTFail("Expected .taskPrompt, got \(segments[0])")
        }
    }

    func testAssistantTextBecomesTextSegment() {
        var card = SwarmLiveCardState(swarmId: "sa-test2")
        card.transcript = [
            SubagentTranscriptEntry.assistantText("Found 3 issues", timestamp: nil),
        ].compactMap { $0 }
        let segments = SubagentChatSegmentBuilder.build(from: card)
        XCTAssertEqual(segments.count, 1)
        if case .text(_, let content, let isStreaming) = segments[0] {
            XCTAssertEqual(content, "Found 3 issues")
            XCTAssertFalse(isStreaming)
        } else {
            XCTFail("Expected .text segment")
        }
    }

    func testReasoningBecomesReasoningSegment() {
        var card = SwarmLiveCardState(swarmId: "sa-test3")
        card.transcript = [
            SubagentTranscriptEntry.reasoning("Let me think...", timestamp: nil),
        ].compactMap { $0 }
        let segments = SubagentChatSegmentBuilder.build(from: card)
        XCTAssertEqual(segments.count, 1)
        if case .reasoning(_, let blocks, _) = segments[0] {
            XCTAssertEqual(blocks.count, 1)
            XCTAssertEqual(blocks[0].text, "Let me think...")
        } else {
            XCTFail("Expected .reasoning segment")
        }
    }

    func testActivityBecomesToolTraceSegment() {
        var card = SwarmLiveCardState(swarmId: "sa-test4")
        let activity = TaskActivity(
            type: "read_batch_started",
            title: "Reading files",
            detail: "/Sources/Auth.swift",
            payload: ["swarm_id": "sa-test4"],
            timestamp: Date(),
            phase: .searching,
            isRunning: true,
            groupId: nil
        )
        card.transcript = [
            SubagentTranscriptEntry.activity(activity),
        ].compactMap { $0 }
        let segments = SubagentChatSegmentBuilder.build(from: card)
        XCTAssertEqual(segments.count, 1)
        if case .toolTrace(_, let events) = segments[0] {
            XCTAssertEqual(events.count, 1)
            XCTAssertEqual(events[0].title, "Reading files")
        } else {
            XCTFail("Expected .toolTrace segment")
        }
    }

    func testResultBecomesResultSegment() {
        var card = SwarmLiveCardState(swarmId: "sa-test5")
        card.transcript = [
            SubagentTranscriptEntry.result("Analysis complete", timestamp: Date()),
        ].compactMap { $0 }
        let segments = SubagentChatSegmentBuilder.build(from: card)
        XCTAssertEqual(segments.count, 1)
        if case .result(_, let text, _) = segments[0] {
            XCTAssertEqual(text, "Analysis complete")
        } else {
            XCTFail("Expected .result segment")
        }
    }

    // MARK: - Merging Consecutive Entries

    func testConsecutiveReasoningEntriesMergedIntoOneSegment() {
        var card = SwarmLiveCardState(swarmId: "sa-merge1")
        card.transcript = [
            SubagentTranscriptEntry.reasoning("First thought", timestamp: nil),
            SubagentTranscriptEntry.reasoning("Second thought", timestamp: nil),
            SubagentTranscriptEntry.reasoning("Third thought", timestamp: nil),
        ].compactMap { $0 }
        let segments = SubagentChatSegmentBuilder.build(from: card)
        XCTAssertEqual(segments.count, 1, "Should merge into single reasoning segment")
        if case .reasoning(_, let blocks, _) = segments[0] {
            XCTAssertEqual(blocks.count, 3)
        } else {
            XCTFail("Expected .reasoning segment with 3 blocks")
        }
    }

    func testConsecutiveTextEntriesMergedIntoOneSegment() {
        var card = SwarmLiveCardState(swarmId: "sa-merge2")
        card.transcript = [
            SubagentTranscriptEntry.assistantText("Paragraph one", timestamp: nil),
            SubagentTranscriptEntry.assistantText("Paragraph two", timestamp: nil),
        ].compactMap { $0 }
        let segments = SubagentChatSegmentBuilder.build(from: card)
        XCTAssertEqual(segments.count, 1, "Should merge into single text segment")
        if case .text(_, let content, _) = segments[0] {
            XCTAssertTrue(content.contains("Paragraph one"))
            XCTAssertTrue(content.contains("Paragraph two"))
        } else {
            XCTFail("Expected .text segment")
        }
    }

    func testConsecutiveActivitiesMergedIntoOneToolTrace() {
        var card = SwarmLiveCardState(swarmId: "sa-merge3")
        let a1 = TaskActivity(type: "read", title: "Read file A", detail: nil, payload: ["swarm_id": "sa-merge3"], phase: .searching, isRunning: false, groupId: nil)
        let a2 = TaskActivity(type: "read", title: "Read file B", detail: nil, payload: ["swarm_id": "sa-merge3"], phase: .searching, isRunning: false, groupId: nil)
        card.transcript = [
            SubagentTranscriptEntry.activity(a1),
            SubagentTranscriptEntry.activity(a2),
        ].compactMap { $0 }
        let segments = SubagentChatSegmentBuilder.build(from: card)
        XCTAssertEqual(segments.count, 1, "Should merge into single toolTrace segment")
        if case .toolTrace(_, let events) = segments[0] {
            XCTAssertEqual(events.count, 2)
        } else {
            XCTFail("Expected .toolTrace segment with 2 events")
        }
    }

    // MARK: - Full Chat Sequence

    func testFullChatSequenceProducesCorrectSegments() {
        var card = SwarmLiveCardState(swarmId: "sa-full")
        let activity = TaskActivity(type: "read", title: "Read file", detail: "main.swift", payload: ["swarm_id": "sa-full"], phase: .searching, isRunning: false, groupId: nil)
        card.transcript = [
            SubagentTranscriptEntry.userPrompt("Analyze auth flow", timestamp: nil),
            SubagentTranscriptEntry.reasoning("Let me check the auth module", timestamp: nil),
            SubagentTranscriptEntry.activity(activity),
            SubagentTranscriptEntry.assistantText("Found the auth flow in main.swift", timestamp: nil),
            SubagentTranscriptEntry.result("Analysis complete: 1 issue found", timestamp: nil),
        ].compactMap { $0 }

        let segments = SubagentChatSegmentBuilder.build(from: card)
        XCTAssertEqual(segments.count, 5)
        if case .taskPrompt = segments[0] {} else { XCTFail("Expected taskPrompt at 0") }
        if case .reasoning = segments[1] {} else { XCTFail("Expected reasoning at 1") }
        if case .toolTrace = segments[2] {} else { XCTFail("Expected toolTrace at 2") }
        if case .text = segments[3] {} else { XCTFail("Expected text at 3") }
        if case .result = segments[4] {} else { XCTFail("Expected result at 4") }
    }

    // MARK: - Segment IDs are Unique

    func testSegmentIdsAreUnique() {
        var card = SwarmLiveCardState(swarmId: "sa-ids")
        let activity = TaskActivity(type: "read", title: "Read", detail: nil, payload: ["swarm_id": "sa-ids"], phase: .searching, isRunning: false, groupId: nil)
        card.transcript = [
            SubagentTranscriptEntry.userPrompt("Task", timestamp: nil),
            SubagentTranscriptEntry.reasoning("Think", timestamp: nil),
            SubagentTranscriptEntry.activity(activity),
            SubagentTranscriptEntry.assistantText("Response", timestamp: nil),
            SubagentTranscriptEntry.result("Done", timestamp: nil),
        ].compactMap { $0 }

        let segments = SubagentChatSegmentBuilder.build(from: card)
        let ids = segments.map(\.id)
        XCTAssertEqual(ids.count, Set(ids).count, "All segment IDs should be unique")
    }

    // MARK: - Live Text Streaming

    func testLiveTextAppendsStreamingSegmentWhenNoAssistantText() {
        var card = SwarmLiveCardState(swarmId: "sa-live1", status: .running)
        card.liveText = "Streaming output here..."
        card.transcript = [
            SubagentTranscriptEntry.userPrompt("Do something", timestamp: nil),
        ].compactMap { $0 }

        let segments = SubagentChatSegmentBuilder.build(from: card)
        XCTAssertEqual(segments.count, 2)
        if case .text(_, let content, let isStreaming) = segments[1] {
            XCTAssertEqual(content, "Streaming output here...")
            XCTAssertTrue(isStreaming)
        } else {
            XCTFail("Expected streaming .text segment")
        }
    }

    func testLiveTextNotDuplicatedWhenAssistantTextExists() {
        var card = SwarmLiveCardState(swarmId: "sa-live2", status: .running)
        card.liveText = "Some live text"
        card.transcript = [
            SubagentTranscriptEntry.assistantText("Already in transcript", timestamp: nil),
        ].compactMap { $0 }

        let segments = SubagentChatSegmentBuilder.build(from: card)
        // Should not add a duplicate streaming segment
        let textSegments = segments.filter {
            if case .text = $0 { return true }
            return false
        }
        XCTAssertEqual(textSegments.count, 1, "Should not duplicate live text when assistant text exists")
    }

    func testCompletedCardDoesNotAppendLiveText() {
        var card = SwarmLiveCardState(swarmId: "sa-done", status: .completed)
        card.liveText = "Old live text"

        let segments = SubagentChatSegmentBuilder.build(from: card)
        let streamingSegments = segments.filter {
            if case .text(_, _, true) = $0 { return true }
            return false
        }
        XCTAssertTrue(streamingSegments.isEmpty, "Completed cards should not have streaming segments")
    }

    // MARK: - Interleaving Breaks Merges

    func testDifferentKindsBetweenSameKindBreaksMerge() {
        var card = SwarmLiveCardState(swarmId: "sa-break")
        let activity = TaskActivity(type: "read", title: "Read", detail: nil, payload: ["swarm_id": "sa-break"], phase: .searching, isRunning: false, groupId: nil)
        card.transcript = [
            SubagentTranscriptEntry.reasoning("Think 1", timestamp: nil),
            SubagentTranscriptEntry.activity(activity),
            SubagentTranscriptEntry.reasoning("Think 2", timestamp: nil),
        ].compactMap { $0 }

        let segments = SubagentChatSegmentBuilder.build(from: card)
        XCTAssertEqual(segments.count, 3, "Activity between reasoning should break merge")
        if case .reasoning(_, let b1, _) = segments[0] { XCTAssertEqual(b1.count, 1) }
        if case .toolTrace = segments[1] {} else { XCTFail("Expected toolTrace at 1") }
        if case .reasoning(_, let b2, _) = segments[2] { XCTAssertEqual(b2.count, 1) }
    }
}

// MARK: - Helper for creating transcript entries in tests

private extension SubagentTranscriptEntry {
    init?(kind: SubagentTranscriptEntryKind, title: String, detail: String) {
        switch kind {
        case .userPrompt:
            guard let e = SubagentTranscriptEntry.userPrompt(detail, timestamp: nil) else { return nil }
            self = e
        case .reasoning:
            guard let e = SubagentTranscriptEntry.reasoning(detail, timestamp: nil) else { return nil }
            self = e
        case .assistantText:
            guard let e = SubagentTranscriptEntry.assistantText(detail, timestamp: nil) else { return nil }
            self = e
        case .result:
            guard let e = SubagentTranscriptEntry.result(detail, timestamp: nil) else { return nil }
            self = e
        case .activity:
            return nil
        }
    }
}
