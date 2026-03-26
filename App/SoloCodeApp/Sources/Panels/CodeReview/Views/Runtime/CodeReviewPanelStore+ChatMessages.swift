import CoderEngine
import Foundation
import os.log

// MARK: - Panel transcript (Rust runtime only; chat UI removed)

private let reviewPanelLog = Logger(subsystem: "com.coderIDE", category: "CodeReviewPanel")

extension CodeReviewPanelStore {
    func appendChatMessage(_ message: ReviewPanelMessage) {
        chatMessages.append(message)
        persistChatState()
    }

    func updateChatMessage(id: UUID, content: String) {
        guard let index = chatMessages.firstIndex(where: { $0.id == id }) else {
            return
        }
        chatMessages[index].content = content
        persistChatState()
    }

    func finalizeChatStreamComplete(id: UUID) {
        guard let index = chatMessages.firstIndex(where: { $0.id == id }) else {
            return
        }
        chatMessages[index].isStreaming = false
        setChatProcessing(false, startedAt: nil)
        persistChatState()
    }

    func finalizeChatMessage(
        id: UUID,
        content: String,
        isError: Bool
    ) {
        _ = isError
        guard let index = chatMessages.firstIndex(where: { $0.id == id }) else {
            return
        }
        chatMessages[index].content = content
        chatMessages[index].isStreaming = false
        setChatProcessing(false, startedAt: nil)
        persistChatState()
    }

    /// Logs panel notices (chat tab removed; no in-panel feed).
    func appendPanelSystemMessage(
        _ text: String,
        kind: ReviewPanelMessageKind = .statusNote
    ) {
        reviewPanelLog.notice("[\(kind.rawValue, privacy: .public)] \(text, privacy: .public)")
    }

    func appendVerifiedFindingSystemMessage(
        sessionId: String,
        findingId: String,
        title: String,
        detail: String? = nil
    ) {
        let body = detail.map { "\(title) [\(findingId)] [\(sessionId)]\n\($0)" }
            ?? "\(title) [\(findingId)] [\(sessionId)]"
        reviewPanelLog.notice("\(body, privacy: .public)")
    }

    func appendReviewRunSectionLine(
        id: UUID,
        sectionTitle: String,
        line: String
    ) {
        guard let index = chatMessages.firstIndex(where: { $0.id == id }) else {
            return
        }

        let trimmedLine = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedLine.isEmpty else { return }

        let separator = "\n---\n"
        let current = chatMessages[index].content
        let parts = current.components(separatedBy: separator)
        var logPart = parts.first ?? ""
        let verdictPart = parts.count > 1
            ? parts.dropFirst().joined(separator: separator)
            : ""

        let heading = "### \(sectionTitle)"

        if isDuplicateLine(trimmedLine, inSection: sectionTitle, ofLog: logPart) {
            return
        }

        if !logPart.contains(heading) {
            if !logPart.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                logPart += "\n\n"
            }
            logPart += heading + "\n" + trimmedLine + "\n"
        } else {
            logPart = insertLineInSection(
                logPart: logPart,
                heading: heading,
                line: trimmedLine
            )
        }

        let rebuilt = verdictPart.isEmpty
            ? logPart.trimmingCharacters(in: .whitespacesAndNewlines)
            : logPart.trimmingCharacters(in: .whitespacesAndNewlines)
                + separator + verdictPart
        chatMessages[index].content = rebuilt
        persistChatState()
    }
}
