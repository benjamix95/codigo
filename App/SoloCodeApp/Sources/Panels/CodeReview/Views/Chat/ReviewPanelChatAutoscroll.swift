import Foundation

enum ReviewPanelChatAutoscroll {
    static let bottomAnchorId = "review-panel-chat-bottom-anchor"

    static func messageListFingerprint(_ messages: [ReviewPanelMessage]) -> String {
        guard let last = messages.last else { return "empty" }

        return [
            String(messages.count),
            last.id.uuidString,
            last.content,
            String(last.isStreaming),
            presentationFingerprint(last.presentation),
        ].joined(separator: "|")
    }

    static func sectionLogFingerprint(_ section: ReviewPanelChatStructuredSection) -> String {
        [
            section.id,
            section.title,
            String(section.lines.count),
            section.lines.last ?? "",
        ].joined(separator: "|")
    }

    private static func presentationFingerprint(_ presentation: ReviewPanelMessagePresentation?) -> String {
        guard let presentation else { return "no-presentation" }

        return presentation.sections
            .map { section in
                [
                    section.id,
                    section.title,
                    String(section.lines.count),
                    section.lines.last ?? "",
                ].joined(separator: "~")
            }
            .joined(separator: "||")
    }
}
