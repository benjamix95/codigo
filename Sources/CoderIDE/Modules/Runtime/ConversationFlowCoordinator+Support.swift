import Foundation
import CoderEngine

final class IteratorHolder<Stream: AsyncSequence>: @unchecked Sendable {
    private var iterator: Stream.AsyncIterator

    init(_ stream: Stream) {
        self.iterator = stream.makeAsyncIterator()
    }

    func next() async throws -> Stream.AsyncIterator.Element? {
        try await iterator.next()
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

private enum StreamIterationState: Error {
    case ended
}

extension ConversationFlowCoordinator {
    func nextEvent(
        withinSeconds timeout: Int,
        isInitialPoll: Bool,
        operation: @escaping @Sendable () async throws -> StreamEvent?
    ) async throws -> StreamEvent? {
        try await withThrowingTaskGroup(of: StreamEvent.self) { group in
            group.addTask {
                guard let value = try await operation() else { throw StreamIterationState.ended }
                return value
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
            } catch StreamIterationState.ended {
                group.cancelAll()
                return nil
            }
        }
    }

    func logStreamDiagnostic(_ message: String) {
        NSLog("[StreamDiag] %@", message)
    }
}
