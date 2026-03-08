import Foundation

enum ReviewPanelChatStructuredSectionStyle: Equatable, Codable {
    case prose
    case metadata
    case findings
    case log
    case thinking
    case activity
    case mermaid
    case outcome
}

struct ReviewPanelChatStructuredSection: Identifiable, Equatable, Codable {
    let id: String
    let title: String
    let lines: [String]
    let style: ReviewPanelChatStructuredSectionStyle
    let isInitiallyExpanded: Bool

    var displayLines: [ReviewPanelChatStructuredDisplayLine] {
        lines.enumerated().map { index, line in
            ReviewPanelChatStructuredDisplayLine(
                id: "\(id)-line-\(index)",
                text: line
            )
        }
    }
}

struct ReviewPanelChatStructuredDisplayLine: Identifiable, Equatable, Codable {
    let id: String
    let text: String
}
