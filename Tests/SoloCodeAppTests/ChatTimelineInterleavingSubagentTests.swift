import XCTest
@testable import CoderIDE

final class ChatTimelineInterleavingSubagentTests: ChatTimelineInterleavingTestCase {
    func testInterleaverPlacesLiveSubagentIntoAnchoredSectionUsingMatchingSwarmSequence() {
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
                roleType: "reviewer",
                status: .running
            ),
        ]

        let segments = ChatTurnTimelineInterleaver.segments(
            blocks: blocks,
            traceEvents: events,
            liveSubagentCards: liveCards
        )

        let liveGroupSequences = segments.compactMap { segment -> Int? in
            if case .completedSubagentsGroup(_, let group, let sequence) = segment,
               group.entries.contains(where: { $0.id == "sa-review" && $0.isRunning }) {
                return sequence
            }
            return nil
        }

        XCTAssertEqual(liveGroupSequences, [2])
    }

    func testInterleaverKeepsTrailingCompletedSubagentGroupAtChronologicalEndWithoutTraceAnchor() {
        let blocks = [
            makeBlock(id: "text-0", kind: .primaryText, text: "Analisi", sequence: 0),
            makeBlock(id: "text-1", kind: .primaryText, text: "Risposta finale", sequence: 2),
        ]
        let snapshots = [makeSnapshot(swarmId: "sa-review", title: "Reviewer")]

        let segments = ChatTurnTimelineInterleaver.segments(
            blocks: blocks,
            traceEvents: [],
            subagentSnapshots: snapshots
        )

        XCTAssertEqual(segments.map(\.sequence), [0, 2, 3])
    }

    func testInterleaverAnchorsCompletedSubagentGroupUsingMatchingSwarmSequenceBetweenTextBlocks() {
        let blocks = [
            makeBlock(id: "text-0", kind: .primaryText, text: "Analisi", sequence: 0),
            makeBlock(id: "text-1", kind: .primaryText, text: "Risposta finale", sequence: 4),
        ]
        let events = [
            makeEvent(sequence: 2, title: "Spawn reviewer", swarmId: "sa-review"),
            makeEvent(sequence: 3, title: "Reviewer update", swarmId: "sa-review"),
        ]
        let snapshots = [makeSnapshot(swarmId: "sa-review", title: "Reviewer")]

        let segments = ChatTurnTimelineInterleaver.segments(
            blocks: blocks,
            traceEvents: events,
            subagentSnapshots: snapshots
        )

        let groupedSegment = try! XCTUnwrap(segments.first(where: { segment in
            if case .completedSubagentsGroup(_, let group, _) = segment {
                return group.cards.map(\.swarmId) == ["sa-review"]
            }
            return false
        }))

        if case .completedSubagentsGroup(_, let group, let sequence) = groupedSegment {
            XCTAssertEqual(sequence, 2)
            XCTAssertEqual(group.cards.map(\.swarmId), ["sa-review"])
        } else {
            XCTFail("Expected completedSubagentsGroup segment")
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
                roleType: "reviewer",
                status: .running
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

    func testInterleaverCreatesMultipleCompletedSubagentSectionsForSeparateLaunchWaves() {
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
            makeSnapshot(swarmId: "sa-review", title: "Reviewer"),
            makeSnapshot(swarmId: "sa-explorer", title: "Explorer"),
        ]

        let segments = ChatTurnTimelineInterleaver.segments(
            blocks: blocks,
            traceEvents: events,
            subagentSnapshots: snapshots
        )

        let groups = segments.compactMap { segment -> ChatTurnCompletedSubagentsGroup? in
            if case .completedSubagentsGroup(_, let group, _) = segment {
                return group
            }
            return nil
        }

        XCTAssertEqual(groups.count, 2)
        XCTAssertEqual(groups[0].cards.map(\.swarmId), ["sa-explorer"])
        XCTAssertEqual(groups[0].sequence, 1)
        XCTAssertEqual(groups[1].cards.map(\.swarmId), ["sa-review"])
        XCTAssertEqual(groups[1].sequence, 4)
    }

    func testInterleaverGroupsCompletedSubagentsLaunchedInSameWaveIntoSingleSection() {
        let blocks = [
            makeBlock(id: "text-0", kind: .primaryText, text: "Start", sequence: 0),
            makeBlock(id: "text-1", kind: .primaryText, text: "End", sequence: 5),
        ]
        let events = [
            makeEvent(sequence: 1, title: "Spawn explorer", swarmId: "sa-explorer"),
            makeEvent(sequence: 2, title: "Spawn reviewer", swarmId: "sa-review"),
            makeEvent(sequence: 4, title: "Reviewer update", swarmId: "sa-review"),
        ]
        let snapshots = [
            makeSnapshot(swarmId: "sa-explorer", title: "Explorer"),
            makeSnapshot(swarmId: "sa-review", title: "Reviewer"),
        ]

        let segments = ChatTurnTimelineInterleaver.segments(
            blocks: blocks,
            traceEvents: events,
            subagentSnapshots: snapshots
        )

        let groups = segments.compactMap { segment -> ChatTurnCompletedSubagentsGroup? in
            if case .completedSubagentsGroup(_, let group, _) = segment {
                return group
            }
            return nil
        }

        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(groups[0].cards.map(\.swarmId), ["sa-explorer", "sa-review"])
        XCTAssertEqual(groups[0].sequence, 1)
    }

    func testInterleaverAnchorsRunningAndCompletedCardsInsideSections() {
        let blocks = [
            makeBlock(id: "text-0", kind: .primaryText, text: "Start", sequence: 0),
            makeBlock(id: "text-1", kind: .primaryText, text: "End", sequence: 5),
        ]
        let events = [
            makeEvent(sequence: 1, title: "Spawn explorer", swarmId: "sa-explorer"),
            makeEvent(sequence: 3, title: "Spawn reviewer", swarmId: "sa-review"),
        ]
        let liveCards = [
            SwarmLiveCardState(
                swarmId: "sa-explorer",
                displayName: "Explorer",
                roleType: "explorer",
                status: .completed
            ),
            SwarmLiveCardState(
                swarmId: "sa-review",
                displayName: "Reviewer",
                roleType: "reviewer",
                status: .running
            ),
        ]
        let snapshots = [
            makeSnapshot(swarmId: "sa-review", title: "Reviewer", summary: "stale"),
        ]

        let segments = ChatTurnTimelineInterleaver.segments(
            blocks: blocks,
            traceEvents: events,
            liveSubagentCards: liveCards,
            subagentSnapshots: snapshots
        )

        let groups = segments.compactMap { segment -> ChatTurnCompletedSubagentsGroup? in
            if case .completedSubagentsGroup(_, let group, _) = segment {
                return group
            }
            return nil
        }

        XCTAssertEqual(groups.count, 2)
        XCTAssertEqual(groups[0].cards.map(\.swarmId), ["sa-explorer"])
        XCTAssertFalse(groups[0].hasRunningEntries)
        XCTAssertEqual(groups[1].cards.map(\.swarmId), ["sa-review"])
        XCTAssertTrue(groups[1].hasRunningEntries)
        XCTAssertEqual(segments.map(\.sequence), [0, 1, 1, 3, 3, 5])
    }

    func testInterleaverPrefersLiveTerminalCardOverPersistedSnapshotForSameSwarm() {
        let snapshots = [
            makeSnapshot(
                swarmId: "sa-review",
                title: "Reviewer",
                summary: "snapshot"
            ),
        ]
        let liveCards = [
            SwarmLiveCardState(
                swarmId: "sa-review",
                displayName: "Reviewer",
                roleType: "reviewer",
                status: .completed,
                summary: "live"
            ),
        ]

        let segments = ChatTurnTimelineInterleaver.segments(
            blocks: [makeBlock(id: "text-0", kind: .primaryText, text: "Done", sequence: 0)],
            traceEvents: [],
            liveSubagentCards: liveCards,
            subagentSnapshots: snapshots
        )

        let group = try! XCTUnwrap(segments.compactMap { segment -> ChatTurnCompletedSubagentsGroup? in
            if case .completedSubagentsGroup(_, let group, _) = segment {
                return group
            }
            return nil
        }.first)

        XCTAssertEqual(group.cards.count, 1)
        XCTAssertEqual(group.cards.first?.summary, "live")
    }

    private func makeSnapshot(
        swarmId: String,
        title: String,
        status: SwarmCardStatus = .completed,
        summary: String? = nil
    ) -> SubagentCardSnapshot {
        SubagentCardSnapshot(
            swarmId: swarmId,
            status: status,
            title: title,
            detail: "done",
            summary: summary,
            errorCount: status == .failed ? 1 : 0,
            warningCount: 0,
            resultPreview: "done",
            transcript: nil
        )
    }
}
