import XCTest
@testable import CoderIDE

final class ChatTimelineInterleavingToolGroupingTests: ChatTimelineInterleavingTestCase {
    func testInterleaverKeepsDistinctCategoriesSeparated() {
        let blocks = [
            makeBlock(id: "text-0", kind: .primaryText, text: "Hi", sequence: 0),
            makeBlock(id: "tool-marker-1", kind: .toolMarker, sequence: 1),
            makeBlock(id: "text-1", kind: .primaryText, text: "Bye", sequence: 4),
        ]
        let events = [
            makeEvent(sequence: 1, title: "Read file", tool: "read", path: "/tmp/A.swift"),
            makeEvent(sequence: 2, title: "command_execution", type: "command_execution", command: "swift test"),
            makeEvent(sequence: 3, title: "Write patch", tool: "write", path: "/tmp/B.swift"),
        ]

        let segments = ChatTurnTimelineInterleaver.segments(blocks: blocks, traceEvents: events)
        let toolSegments = segments.compactMap { segment -> ToolTraceEvent? in
            if case .toolEvent(_, let event, _) = segment { return event }
            return nil
        }

        XCTAssertEqual(toolSegments.map(\.title), ["Read file", "command_execution", "Write patch"])
        XCTAssertEqual(segments.map(\.sequence), [0, 1, 2, 3, 4])
    }

    func testInterleaverGroupsConsecutiveExplorationEvents() {
        let blocks = [
            makeBlock(id: "text-0", kind: .primaryText, text: "Hi", sequence: 0),
            makeBlock(id: "text-1", kind: .primaryText, text: "Bye", sequence: 4),
        ]
        let events = [
            makeEvent(sequence: 1, title: "read", tool: "read", path: "/tmp/ChatTurnView.swift"),
            makeEvent(sequence: 2, title: "read", tool: "read", path: "/tmp/MessageToolTraceView.swift"),
            makeEvent(sequence: 3, title: "grep", tool: "grep", query: "ToolTraceEvent"),
        ]

        let segments = ChatTurnTimelineInterleaver.segments(blocks: blocks, traceEvents: events)
        let groups = segments.compactMap { segment -> ChatTurnToolEventGroup? in
            if case .toolGroup(_, let group, _) = segment { return group }
            return nil
        }

        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(groups[0].category, .exploration)
        XCTAssertEqual(groups[0].events.count, 3)
        XCTAssertEqual(segments.map(\.sequence), [0, 1, 4])
    }

    func testInterleaverDoesNotGroupAcrossNarrativeBoundary() {
        let blocks = [
            makeBlock(id: "text-0", kind: .primaryText, text: "Hi", sequence: 0),
            makeBlock(id: "text-1", kind: .primaryText, text: "Middle", sequence: 2),
            makeBlock(id: "text-2", kind: .primaryText, text: "Bye", sequence: 4),
        ]
        let events = [
            makeEvent(sequence: 1, title: "read", tool: "read", path: "/tmp/ChatTurnView.swift"),
            makeEvent(sequence: 3, title: "read", tool: "read", path: "/tmp/ChatTurnInterleavedSegment.swift"),
        ]

        let segments = ChatTurnTimelineInterleaver.segments(blocks: blocks, traceEvents: events)
        let groupCount = segments.filter {
            if case .toolGroup = $0 { return true }
            return false
        }.count
        let eventCount = segments.filter {
            if case .toolEvent = $0 { return true }
            return false
        }.count

        XCTAssertEqual(groupCount, 0)
        XCTAssertEqual(eventCount, 2)
    }

    func testInterleaverGroupsConsecutiveTerminalEvents() {
        let blocks = [
            makeBlock(id: "text-0", kind: .primaryText, text: "Hi", sequence: 0),
            makeBlock(id: "text-1", kind: .primaryText, text: "Bye", sequence: 3),
        ]
        let events = [
            makeEvent(sequence: 1, title: "command_execution", type: "command_execution", command: "xcodebuild test"),
            makeEvent(sequence: 2, title: "command_execution", type: "command_execution", command: "swift test"),
        ]

        let segments = ChatTurnTimelineInterleaver.segments(blocks: blocks, traceEvents: events)
        let groups = segments.compactMap { segment -> ChatTurnToolEventGroup? in
            if case .toolGroup(_, let group, _) = segment { return group }
            return nil
        }

        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(groups[0].category, .terminal)
        XCTAssertEqual(groups[0].events.count, 2)
    }

    func testInterleaverDoesNotGroupTerminalAndExplorationWithSameSequenceWindow() {
        let blocks = [
            makeBlock(id: "text-0", kind: .primaryText, text: "Start", sequence: 0),
            makeBlock(id: "text-1", kind: .primaryText, text: "End", sequence: 5),
        ]
        let events = [
            makeEvent(sequence: 1, title: "read", tool: "read", path: "/tmp/File.swift"),
            makeEvent(sequence: 2, title: "command_execution", type: "command_execution", command: "swift test"),
            makeEvent(sequence: 3, title: "grep", tool: "grep", query: "struct Foo"),
            makeEvent(sequence: 4, title: "command_execution", type: "command_execution", command: "git diff"),
        ]

        let segments = ChatTurnTimelineInterleaver.segments(blocks: blocks, traceEvents: events)
        let titles = segments.map { segment -> String in
            switch segment {
            case .text(_, let content, _): return content
            case .toolEvent(_, let event, _): return event.title
            case .toolGroup(_, let group, _): return group.category.rawValue
            case .reasoning: return "reasoning"
            case .artifact: return "artifact"
            case .subagentLiveCard: return "subagent-live"
            case .subagentSnapshot: return "subagent-snapshot"
            }
        }

        XCTAssertEqual(
            titles,
            ["Start", "read", "command_execution", "grep", "command_execution", "End"]
        )
    }

    func testInterleaverDoesNotCollapseSingleEventIntoToolGroup() {
        let blocks = [
            makeBlock(id: "text-0", kind: .primaryText, text: "Start", sequence: 0),
            makeBlock(id: "text-1", kind: .primaryText, text: "End", sequence: 2),
        ]
        let events = [
            makeEvent(sequence: 1, title: "read", tool: "read", path: "/tmp/File.swift"),
        ]

        let segments = ChatTurnTimelineInterleaver.segments(blocks: blocks, traceEvents: events)
        XCTAssertEqual(
            segments.filter {
                if case .toolGroup = $0 { return true }
                return false
            }.count,
            0
        )
        XCTAssertEqual(
            segments.filter {
                if case .toolEvent = $0 { return true }
                return false
            }.count,
            1
        )
    }
}
