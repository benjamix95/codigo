import CoderEngine
import Foundation

// MARK: - Chat Message Operations

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
        guard let index = chatMessages.firstIndex(where: { $0.id == id }) else {
            return
        }
        chatMessages[index].content = content
        chatMessages[index].isStreaming = false
        setChatProcessing(false, startedAt: nil)
        persistChatState()
    }

    func appendPanelSystemMessage(
        _ text: String,
        kind: ReviewPanelMessageKind = .statusNote,
        selectChatTab: Bool = false
    ) {
        if selectChatTab {
            selectTab(.chat)
        }
        let message: ReviewPanelMessage
        switch kind {
        case .findingMutation:
            message = ReviewPanelChatMessageFactory.findingUpdate(text: text)
        default:
            message = ReviewPanelMessage(
                role: .system,
                kind: kind,
                content: text
            )
        }
        appendChatMessage(message)
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
        let verdictPart = parts.count > 1 ? parts.dropFirst().joined(separator: separator) : ""

        let heading = "### \(sectionTitle)"
        if logPart.contains("\n\(trimmedLine)\n")
            || logPart.hasSuffix("\n\(trimmedLine)")
            || logPart.contains("\n\(trimmedLine)")
        {
            return
        }

        if !logPart.contains(heading) {
            if !logPart.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                logPart += "\n\n"
            }
            logPart += heading + "\n"
        } else if !logPart.hasSuffix("\n") {
            logPart += "\n"
        }

        logPart += trimmedLine + "\n"
        let rebuilt = verdictPart.isEmpty
            ? logPart.trimmingCharacters(in: .whitespacesAndNewlines)
            : logPart.trimmingCharacters(in: .whitespacesAndNewlines) + separator + verdictPart
        chatMessages[index].content = rebuilt
        persistChatState()
    }
}
