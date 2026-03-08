import Foundation
import CoderEngine

actor IteratorHolder<Stream: AsyncSequence> {
    private var iterator: Stream.AsyncIterator

    init(_ stream: Stream) {
        self.iterator = stream.makeAsyncIterator()
    }

    func next() async throws -> Stream.AsyncIterator.Element? {
        var iterator = self.iterator
        let value = try await iterator.next()
        self.iterator = iterator
        return value
    }
}

enum StreamWatchdogError: LocalizedError {
    case noEvents(timeout: Int)
    case stalled(timeout: Int)

    var errorDescription: String? {
        switch self {
        case .noEvents(let timeout):
            return "No events received from provider within \(timeout)s."
        case .stalled(let timeout):
            return "Stream stalled: no updates for \(timeout)s."
        }
    }
}

extension ConversationFlowCoordinator {
    func nextEvent(
        withinSeconds timeout: Int,
        isInitialPoll: Bool,
        pendingTask: Task<StreamEvent?, Error>
    ) async throws -> StreamEvent? {
        try await withThrowingTaskGroup(of: StreamEvent?.self) { group in
            group.addTask {
                try await pendingTask.value
            }
            group.addTask {
                let safeTimeout = max(1, timeout)
                try await Task.sleep(nanoseconds: UInt64(safeTimeout) * 1_000_000_000)
                throw isInitialPoll
                    ? StreamWatchdogError.noEvents(timeout: timeout)
                    : StreamWatchdogError.stalled(timeout: timeout)
            }
            do {
                guard let value = try await group.next() else {
                    throw StreamWatchdogError.stalled(timeout: timeout)
                }
                group.cancelAll()
                return value
            }
        }
    }

    func logStreamDiagnostic(_ message: String) {
        NSLog("[StreamDiag] %@", message)
    }
}
