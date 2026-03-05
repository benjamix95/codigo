import Foundation

/// Ruoli specializzati negli agenti della pipeline e dello swarm (§6.13).
public enum AgentRole: String, CaseIterable, Codable, Sendable, Equatable {
    case planner
    case explorer
    case coder
    case debugger
    case reviewer
    case docWriter
    case securityAuditor
    case testWriter

    /// Nome visualizzato per la UI.
    public var displayName: String {
        switch self {
        case .planner: "Planner"
        case .explorer: "Explorer"
        case .coder: "Coder"
        case .debugger: "Debugger"
        case .reviewer: "Reviewer"
        case .docWriter: "DocWriter"
        case .securityAuditor: "SecurityAuditor"
        case .testWriter: "TestWriter"
        }
    }

    /// Ruoli read-only non possono mutare il repository (§6.13).
    public var isReadOnly: Bool {
        switch self {
        case .planner, .explorer, .reviewer, .securityAuditor: true
        case .coder, .debugger, .testWriter, .docWriter: false
        }
    }
}
