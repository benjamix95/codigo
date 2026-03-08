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
        let verdictPart = parts.count > 1
            ? parts.dropFirst().joined(separator: separator)
            : ""

        let heading = "### \(sectionTitle)"

        // Deduplicate: skip if this exact line already exists in the section
        if isDuplicateLine(trimmedLine, inSection: sectionTitle, ofLog: logPart) {
            return
        }

        if !logPart.contains(heading) {
            // Section doesn't exist — append new section at end of logPart
            if !logPart.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                logPart += "\n\n"
            }
            logPart += heading + "\n" + trimmedLine + "\n"
        } else {
            // Section exists — insert line at end of this specific section
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

    /// Insert a line at the end of a specific ### section,
    /// before the next ### heading or end of logPart.
    private func insertLineInSection(
        logPart: String,
        heading: String,
        line: String
    ) -> String {
        guard let headingRange = logPart.range(of: heading) else {
            return logPart + "\n" + line + "\n"
        }

        // Find the end of this section: the next ### heading
        let afterHeading = logPart[headingRange.upperBound...]
        if let nextHeadingRange = afterHeading.range(of: "\n### ") {
            // Insert before the next section
            let insertPoint = nextHeadingRange.lowerBound
            var result = String(logPart[..<insertPoint])
            if !result.hasSuffix("\n") { result += "\n" }
            result += line + "\n"
            result += String(logPart[insertPoint...])
            return result
        } else {
            // This is the last section — append at end
            var result = logPart
            if !result.hasSuffix("\n") { result += "\n" }
            result += line + "\n"
            return result
        }
    }

    /// Check if a line already exists within a specific section.
    private func isDuplicateLine(
        _ line: String,
        inSection sectionTitle: String,
        ofLog logPart: String
    ) -> Bool {
        let heading = "### \(sectionTitle)"
        guard let headingRange = logPart.range(of: heading) else {
            return false
        }
        let afterHeading = logPart[headingRange.upperBound...]

        // Find the section content (up to next heading or end)
        let sectionContent: Substring
        if let nextRange = afterHeading.range(of: "\n### ") {
            sectionContent = afterHeading[..<nextRange.lowerBound]
        } else {
            sectionContent = afterHeading
        }

        return sectionContent.contains(line)
    }
}
