import Foundation

struct TaskCompletionNotificationFormatter {
    static let `default` = TaskCompletionNotificationFormatter()

    let titleMaxChars: Int
    let bodyMaxChars: Int
    let fallbackTitle: String
    let fallbackBody: String
    let ellipsis: String

    init(
        titleMaxChars: Int = 120,
        bodyMaxChars: Int = 240,
        fallbackTitle: String = "Task completato",
        fallbackBody: String = "Apri CoderIDE per vedere i dettagli.",
        ellipsis: String = "…"
    ) {
        self.titleMaxChars = titleMaxChars
        self.bodyMaxChars = bodyMaxChars
        self.fallbackTitle = fallbackTitle
        self.fallbackBody = fallbackBody
        self.ellipsis = ellipsis
    }

    @MainActor
    func sanitizedNonEmptyText(_ text: String?) -> String? {
        guard let text else { return nil }
        let sanitized = sanitize(text)
        return sanitized.isEmpty ? nil : sanitized
    }

    @MainActor
    func makeTitle(question _: String?) -> String {
        truncate(fallbackTitle, maxChars: titleMaxChars)
    }

    @MainActor
    func makeBody(answer _: String) -> String {
        truncate(fallbackBody, maxChars: bodyMaxChars)
    }

    @MainActor
    func sanitize(_ text: String) -> String {
        let stripped = ChatStore.stripCoderideMarkers(text, aggressive: false)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !stripped.isEmpty else { return "" }

        let rawLines = stripped.components(separatedBy: .newlines)
        var normalizedLines: [String] = []
        for rawLine in rawLines {
            let line = collapseInternalWhitespace(
                rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            )
            guard !line.isEmpty else { continue }
            normalizedLines.append(line)
        }

        return normalizedLines
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func collapseInternalWhitespace(_ text: String) -> String {
        text
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
    }

    private func truncate(_ text: String, maxChars: Int) -> String {
        guard maxChars > 0 else { return "" }
        guard text.count > maxChars else { return text }

        let ellipsisCount = ellipsis.count
        guard maxChars > ellipsisCount else {
            return String(ellipsis.prefix(maxChars))
        }

        let prefixCount = maxChars - ellipsisCount
        return String(text.prefix(prefixCount)) + ellipsis
    }
}
