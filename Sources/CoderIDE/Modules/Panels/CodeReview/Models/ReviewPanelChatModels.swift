import Foundation

// MARK: - Panel Chat Message

struct ReviewPanelMessage: Identifiable, Equatable {
    let id: UUID
    let role: ReviewPanelMessageRole
    var content: String
    let timestamp: Date
    var isStreaming: Bool

    init(
        id: UUID = UUID(),
        role: ReviewPanelMessageRole,
        content: String,
        timestamp: Date = Date(),
        isStreaming: Bool = false
    ) {
        self.id = id
        self.role = role
        self.content = content
        self.timestamp = timestamp
        self.isStreaming = isStreaming
    }
}

// MARK: - Message Role

enum ReviewPanelMessageRole: String, Equatable {
    case user
    case assistant
    case system
}

// MARK: - Preset Chips

struct ReviewChatPreset: Identifiable {
    let id: String
    let label: String
    let prompt: String
    let icon: String

    static let defaults: [ReviewChatPreset] = [
        ReviewChatPreset(
            id: "summarize",
            label: "Summarize",
            prompt: "Summarize the current code review findings concisely. Group by severity and highlight the most critical issues.",
            icon: "doc.text"
        ),
        ReviewChatPreset(
            id: "critical",
            label: "Most Critical",
            prompt: "What are the most critical findings in this review? Explain the potential impact and recommended fixes.",
            icon: "exclamationmark.triangle.fill"
        ),
        ReviewChatPreset(
            id: "howfix",
            label: "How to Fix",
            prompt: "For the top open findings, provide step-by-step fix instructions with code examples.",
            icon: "wrench.and.screwdriver"
        ),
        ReviewChatPreset(
            id: "security",
            label: "Security Check",
            prompt: "Are there any security vulnerabilities in the current findings? Analyze potential attack vectors.",
            icon: "lock.shield"
        ),
    ]
}
