import AppKit
import CoderEngine
import SwiftUI
import UniformTypeIdentifiers

extension ChatPanelView {
    internal func appendTechnicalErrorMessage(_ message: String, in conversationId: UUID?) {
        let normalized = normalizeTechnicalErrorMessage(message)
        if let conversationId,
            let last = chatStore.conversation(for: conversationId)?.messages.last,
            last.role == .assistant,
            last.content == normalized
        {
            return
        }
        chatStore.addMessage(
            ChatMessage(role: .assistant, content: normalized, isStreaming: false),
            to: conversationId
        )
    }

    internal func normalizeTechnicalErrorMessage(_ message: String) -> String {
        let raw = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else {
            return "[Error] Operation not completed. Try again."
        }
        let lower = raw.lowercased()
        if lower.contains("coderengine.coderengineerror error 0")
            || (lower.contains("operation couldn") && lower.contains("coderengine"))
        {
            return
                "[Runtime error] Operation not completed by CLI provider. Check authentication and usage limits, then try again."
        }
        return raw
    }

    internal func userFacingStreamError(_ error: Error) -> String {
        if isNetworkError(error) && !networkMonitor.isPathSatisfied {
            return "[Connection lost] The network connection was interrupted. Reconnecting…"
        }
        let detail = String(describing: error)
        let normalized = normalizeTechnicalErrorMessage(detail)
        if normalized == detail.trimmingCharacters(in: .whitespacesAndNewlines) {
            return "[Error] \(error.localizedDescription)"
        }
        return normalized
    }

    internal func isNetworkError(_ error: Error) -> Bool {
        let nsError = error as NSError
        let networkCodes: Set<Int> = [
            NSURLErrorNotConnectedToInternet,
            NSURLErrorNetworkConnectionLost,
            NSURLErrorTimedOut,
            NSURLErrorCannotFindHost,
            NSURLErrorCannotConnectToHost,
            NSURLErrorDNSLookupFailed,
            NSURLErrorInternationalRoamingOff,
            NSURLErrorDataNotAllowed,
        ]
        if nsError.domain == NSURLErrorDomain && networkCodes.contains(nsError.code) {
            return true
        }
        let desc = String(describing: error).lowercased()
        return desc.contains("network connection was lost")
            || desc.contains("not connected to the internet")
            || desc.contains("the internet connection appears to be offline")
            || desc.contains("a data connection is not currently allowed")
    }

    internal func isInterruptedStreamError(_ error: Error) -> Bool {
        if Task.isCancelled { return true }
        if error is CancellationError { return true }

        let nsError = error as NSError
        if nsError.domain == NSCocoaErrorDomain, nsError.code == NSUserCancelledError {
            return true
        }

        if executionController.runState == .stopping {
            return true
        }

        let normalized = String(describing: error).lowercased()
        if normalized.contains("cancellationerror")
            || normalized.contains("cancelled")
            || normalized.contains("canceled")
        {
            return true
        }

        return false
    }
}
