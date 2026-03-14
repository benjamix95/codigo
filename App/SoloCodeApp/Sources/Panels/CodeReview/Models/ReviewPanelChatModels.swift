import Foundation

struct ReviewPanelMessagePresentation: Equatable, Codable {
    let sections: [ReviewPanelChatStructuredSection]
}

// MARK: - Panel Chat Message

struct ReviewPanelMessage: Identifiable, Equatable, Codable {
    let id: UUID
    let role: ReviewPanelMessageRole
    let kind: ReviewPanelMessageKind
    var content: String
    var presentation: ReviewPanelMessagePresentation?
    let timestamp: Date
    var isStreaming: Bool

    init(
        id: UUID = UUID(),
        role: ReviewPanelMessageRole,
        kind: ReviewPanelMessageKind = .plain,
        content: String,
        presentation: ReviewPanelMessagePresentation? = nil,
        timestamp: Date = Date(),
        isStreaming: Bool = false
    ) {
        self.id = id
        self.role = role
        self.kind = kind
        self.content = content
        self.presentation = presentation
        self.timestamp = timestamp
        self.isStreaming = isStreaming
    }
}

// MARK: - Message Role

enum ReviewPanelMessageRole: String, Equatable, Codable {
    case user
    case assistant
    case system
}

enum ReviewPanelMessageKind: String, Equatable, Codable {
    case plain
    case commandInvocation
    case reviewRun
    case findingMutation
    case summary
    case statusNote

    var title: String {
        switch self {
        case .plain: return "Message"
        case .commandInvocation: return "Command"
        case .reviewRun: return "Review Run"
        case .findingMutation: return "Finding Update"
        case .summary: return "Summary"
        case .statusNote: return "Status"
        }
    }

    var icon: String {
        switch self {
        case .plain: return "bubble.left"
        case .commandInvocation: return "terminal"
        case .reviewRun: return "waveform.path.ecg"
        case .findingMutation: return "wrench.and.screwdriver"
        case .summary: return "doc.text"
        case .statusNote: return "info.circle"
        }
    }
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
