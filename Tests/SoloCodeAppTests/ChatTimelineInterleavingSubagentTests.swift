import XCTest
@testable import CoderIDE

final class ChatTimelineInterleavingSubagentTests: ChatTimelineInterleavingTestCase {
    func testInterleaverPlacesLiveSubagentCardInlineUsingMatchingSwarmSequence() {
        let blocks = [
            makeBlock(id: "text-0", kind: .primaryText, text: "Hi", sequence: 0),
            makeBlock(id: "text-1", kind: .primaryText, text: "Bye", sequence: 4),
        ]
        let events = [
            makeEvent(sequence: 2, title: "Spawn reviewer", swarmId: "sa-review"),
            makeEvent(sequence: 3, title: "Reviewer update", swarmId: "sa-review"),
        ]
        let liveCards = [
            SwarmLiveCardState(
                swarmId: "sa-review",
                displayName: "Reviewer",
                roleType: "reviewer"
            ),
        ]

        let segments = ChatTurnTimelineInterleaver.segments(
            blocks: blocks,
            traceEvents: events,
            liveSubagentCards: liveCards
        )

        let liveCardSequences = segments.compactMap { segment -> Int? in
            if case .subagentLiveCard(_, let card, let sequence) = segment, card.swarmId == "sa-review" {
                return sequence
            }
            return nil
        }

        XCTAssertEqual(liveCardSequences, [2])
    }

    func testInterleaverKeepsTrailingSubagentSnapshotAtChronologicalEndWithoutTraceAnchor() {
        let blocks = [
            makeBlock(id: "text-0", kind: .primaryText, text: "Analisi", sequence: 0),
            makeBlock(id: "text-1", kind: .primaryText, text: "Risposta finale", sequence: 2),
        ]
        let snapshots = [
            SubagentCardSnapshot(
                swarmId: "sa-review",
                status: .completed,
                title: "Reviewer",
                detail: "done",
                summary: "ok",
                errorCount: 0,
                warningCount: 0,
                resultPreview: "done",
                transcript: nil
            ),
        ]

        let segments = ChatTurnTimelineInterleaver.segments(
            blocks: blocks,
            traceEvents: [],
            subagentSnapshots: snapshots
        )

        XCTAssertEqual(segments.map(\.sequence), [0, 2, 3])
    }

    func testInterleaverAnchorsSnapshotUsingMatchingSwarmSequenceBetweenTextBlocks() {
        let blocks = [
            makeBlock(id: "text-0", kind: .primaryText, text: "Analisi", sequence: 0),
            makeBlock(id: "text-1", kind: .primaryText, text: "Risposta finale", sequence: 4),
        ]
        let events = [
            makeEvent(sequence: 2, title: "Spawn reviewer", swarmId: "sa-review"),
            makeEvent(sequence: 3, title: "Reviewer update", swarmId: "sa-review"),
        ]
        let snapshots = [
            SubagentCardSnapshot(
                swarmId: "sa-review",
                status: .completed,
                title: "Reviewer",
                detail: "done",
                summary: "ok",
                errorCount: 0,
                warningCount: 0,
                resultPreview: "done",
                transcript: nil
            ),
        ]

        let segments = ChatTurnTimelineInterleaver.segments(
            blocks: blocks,
            traceEvents: events,
            subagentSnapshots: snapshots
        )

        let snapshotSegment = try! XCTUnwrap(segments.first(where: { segment in
            if case .subagentSnapshot(_, let snapshot, _) = segment {
                return snapshot.swarmId == "sa-review"
            }
            return false
        }))

        if case .subagentSnapshot(_, _, let snapshotSequence) = snapshotSegment {
            XCTAssertEqual(snapshotSequence, 2)
        } else {
            XCTFail("Expected snapshot segment")
        }
        XCTAssertEqual(segments.map(\.sequence), [0, 2, 2, 3, 4])
    }

    func testInterleaverDoesNotCollapsePrimaryTextIntoSingleMonolithWhenSubagentAnchorsExist() {
        let blocks = [
            makeBlock(id: "text-0", kind: .primaryText, text: "Prima parte", sequence: 0),
            makeBlock(id: "text-1", kind: .primaryText, text: "Risposta finale", sequence: 4),
        ]
        let events = [
            makeEvent(sequence: 1, title: "Read file", tool: "read", path: "/tmp/A.swift"),
            makeEvent(sequence: 2, title: "Spawn reviewer", swarmId: "sa-review"),
            makeEvent(sequence: 3, title: "Write patch", tool: "write", path: "/tmp/B.swift"),
        ]
        let liveCards = [
            SwarmLiveCardState(
                swarmId: "sa-review",
                displayName: "Reviewer",
                roleType: "reviewer"
            ),
        ]

        let segments = ChatTurnTimelineInterleaver.segments(
            blocks: blocks,
            traceEvents: events,
            liveSubagentCards: liveCards
        )

        XCTAssertEqual(segments.map(\.sequence), [0, 1, 2, 3, 4])
        XCTAssertEqual(
            segments.compactMap { segment -> String? in
                if case .text(_, let content, _) = segment { return content }
                return nil
            },
            ["Prima parte", "Risposta finale"]
        )
    }

    func testInterleaverAnchorsMultipleSubagentsIndependently() {
        let blocks = [
            makeBlock(id: "text-0", kind: .primaryText, text: "Start", sequence: 0),
            makeBlock(id: "text-1", kind: .primaryText, text: "End", sequence: 6),
        ]
        let events = [
            makeEvent(sequence: 1, title: "Spawn explorer", swarmId: "sa-explorer"),
            makeEvent(sequence: 2, title: "Explorer update", swarmId: "sa-explorer"),
            makeEvent(sequence: 4, title: "Spawn reviewer", swarmId: "sa-review"),
            makeEvent(sequence: 5, title: "Reviewer update", swarmId: "sa-review"),
        ]
        let snapshots = [
            SubagentCardSnapshot(
                swarmId: "sa-review",
                status: .completed,
                title: "Reviewer",
                detail: "done",
                summary: nil,
                errorCount: 0,
                warningCount: 0,
                resultPreview: nil,
                transcript: nil
            ),
            SubagentCardSnapshot(
                swarmId: "sa-explorer",
                status: .completed,
                title: "Explorer",
                detail: "done",
                summary: nil,
                errorCount: 0,
                warningCount: 0,
                resultPreview: nil,
                transcript: nil
            ),
        ]

        let segments = ChatTurnTimelineInterleaver.segments(
            blocks: blocks,
            traceEvents: events,
            subagentSnapshots: snapshots
        )

        let anchoredSequences = segments.compactMap { segment -> String? in
            if case .subagentSnapshot(_, let snapshot, let sequence) = segment {
                return "\(snapshot.swarmId):\(sequence)"
            }
            return nil
        }

        XCTAssertEqual(
            anchoredSequences.sorted(),
            ["sa-explorer:1", "sa-review:4"]
        )
    }
}
