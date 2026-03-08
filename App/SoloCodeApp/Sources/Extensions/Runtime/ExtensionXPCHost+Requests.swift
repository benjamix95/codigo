import Foundation

extension ExtensionXPCHost {
    typealias XPCRequestCompletion<T> = @Sendable (Result<T, Error>) -> Void

    final class XPCRequestState: @unchecked Sendable {
        let lock = NSLock()
        var didResume = false
        var timeoutTask: Task<Void, Never>?
    }

    func executeRequest<T>(
        pluginId: String,
        timeout: TimeInterval,
        timeoutError: @escaping @Sendable () -> Error,
        onTimeout: (@Sendable () async -> Void)? = nil,
        operation: @escaping (@escaping XPCRequestCompletion<T>) -> Void
    ) async throws -> T {
        try await withCheckedThrowingContinuation { continuation in
            let state = XPCRequestState()

            @Sendable func resume(_ result: Result<T, Error>) {
                state.lock.lock()
                guard !state.didResume else {
                    state.lock.unlock()
                    return
                }
                state.didResume = true
                let runningTimeoutTask = state.timeoutTask
                state.lock.unlock()

                runningTimeoutTask?.cancel()
                continuation.resume(with: result)
            }

            let safeTimeout = max(timeout, 0)
            state.timeoutTask = Task {
                if safeTimeout > 0 {
                    try? await Task.sleep(
                        nanoseconds: UInt64(safeTimeout * 1_000_000_000)
                    )
                } else {
                    await Task.yield()
                }
                guard !Task.isCancelled else { return }
                await onTimeout?()
                resume(.failure(timeoutError()))
            }

            operation { result in
                resume(result)
            }
        }
    }
}
