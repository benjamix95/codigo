import Foundation

struct AsyncTimeoutError: LocalizedError, Equatable, Sendable {
    let operationName: String
    let seconds: Int

    var errorDescription: String? {
        "\(operationName) timed out after \(seconds)s"
    }
}

enum AsyncTimeout {
    static func run<T: Sendable>(
        seconds: Int,
        operationName: String,
        operation: @escaping @Sendable () async throws -> T
    ) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask {
                try await operation()
            }
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(seconds) * 1_000_000_000)
                throw AsyncTimeoutError(operationName: operationName, seconds: seconds)
            }

            defer { group.cancelAll() }
            guard let result = try await group.next() else {
                throw AsyncTimeoutError(operationName: operationName, seconds: seconds)
            }
            return result
        }
    }
}
