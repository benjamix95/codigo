import Foundation

struct FlowLatencySnapshot: Equatable {
    let conversationId: UUID
    var streamStartedAt: Date?
    var firstEventAt: Date?
    var firstTextDeltaAt: Date?
    var streamCompletedAt: Date?

    var firstEventLatencyMs: Int? {
        milliseconds(from: streamStartedAt, to: firstEventAt)
    }

    var firstTextLatencyMs: Int? {
        milliseconds(from: streamStartedAt, to: firstTextDeltaAt)
    }

    var totalLatencyMs: Int? {
        milliseconds(from: streamStartedAt, to: streamCompletedAt)
    }

    private func milliseconds(from start: Date?, to end: Date?) -> Int? {
        guard let start, let end else { return nil }
        return max(0, Int(end.timeIntervalSince(start) * 1000))
    }
}

@MainActor
final class FlowDiagnosticsStore: ObservableObject {
    @Published private(set) var snapshots: [UUID: FlowLatencySnapshot] = [:]

    func reset(for conversationId: UUID) {
        snapshots[conversationId] = FlowLatencySnapshot(
            conversationId: conversationId,
            streamStartedAt: nil,
            firstEventAt: nil,
            firstTextDeltaAt: nil,
            streamCompletedAt: nil
        )
    }

    func record(
        signal: ConversationFlowCoordinator.StreamSignal,
        conversationId: UUID
    ) {
        var snapshot = snapshots[conversationId] ?? FlowLatencySnapshot(
            conversationId: conversationId,
            streamStartedAt: nil,
            firstEventAt: nil,
            firstTextDeltaAt: nil,
            streamCompletedAt: nil
        )

        switch signal {
        case .streamStarted(let at):
            snapshot.streamStartedAt = snapshot.streamStartedAt ?? at
            snapshot.streamCompletedAt = nil
        case .firstEvent(let at):
            snapshot.firstEventAt = snapshot.firstEventAt ?? at
        case .firstTextDelta(let at):
            snapshot.firstTextDeltaAt = snapshot.firstTextDeltaAt ?? at
        case .streamCompleted(let at):
            snapshot.streamCompletedAt = at
        }

        snapshots[conversationId] = snapshot
    }

    func snapshot(for conversationId: UUID?) -> FlowLatencySnapshot? {
        guard let conversationId else { return nil }
        return snapshots[conversationId]
    }
}
