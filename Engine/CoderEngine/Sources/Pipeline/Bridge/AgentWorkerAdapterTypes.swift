import Foundation
import os

// MARK: - AgentWorkerAdapterConfig

public struct AgentWorkerAdapterConfig: Sendable {
    public let streamTimeoutSec: Int
    public let maxTextLength: Int

    public init(
        streamTimeoutSec: Int = 300,
        maxTextLength: Int = 500_000
    ) {
        self.streamTimeoutSec = streamTimeoutSec
        self.maxTextLength = maxTextLength
    }
}

// MARK: - AgentWorkerDelegate

/// Delegate per ricevere eventi di streaming in tempo reale dal worker.
public protocol AgentWorkerDelegate: AnyObject, Sendable {
    func worker(
        jobId: String, taskId: String,
        didEmitTextDelta delta: String
    ) async
    func worker(
        jobId: String, taskId: String,
        didReplace replacement: String
    ) async
    func worker(
        jobId: String, taskId: String,
        didEmitRaw type: String, payload: [String: String]
    ) async
}

// MARK: - AgentWorkerError

public enum AgentWorkerError: Error, Sendable {
    case streamError(String)
    case timeout(taskId: String, elapsedMs: Int)
}

extension AgentWorkerError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .streamError(let message):
            let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? "Il provider ha terminato lo stream senza dettagli di errore." : trimmed
        case .timeout(let taskId, let elapsedMs):
            return "Timeout del worker pipeline per \(taskId) dopo \(elapsedMs)ms."
        }
    }
}
